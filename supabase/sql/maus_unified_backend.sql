-- MAU$ unified backend: caja, ID login, and POS snapshot sync.
-- Applied to the separate MAU$ Supabase project; no MAU$ch rows are copied.

create table if not exists public.boxes (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  note text not null default '',
  opening numeric not null default 0,
  date date not null,
  created bigint not null,
  closed_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table if not exists public.moves (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  box_id text not null,
  kind text not null check (kind = any (array['entrada'::text, 'salida'::text])),
  amount numeric not null check (amount > 0),
  date date not null,
  concept text not null,
  note text not null default '',
  photo text,
  created bigint not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  constraint moves_box_owner_fk foreign key (user_id, box_id)
    references public.boxes(user_id, id) on delete cascade
);

alter table public.boxes enable row level security;
alter table public.moves enable row level security;
revoke all on public.boxes, public.moves from anon;
grant select, insert, update, delete on public.boxes, public.moves to authenticated;

drop policy if exists "Users manage their own boxes" on public.boxes;
create policy "Users manage their own boxes" on public.boxes for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists "Users manage their own moves" on public.moves;
create policy "Users manage their own moves" on public.moves for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

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
  on public.mausch_pos_sync for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Users can create their own MAU$ sales and inventory" on public.mausch_pos_sync;
create policy "Users can create their own MAU$ sales and inventory"
  on public.mausch_pos_sync for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Users can update their own MAU$ sales and inventory" on public.mausch_pos_sync;
create policy "Users can update their own MAU$ sales and inventory"
  on public.mausch_pos_sync for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create table if not exists public.mausch_identities (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9._-]{3,24}$'),
  recovery_code_hash text not null,
  recovery_attempts integer not null default 0 check (recovery_attempts >= 0),
  recovery_locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.mausch_identities enable row level security;
revoke all on public.mausch_identities from public, anon, authenticated;
grant all on public.mausch_identities to service_role;

create table if not exists public.mausch_auth_limits (
  bucket_hash text primary key,
  request_count integer not null default 0 check (request_count >= 0),
  reset_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table public.mausch_auth_limits enable row level security;
revoke all on public.mausch_auth_limits from public, anon, authenticated;
grant all on public.mausch_auth_limits to service_role;

create or replace function public.mausch_consume_auth_limit(
  p_bucket_hash text, p_max_requests integer, p_window_seconds integer
) returns boolean
language plpgsql security definer set search_path = '' as $function$
declare
  v_count integer;
  v_reset_at timestamptz;
begin
  insert into public.mausch_auth_limits (bucket_hash, request_count, reset_at)
    values (p_bucket_hash, 0, now() + make_interval(secs => p_window_seconds))
    on conflict (bucket_hash) do nothing;
  select request_count, reset_at into v_count, v_reset_at
    from public.mausch_auth_limits where bucket_hash = p_bucket_hash for update;
  if v_reset_at <= now() then
    update public.mausch_auth_limits
      set request_count = 1, reset_at = now() + make_interval(secs => p_window_seconds), updated_at = now()
      where bucket_hash = p_bucket_hash;
    return true;
  end if;
  if v_count >= p_max_requests then return false; end if;
  update public.mausch_auth_limits set request_count = v_count + 1, updated_at = now()
    where bucket_hash = p_bucket_hash;
  return true;
end;
$function$;

create or replace function public.mausch_consume_recovery_code(
  p_user_id uuid, p_code_hash text, p_next_hash text
) returns boolean
language plpgsql security definer set search_path = '' as $function$
declare
  v_code_hash text;
  v_attempts integer;
  v_locked_until timestamptz;
begin
  select recovery_code_hash, recovery_attempts, recovery_locked_until
    into v_code_hash, v_attempts, v_locked_until
    from public.mausch_identities where user_id = p_user_id for update;
  if not found then return false; end if;
  if v_locked_until is not null and v_locked_until > now() then return false; end if;
  if v_code_hash <> p_code_hash then
    v_attempts := v_attempts + 1;
    update public.mausch_identities
      set recovery_attempts = case when v_attempts >= 5 then 0 else v_attempts end,
          recovery_locked_until = case when v_attempts >= 5 then now() + interval '15 minutes' else null end,
          updated_at = now()
      where user_id = p_user_id;
    return false;
  end if;
  update public.mausch_identities
    set recovery_code_hash = p_next_hash, recovery_attempts = 0,
        recovery_locked_until = null, updated_at = now()
    where user_id = p_user_id;
  return true;
end;
$function$;

revoke all on function public.mausch_consume_auth_limit(text, integer, integer) from public, anon, authenticated;
revoke all on function public.mausch_consume_recovery_code(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mausch_consume_auth_limit(text, integer, integer) to service_role;
grant execute on function public.mausch_consume_recovery_code(uuid, text, text) to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'boxes') then
      alter publication supabase_realtime add table public.boxes;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'moves') then
      alter publication supabase_realtime add table public.moves;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mausch_pos_sync') then
      alter publication supabase_realtime add table public.mausch_pos_sync;
    end if;
  end if;
end $$;
