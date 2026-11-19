-- NOUN STAR MANAGER: multi-role foundation (additive; keeps existing owner-only access)
begin;

alter table public.profiles
  add column if not exists role text not null default 'coach';

alter table public.profiles
  drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('manager','coach','player'));

-- The existing single account becomes the club manager and first-team head coach.
-- Only perform this bootstrap when the project still has exactly one profile.
update public.profiles
set role = 'manager'
where id = (select id from public.profiles order by created_at asc limit 1)
  and (select count(*) from public.profiles) = 1;

alter table public.players
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create unique index if not exists players_user_id_unique
  on public.players(user_id)
  where user_id is not null;

create table if not exists public.team_coaches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  coach_user_id uuid not null references auth.users(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  unique (team_id, coach_user_id)
);

create index if not exists team_coaches_owner_id_idx
  on public.team_coaches(owner_id);
create index if not exists team_coaches_coach_user_id_idx
  on public.team_coaches(coach_user_id);
create index if not exists team_coaches_team_id_idx
  on public.team_coaches(team_id);

alter table public.team_coaches enable row level security;
drop policy if exists nsm_owner_only on public.team_coaches;
create policy nsm_owner_only on public.team_coaches
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Role changes cannot be made by editing one's own profile row.
create or replace function public.nsm_guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and coalesce(current_setting('nsm.allow_role_change', true), '') <> 'on'
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Profile role changes must use the manager role-assignment function';
  end if;
  return new;
end;
$$;

drop trigger if exists nsm_guard_profile_role_change on public.profiles;
create trigger nsm_guard_profile_role_change
before update of role on public.profiles
for each row execute function public.nsm_guard_profile_role_change();

create or replace function public.nsm_set_profile_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not exists (
       select 1 from public.profiles
       where id = auth.uid() and role = 'manager'
     ) then
    raise exception 'Only the club manager can assign account roles';
  end if;

  if p_role not in ('manager','coach','player') then
    raise exception 'Invalid profile role';
  end if;

  perform set_config('nsm.allow_role_change', 'on', true);
  update public.profiles set role = p_role where id = p_user_id;
  perform set_config('nsm.allow_role_change', 'off', true);

  if not found then
    raise exception 'Profile not found';
  end if;
end;
$$;

revoke all on function public.nsm_set_profile_role(uuid,text) from public;
grant execute on function public.nsm_set_profile_role(uuid,text) to authenticated, service_role;

commit;
