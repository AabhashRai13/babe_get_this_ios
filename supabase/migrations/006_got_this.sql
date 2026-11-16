-- Got This: every ticked shopping item becomes a purchase for each person on
-- the list, so the app can learn what a household buys again
-- (spec docs/superpowers/specs/2026-11-09-got-this-design.md, "Server").
-- Run AFTER 005, staging first. Projects: the one NAMED "babegetthis-staging"
-- (fpzjyusgqdzqituokrwq) is PRODUCTION; real staging is
-- "babe-get-this-real-staging" (vdiheceziirgvbudxdxg, paused, resume it first).
-- Apply by hand in the SQL editor, as 001-005 were. Never `supabase db push`:
-- it would try to re-apply 001-005, which are not recorded as applied there.
-- Compatible with old app versions: they keep working unchanged. They never
-- send items.picked_up_at, and a tick they make is recorded by the items
-- trigger (section 12) as a 'legacy' tick.

-- ─── 1. Private schema: internal functions, never reachable from the API ────

create schema got_this_private;
revoke all on schema got_this_private from public, anon, authenticated;

-- ─── 2. Tables ───────────────────────────────────────────────────────────────

-- The latest tick time. Clients send it with a tick; old versions never do.
alter table public.items
  add column picked_up_at timestamptz;

-- One row per tick event. id = got_this_private.tick_id(item_id, ticked_at).
-- Written only through got_this_private.record_tick_rows. No foreign key on
-- item_id: a tick outlives an item that is later removed.
create table public.ticks (
  id          uuid primary key,
  item_id     uuid not null,
  list_id     uuid not null references public.lists (id) on delete cascade,
  ticked_at   timestamptz not null,
  name        text not null,          -- as the item was named when ticked
  category_id text,
  undone_at   timestamptz,            -- set once; a tick never comes back
  source      text not null check (source in ('app', 'legacy', 'backfill')),
  created_at  timestamptz not null default now()
);

create index ticks_list_id_idx on public.ticks (list_id);
create index ticks_created_at_idx on public.ticks (created_at);  -- purge

-- One row per person per tick. id = got_this_private.purchase_id(user_id, tick_id).
create table public.purchases (
  id             uuid primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  tick_id        uuid not null,
  source_item_id uuid not null,       -- no foreign key, as for ticks.item_id
  name           text not null,
  category_id    text,
  bought_at      timestamptz not null,
  updated_at     timestamptz not null default now(),  -- sync clock, server-set
  deleted_at     timestamptz                          -- tombstone: the tick was undone
);

-- catch-up query shape: "my purchases changed since T"
create index purchases_user_updated_idx on public.purchases (user_id, updated_at);
create index purchases_tick_id_idx on public.purchases (tick_id);

create trigger purchases_set_updated_at
  before insert or update on public.purchases
  for each row execute function public.set_updated_at();

-- When a person last cleared their history. Only ever moves forward.
create table public.purchase_history_resets (
  user_id  uuid primary key references auth.users (id) on delete cascade,
  reset_at timestamptz not null
);

-- One "running low" notification per person per ISO week (e.g. 2026-W46).
create table public.running_low_notices (
  user_id   uuid references auth.users (id) on delete cascade,
  iso_week  text,
  posted_at timestamptz not null default now(),
  primary key (user_id, iso_week)
);

-- ─── 3. RLS: read your own rows; every write goes through a trigger or RPC ──

alter table public.ticks                   enable row level security;
alter table public.purchases               enable row level security;
alter table public.purchase_history_resets enable row level security;
alter table public.running_low_notices     enable row level security;

create policy purchases_select_own on public.purchases
  for select using (user_id = auth.uid());

create policy purchase_history_resets_select_own on public.purchase_history_resets
  for select using (user_id = auth.uid());

create policy running_low_notices_select_own on public.running_low_notices
  for select using (user_id = auth.uid());

-- Deliberately absent: any policy on ticks, and insert/update/delete policies
-- on all four tables.

-- ─── 4. Ids (must match GotThisIds on the phone) ─────────────────────────────
-- md5 of "<item id>:<epoch millis>" and "<user id>:<tick id>", read as a uuid.

create function got_this_private.tick_id(p_item uuid, p_at timestamptz)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select md5(p_item::text || ':' || (floor(extract(epoch from p_at) * 1000))::bigint::text)::uuid;
$$;

