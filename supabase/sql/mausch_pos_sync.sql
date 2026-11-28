-- Reversible, separate snapshot storage for MAU$ Sales and Inventory.
-- Review and apply only to a Supabase development branch before any production rollout.
create table if not exists public.mausch_pos_sync (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.mausch_pos_sync enable row level security;
revoke all on public.mausch_pos_sync from anon;
grant select, insert, update on public.mausch_pos_sync to authenticated;

drop policy if exists "Users can read their own MAU$ sales and inventory" on public.mausch_pos_sync;
create policy "Users can read their own MAU$ sales and inventory"
  on public.mausch_pos_sync for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own MAU$ sales and inventory" on public.mausch_pos_sync;
create policy "Users can create their own MAU$ sales and inventory"
  on public.mausch_pos_sync for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own MAU$ sales and inventory" on public.mausch_pos_sync;
create policy "Users can update their own MAU$ sales and inventory"
  on public.mausch_pos_sync for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Realtime is optional; initial data sync also runs at login, reconnect and app foreground.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'mausch_pos_sync'
     ) then
    alter publication supabase_realtime add table public.mausch_pos_sync;
  end if;
end $$;
