-- Fix: lists.created_by referenced auth.users with the default RESTRICT
-- action, so the delete_user RPC failed for anyone who had ever shared a
-- list — sharing silently made accounts undeletable.
--
-- Decision: the list belongs to the partnership, not the creator (see
-- docs/technical-decisions/004). When the creator's account is deleted, the
-- list survives for the remaining members with created_by set to NULL.
-- (list_members rows already ON DELETE CASCADE, so only the departed
-- member's membership disappears.)
--
-- Run AFTER 001, in the Supabase SQL editor (staging first).

alter table public.lists
  alter column created_by drop not null;

alter table public.lists
  drop constraint lists_created_by_fkey;

alter table public.lists
  add constraint lists_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete set null;

-- The immutability trigger must let the SET NULL referential action through:
-- that action runs an internal update on lists, and the old body would have
-- re-asserted the deleted user's id, failing the FK. Client pushes always
-- send a non-null created_by, so the preserve rule still applies to them
-- (a client sending null merely loses provenance — membership, not
-- created_by, is what authorization runs on).
create or replace function public.protect_list_immutables()
returns trigger
language plpgsql
as $$
begin
  if new.created_by is not null then
    new.created_by := old.created_by;
  end if;
  new.share_code := old.share_code;
  return new;
end;
$$;
