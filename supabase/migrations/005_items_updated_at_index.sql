-- Account-wide item catch-up reads `items where updated_at >= <sync point>`
-- with no list filter: RLS (is_list_member) scopes it to the account, the same
-- way discovery on `lists` is scoped. Before this the app asked per batch of
-- list ids, which used items_list_updated_idx; this query cannot, and without
-- an index on updated_at alone every app open is a sequential scan of items.
-- Additive and safe to run at any time. Run AFTER 004, staging first.

create index if not exists items_updated_idx on public.items (updated_at);
