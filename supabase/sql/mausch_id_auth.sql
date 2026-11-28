-- MAU$ch username/password identity mapping. Additive only: existing auth.users,
-- boxes, and moves remain in place and keep their current user_id values.
create table if not exists public.mausch_identities (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  recovery_code_hash text not null,
  recovery_attempts integer not null default 0 check (recovery_attempts >= 0),
  recovery_locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mausch_username_format check (username ~ '^[a-z0-9._-]{3,24}$')
);

alter table public.mausch_identities enable row level security;
revoke all on table public.mausch_identities from public, anon, authenticated;
grant select, insert, update, delete on table public.mausch_identities to service_role;

create table if not exists public.mausch_auth_limits (
  bucket_hash text primary key,
  request_count integer not null default 0 check (request_count >= 0),
  reset_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.mausch_auth_limits enable row level security;
revoke all on table public.mausch_auth_limits from public, anon, authenticated;
grant select, insert, update, delete on table public.mausch_auth_limits to service_role;

-- Only the server-side auth function can call this routine. It compares hashes
-- and rotates the recovery code under a row lock; five failures trigger a lock.
create or replace function public.mausch_consume_recovery_code(
  p_user_id uuid,
  p_code_hash text,
  p_next_hash text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code_hash text;
  v_attempts integer;
  v_locked_until timestamptz;
begin
  select recovery_code_hash, recovery_attempts, recovery_locked_until
    into v_code_hash, v_attempts, v_locked_until
    from public.mausch_identities
    where user_id = p_user_id
    for update;

  if not found then
    return false;
  end if;

  if v_locked_until is not null and v_locked_until > now() then
    return false;
  end if;

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
    set recovery_code_hash = p_next_hash,
        recovery_attempts = 0,
        recovery_locked_until = null,
        updated_at = now()
    where user_id = p_user_id;
  return true;
end;
$$;

revoke all on function public.mausch_consume_recovery_code(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mausch_consume_recovery_code(uuid, text, text) to service_role;

create or replace function public.mausch_consume_auth_limit(
  p_bucket_hash text,
  p_max_requests integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_reset_at timestamptz;
begin
  insert into public.mausch_auth_limits (bucket_hash, request_count, reset_at)
    values (p_bucket_hash, 0, now() + make_interval(secs => p_window_seconds))
    on conflict (bucket_hash) do nothing;

  select request_count, reset_at into v_count, v_reset_at
    from public.mausch_auth_limits
    where bucket_hash = p_bucket_hash
    for update;

  if v_reset_at <= now() then
    update public.mausch_auth_limits
      set request_count = 1,
          reset_at = now() + make_interval(secs => p_window_seconds),
          updated_at = now()
      where bucket_hash = p_bucket_hash;
    return true;
  end if;

  if v_count >= p_max_requests then
    return false;
  end if;

  update public.mausch_auth_limits
    set request_count = v_count + 1,
        updated_at = now()
    where bucket_hash = p_bucket_hash;
  return true;
end;
$$;

revoke all on function public.mausch_consume_auth_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.mausch_consume_auth_limit(text, integer, integer) to service_role;
