-- Realtime list sharing: tables, triggers, RLS, join RPC, realtime publication.
-- Apply order matters: run this file top to bottom in the Supabase SQL editor (staging first).
-- Client contract: app upserts the list row BEFORE its item rows (membership trigger
-- on lists must fire before item RLS checks can pass for the creator).
-- Also: the FIRST share of a list must be a plain INSERT — an upsert's
-- update-arm policy check (is_list_member) runs before lists_add_creator has
-- granted membership, so upserting a brand-new list always fails RLS 42501.

-- ─── 1.1 Tables ──────────────────────────────────────────────────────────────
-- UUIDs are client-generated and identical to the Room row ids.

create table public.lists (
  id         uuid primary key,
  name       text not null,
  share_code text not null unique,
  created_by uuid not null references auth.users (id),
  updated_at timestamptz not null default now(),  -- LWW clock, server-set (trigger below)
  deleted_at timestamptz                          -- tombstone; never purged in v1
);

create table public.items (
  id           uuid primary key,
  list_id      uuid not null references public.lists (id) on delete cascade,
  name         text not null,
  quantity     text not null default '1',   -- free text in the app ("2 bags"), mirrors Room's String
  is_picked_up boolean not null default false,
  category_id  text,   -- opaque device-local id; receiving devices may not resolve it
  shop         text,
  note         text,
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create table public.list_members (
  list_id   uuid not null references public.lists (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (list_id, user_id)   -- every member is a full editor; no roles
);

create index items_list_id_idx on public.items (list_id);
-- catch-up query shape: "items of list X changed since T"
create index items_list_updated_idx on public.items (list_id, updated_at);

-- ─── 1.2 Server-set updated_at (clients are never trusted for the LWW clock) ─

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger lists_set_updated_at
  before insert or update on public.lists
  for each row execute function public.set_updated_at();

create trigger items_set_updated_at
  before insert or update on public.items
  for each row execute function public.set_updated_at();

-- Clients push whole rows (upserts), so a member's update would otherwise
-- overwrite created_by with their own id or mangle the share code. These two
-- are write-once: on UPDATE the old values always win.
create or replace function public.protect_list_immutables()
returns trigger
language plpgsql
as $$
begin
  new.created_by := old.created_by;
  new.share_code := old.share_code;
  return new;
end;
$$;

create trigger lists_protect_immutables
  before update on public.lists
  for each row execute function public.protect_list_immutables();

-- Creator automatically becomes a member (security definer: list_members has no
-- direct insert policy, so this trigger and the join RPC are the only two ways in).
create or replace function public.add_creator_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into list_members (list_id, user_id)
  values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end;
$$;

create trigger lists_add_creator
  after insert on public.lists
  for each row execute function public.add_creator_membership();

-- ─── 1.3 RLS: membership is the security boundary ────────────────────────────

alter table public.lists        enable row level security;
alter table public.items        enable row level security;
alter table public.list_members enable row level security;

-- security definer so the lists/items policies can consult list_members without
-- recursing into list_members' own RLS.
create or replace function public.is_list_member(p_list_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from list_members
    where list_id = p_list_id and user_id = auth.uid()
  );
$$;

create policy lists_select on public.lists
  for select using (public.is_list_member(id));

create policy lists_insert on public.lists
  for insert with check (created_by = auth.uid());

create policy lists_update on public.lists
  for update using (public.is_list_member(id));

create policy items_select on public.items
  for select using (public.is_list_member(list_id));

create policy items_insert on public.items
  for insert with check (public.is_list_member(list_id));

create policy items_update on public.items
  for update using (public.is_list_member(list_id));

create policy members_select_own on public.list_members
  for select using (user_id = auth.uid());

-- Deliberately absent: DELETE policies anywhere (soft delete only — an UPDATE
-- setting deleted_at), and INSERT on list_members (trigger + RPC only).

-- ─── 1.4 Join by code: the single narrow exception to membership-gated access ─

create or replace function public.join_list_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_list_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select id into v_list_id
  from lists
  where share_code = upper(trim(p_code)) and deleted_at is null;

  if v_list_id is null then
    raise exception 'invalid_code';
  end if;

  insert into list_members (list_id, user_id)
  values (v_list_id, auth.uid())
  on conflict do nothing;   -- joining twice is idempotent

  return v_list_id;
end;
$$;

revoke execute on function public.join_list_by_code(text) from anon, public;
grant  execute on function public.join_list_by_code(text) to authenticated;

-- ─── 1.5 Realtime (postgres_changes; respects RLS per subscriber) ────────────

alter publication supabase_realtime add table public.lists, public.items;

-- ─── 1.6 Negative test (run manually in SQL editor as a NON-member user JWT) ──
-- Expect zero rows / an error, never data:
--   select * from lists;
--   select * from items;
--   insert into list_members (list_id, user_id) values ('<some-list>', auth.uid());
-- And as anon (no JWT): select join_list_by_code('ABCDEF');  -- must be denied