create function got_this_private.purchase_id(p_user uuid, p_tick uuid)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select md5(p_user::text || ':' || p_tick::text)::uuid;
$$;

revoke all on function got_this_private.tick_id(uuid, timestamptz) from public, anon, authenticated;
revoke all on function got_this_private.purchase_id(uuid, uuid) from public, anon, authenticated;

-- ─── 5. The only writer of ticks ─────────────────────────────────────────────
-- The first copy of a tick keeps its name, category, list, item and time.
-- A later copy can only add an undo; once undone, a tick stays undone.

create function got_this_private.record_tick_rows(
  p_id       uuid,
  p_item     uuid,
  p_list     uuid,
  p_at       timestamptz,
  p_name     text,
  p_category text,
  p_undone   timestamptz,
  p_source   text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.ticks as t
    (id, item_id, list_id, ticked_at, name, category_id, undone_at, source)
  values
    (p_id, p_item, p_list, p_at, p_name, p_category, p_undone, p_source)
  on conflict (id) do update
    set undone_at = coalesce(t.undone_at, excluded.undone_at);
$$;

revoke all on function got_this_private.record_tick_rows(uuid, uuid, uuid, timestamptz, text, text, timestamptz, text)
  from public, anon, authenticated;

-- ─── 6. Ticks become purchases ───────────────────────────────────────────────
-- Credited: the list's creator, every member who joined at or before the tick,
-- and the person who sent it (their phone's clock may put the tick before they
-- joined, and they must not lose their own purchase), minus anyone who has
-- cleared their history since then. Only the first copy of a live tick creates
-- purchases; an undo tombstones them for everyone.

create function got_this_private.ticks_make_purchases()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.undone_at is null then
    insert into public.purchases
      (id, user_id, tick_id, source_item_id, name, category_id, bought_at)
    select got_this_private.purchase_id(credited.user_id, new.id),
           credited.user_id, new.id, new.item_id, new.name, new.category_id, new.ticked_at
    from (
      select l.created_by as user_id
      from public.lists l
      where l.id = new.list_id and l.created_by is not null
      union   -- distinct: the creator is also a member
      select m.user_id
      from public.list_members m
      where m.list_id = new.list_id and m.joined_at <= new.ticked_at
      union
      -- Null without a session (the backfill); the senders of record_ticks and
      -- of old-app item pushes are members of the list.
      select auth.uid() where auth.uid() is not null
    ) credited
    -- A clear racing this tick under READ COMMITTED can let in a purchase at or
    -- before the new reset; the phone's watermark still hides it.
    where not exists (
      select 1 from public.purchase_history_resets r
      where r.user_id = credited.user_id and r.reset_at >= new.ticked_at
    )
    on conflict (id) do nothing;
  end if;

  if new.undone_at is not null then
    update public.purchases
    set deleted_at = now()
    where tick_id = new.id and deleted_at is null;
  end if;

  return null;
end;
$$;

revoke all on function got_this_private.ticks_make_purchases() from public, anon, authenticated;

create trigger ticks_make_purchases
  after insert or update on public.ticks
  for each row execute function got_this_private.ticks_make_purchases();

-- ─── 7. record_ticks: the phone's tick outbox ────────────────────────────────
-- Every event lands in exactly one of accepted / retry / rejected (arrays of
-- the ids as sent). The first failing check decides:
--   malformed, wrong id, size limits, not a member, outside +-30 days -> rejected
--   1 to 30 days ahead, item not on the server yet                   -> retry
-- An undo is honoured only within 2 hours of the tick; otherwise the tick is
-- kept as if no undo had been sent.

create function public.record_ticks(p_events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_event    jsonb;
  v_raw_id   text;
  v_id       uuid;
  v_item     uuid;
  v_list     uuid;
  v_at       timestamptz;
  v_name     text;
  v_category text;
  v_undone   timestamptz;
  v_expected uuid;
  v_class    text;
  v_accepted jsonb := '[]'::jsonb;
  v_retry    jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    raise exception 'bad_events';
  end if;

  if jsonb_array_length(p_events) > 500 then
    raise exception 'too_many_events';
  end if;

  for v_event in select e.value from jsonb_array_elements(p_events) as e(value) loop
    v_raw_id := case when jsonb_typeof(v_event) = 'object' then v_event ->> 'id' end;
    v_class := null;

    -- Malformed: not an object, a key missing, a required value null, or a
    -- value that does not parse.
    if jsonb_typeof(v_event) <> 'object'
       or not (v_event ?& array['id', 'item_id', 'list_id', 'ticked_at', 'name', 'category_id', 'undone_at'])
       or v_event ->> 'id' is null
       or v_event ->> 'item_id' is null
       or v_event ->> 'list_id' is null
       or v_event ->> 'ticked_at' is null
       or v_event ->> 'name' is null then
      v_class := 'rejected';
    else
      begin
        v_id       := (v_event ->> 'id')::uuid;
        v_item     := (v_event ->> 'item_id')::uuid;
        v_list     := (v_event ->> 'list_id')::uuid;
        v_at       := (v_event ->> 'ticked_at')::timestamptz;
        v_name     := v_event ->> 'name';
        v_category := v_event ->> 'category_id';
        v_undone   := (v_event ->> 'undone_at')::timestamptz;
        v_expected := got_this_private.tick_id(v_item, v_at);
      exception when data_exception then
        v_class := 'rejected';
      end;
    end if;

    if v_class is null and v_id <> v_expected then
      v_class := 'rejected';
    end if;

    if v_class is null
       and (char_length(v_name) not between 1 and 500
            or (v_category is not null and char_length(v_category) > 100)) then
      v_class := 'rejected';
    end if;

    if v_class is null and not exists (
         select 1 from public.list_members m
         where m.list_id = v_list and m.user_id = v_uid
       ) then
      v_class := 'rejected';
    end if;

    if v_class is null
       and (v_at < now() - interval '30 days' or v_at > now() + interval '30 days') then
      v_class := 'rejected';
    end if;

    if v_class is null and v_at > now() + interval '1 day' then
      v_class := 'retry';
    end if;

    if v_class is null and not exists (
         select 1 from public.items i
         where i.id = v_item and i.list_id = v_list
       ) then
      v_class := 'retry';
    end if;

    if v_class is null then
      v_class := 'accepted';
      if v_undone < v_at or v_undone > v_at + interval '2 hours' then
        v_undone := null;
      end if;
      perform got_this_private.record_tick_rows(
        v_id, v_item, v_list, v_at, v_name, v_category, v_undone, 'app'
      );
    end if;

    -- An event without an id string cannot be named in the reply.
    if v_raw_id is not null then
      case v_class
        when 'accepted' then v_accepted := v_accepted || jsonb_build_array(v_raw_id);
        when 'retry'    then v_retry    := v_retry    || jsonb_build_array(v_raw_id);
        else                 v_rejected := v_rejected || jsonb_build_array(v_raw_id);
      end case;
    end if;
  end loop;

  return jsonb_build_object('accepted', v_accepted, 'retry', v_retry, 'rejected', v_rejected);
end;
$$;

revoke execute on function public.record_ticks(jsonb) from public, anon;
grant  execute on function public.record_ticks(jsonb) to authenticated;

-- ─── 8. upload_own_purchases: history that cannot go through ticks ───────────
-- Guest-era purchases, and ticks on lists that never reached the server. They
-- credit only the caller. The id is recomputed here, so a caller cannot write
-- under another user's id. Rows at or before the caller's reset, outside the
-- name and category limits, missing a value or not parsing, are skipped.

create function public.upload_own_purchases(p_rows jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_reset    timestamptz;
  v_row      jsonb;
  v_tick     uuid;
  v_item     uuid;
  v_name     text;
  v_category text;
  v_at       timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'bad_rows';
  end if;

  if jsonb_array_length(p_rows) > 500 then
    raise exception 'too_many_rows';
  end if;

  select r.reset_at into v_reset
  from public.purchase_history_resets r
  where r.user_id = v_uid;

  -- One row at a time, so a row that does not parse is skipped like any other
  -- invalid row instead of failing the batch (the phone would resend it forever).
  for v_row in select e.value from jsonb_array_elements(p_rows) as e(value) loop
    continue when jsonb_typeof(v_row) <> 'object';
    begin
      v_tick     := (v_row ->> 'tick_id')::uuid;
      v_item     := (v_row ->> 'source_item_id')::uuid;
      v_name     := v_row ->> 'name';
      v_category := v_row ->> 'category_id';
      v_at       := (v_row ->> 'bought_at')::timestamptz;
    exception when data_exception then
      continue;
    end;

    continue when v_tick is null
               or v_item is null
               or v_at is null
               or v_name is null
               or char_length(v_name) not between 1 and 500
               or (v_category is not null and char_length(v_category) > 100)
               or (v_reset is not null and v_at <= v_reset);

    insert into public.purchases
      (id, user_id, tick_id, source_item_id, name, category_id, bought_at)
    values
      (got_this_private.purchase_id(v_uid, v_tick), v_uid, v_tick, v_item, v_name, v_category, v_at)
    on conflict (id) do nothing;
  end loop;
end;
$$;

revoke execute on function public.upload_own_purchases(jsonb) from public, anon;
grant  execute on function public.upload_own_purchases(jsonb) to authenticated;

-- ─── 9. clear_purchase_history ───────────────────────────────────────────────
-- p_cleared_at is when the person pressed Clear, possibly while offline. It
-- never counts from the future, and the reset never moves back (I7), so two
-- clears arriving in reverse order keep the later one. Returns the reset now
-- in force.

create function public.clear_purchase_history(p_cleared_at timestamptz)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_t     timestamptz;
  v_reset timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  v_t := least(p_cleared_at, now());

  delete from public.purchases
  where user_id = v_uid and bought_at <= v_t;

  insert into public.purchase_history_resets as r (user_id, reset_at)
  values (v_uid, v_t)
  on conflict (user_id) do update
    set reset_at = greatest(r.reset_at, excluded.reset_at)
  returning r.reset_at into v_reset;

  return v_reset;
end;
$$;

revoke execute on function public.clear_purchase_history(timestamptz) from public, anon;
grant  execute on function public.clear_purchase_history(timestamptz) to authenticated;

-- ─── 10. claim_running_low_week ──────────────────────────────────────────────
-- At most one "running low" notification per person per ISO week, across all
-- their phones: true only for the call that claims the week.

create function public.claim_running_low_week(p_week text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_week is null or p_week !~ '^\d{4}-W\d{2}$' then
    raise exception 'bad_week';
  end if;

  insert into public.running_low_notices (user_id, iso_week)
  values (v_uid, p_week)
  on conflict do nothing;

  return found;
end;
$$;

revoke execute on function public.claim_running_low_week(text) from public, anon;
grant  execute on function public.claim_running_low_week(text) to authenticated;

-- ─── 11. Purge, daily at 03:00 UTC ───────────────────────────────────────────
-- No event older than 30 days is accepted, so a tick row is never needed after
-- that; the privacy policy promises 60 days. Purchases are not touched.

create function got_this_private.purge()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.ticks where created_at < now() - interval '60 days';
  delete from public.running_low_notices where posted_at < now() - interval '8 weeks';
$$;

revoke all on function got_this_private.purge() from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;

-- Idempotent: drop a job of the same name before scheduling it.
select cron.unschedule(j.jobid) from cron.job j where j.jobname = 'got_this_purge_ticks';
select cron.schedule('got_this_purge_ticks', '0 3 * * *', 'select got_this_private.purge()');

-- ─── 12. Old app versions: record their ticks from the items they push ──────
-- Versions without Got This never send picked_up_at. When such a push ticks an
-- item (is_picked_up turns true and the push carried no tick time), stamp the
-- item with the server time and write a 'legacy' tick. A current app's own tick
-- never takes this path: it always sends a new picked_up_at with it, and the
-- tick itself arrives through record_ticks.
--
-- Whether a push carried a tick time cannot be read from the UPDATE alone: an
-- upsert that leaves picked_up_at out and one that repeats the stored value
-- look the same there. The BEFORE INSERT call sees the proposed row, so it
-- leaves a note for its own item and transaction (a setting, got_this.t<id>):
-- 'yes' when the row carried picked_up_at, 'no' when it did not. A stale push
-- from a current app (the server holds false, P after another phone's untick,
-- and the push says true, P) carries P, so it is not mistaken for an old app's
-- tick. A plain UPDATE leaves no note and is treated as an old app's, as before.
-- Otherwise picked_up_at only moves forward: greatest() ignores nulls, so a
-- null or older value from any client keeps the stored one. The exception is a
-- tick (false to true) that carries its own time: it is kept even when older
-- than the stored one, because that phone's clock is behind and it derives the
-- tick id for a later undo from its own time (arrival order, not the clock,
-- says which tick is the latest).
--
-- Clients push with upsert (INSERT ... ON CONFLICT (id) DO UPDATE). Postgres
-- fires BEFORE INSERT for the proposed row before it finds the conflict, then
-- BEFORE UPDATE for the existing row. So the INSERT branch must do nothing but
-- leave its note when the row already exists, and let the UPDATE branch decide.
--
-- Times are truncated to milliseconds, so the stored time and the tick id
-- agree with what a phone computes from the same value.

create function got_this_private.items_track_picked_up_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_note text;
begin
  if tg_op = 'INSERT' then
    -- Two concurrent first pushes of the same new ticked item can both pass
    -- this check and both write a legacy tick (different now(), different ids).
    if exists (select 1 from public.items i where i.id = new.id) then
      -- an upsert of an existing row: BEFORE UPDATE decides
      perform set_config(
        'got_this.t' || replace(new.id::text, '-', ''),
        case when new.picked_up_at is null then 'no' else 'yes' end,
        true
      );
      return new;
    end if;
    if new.is_picked_up and new.picked_up_at is null then
      new.picked_up_at := date_trunc('milliseconds', now());
      perform got_this_private.record_tick_rows(
        got_this_private.tick_id(new.id, new.picked_up_at),
        new.id, new.list_id, new.picked_up_at, left(new.name, 500), new.category_id, null, 'legacy'
      );
    end if;
    return new;
  end if;

  v_note := coalesce(current_setting('got_this.t' || replace(new.id::text, '-', ''), true), '');
  perform set_config('got_this.t' || replace(new.id::text, '-', ''), '', true);

  if not old.is_picked_up
     and new.is_picked_up
     and new.picked_up_at is not distinct from old.picked_up_at
     and v_note <> 'yes' then
    new.picked_up_at := date_trunc('milliseconds', now());
    perform got_this_private.record_tick_rows(
      got_this_private.tick_id(new.id, new.picked_up_at),
      new.id, new.list_id, new.picked_up_at, left(new.name, 500), new.category_id, null, 'legacy'
    );
  elsif not old.is_picked_up and new.is_picked_up and new.picked_up_at is not null then
    null;   -- a tick with its own time: keep it
  else
    new.picked_up_at := greatest(new.picked_up_at, old.picked_up_at);
  end if;
  return new;
end;
$$;

revoke all on function got_this_private.items_track_picked_up_at() from public, anon, authenticated;

create trigger items_track_picked_up_at
  before insert or update on public.items
  for each row execute function got_this_private.items_track_picked_up_at();

-- ─── 13. Backfill, once: items ticked before this migration ─────────────────
-- Each gets a 'backfill' tick at its last edit time, which the ticks trigger
-- turns into purchases for the people on the list then. picked_up_at is then
-- set with both items triggers off, so updated_at does not move (phones do not
-- re-download every ticked item) and no legacy tick is written. The ALTERs are
-- part of this transaction: other sessions never see the triggers disabled.

create function got_this_private.backfill_ticked_items()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  -- Lock items first, so no write lands between the ticks and the update.
  alter table public.items disable trigger items_set_updated_at;
  alter table public.items disable trigger items_track_picked_up_at;

  perform got_this_private.record_tick_rows(
    got_this_private.tick_id(i.id, date_trunc('milliseconds', i.updated_at)),
    i.id, i.list_id, date_trunc('milliseconds', i.updated_at),
    left(i.name, 500), i.category_id, null, 'backfill'
  )
  from public.items i
  where i.is_picked_up and i.deleted_at is null and i.picked_up_at is null;

  update public.items
  set picked_up_at = date_trunc('milliseconds', updated_at)
  where is_picked_up and deleted_at is null and picked_up_at is null;
  get diagnostics v_count = row_count;

  alter table public.items enable trigger items_set_updated_at;
  alter table public.items enable trigger items_track_picked_up_at;

  return v_count;
end;
$$;

revoke all on function got_this_private.backfill_ticked_items() from public, anon, authenticated;

select got_this_private.backfill_ticked_items();
