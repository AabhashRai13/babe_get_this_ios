-- delete_user also deletes the caller's solo lists (docs/technical-decisions/008).
-- Since 003 every signed-in user's lists live on the server, so deleting an
-- account must take the lists nobody else joined with it — the privacy policy
-- promises it and Play requires it. Lists another member joined stay with them
-- (002 already nulls their created_by).
--
-- Previously defined only in the Supabase dashboard; this is its first time in
-- version control. The original body was exactly:
--   delete from auth.users where id = auth.uid();
-- Run AFTER 003, staging first. CREATE OR REPLACE keeps the existing grants.

create or replace function public.delete_user()
returns void
language sql
security definer
set search_path to ''
as $function$
  -- Solo lists first, while the caller's membership rows still exist to
  -- identify them (they cascade away with auth.users). Items and memberships
  -- cascade with each list.
  delete from public.lists l
  where exists (
          select 1 from public.list_members m
          where m.list_id = l.id and m.user_id = auth.uid()
        )
    and not exists (
          select 1 from public.list_members m
          where m.list_id = l.id and m.user_id <> auth.uid()
        );
  delete from auth.users where id = auth.uid();
$function$;

-- Negative tests (run manually in the SQL editor, as user A with a JWT):
--   Setup: A owns 'solo' (A only member) and 'shared' (A and B are members).
--   select public.delete_user();
--   As B: select id from public.lists where id in ('<solo>', '<shared>');
--     -> only '<shared>' remains, created_by now null.
--   As service role: select count(*) from public.lists where id = '<solo>';  -> 0
--   As service role: select count(*) from public.items where list_id = '<solo>';  -> 0
