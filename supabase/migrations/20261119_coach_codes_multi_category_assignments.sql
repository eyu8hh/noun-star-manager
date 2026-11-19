begin;
alter table public.profiles add column if not exists coach_code text;
alter table public.profiles add column if not exists club_owner_id uuid references auth.users(id) on delete cascade;
create unique index if not exists profiles_coach_code_unique on public.profiles (lower(coach_code)) where coach_code is not null;
create index if not exists profiles_club_owner_id_idx on public.profiles(club_owner_id) where club_owner_id is not null;
alter table public.team_coaches add column if not exists assignment_type text not null default 'head';
alter table public.team_coaches drop constraint if exists team_coaches_assignment_type_check;
alter table public.team_coaches add constraint team_coaches_assignment_type_check check (assignment_type in ('head','assistant'));
create or replace function public.nsm_protect_profile_role()
returns trigger language plpgsql as $$
begin
 if new.role is distinct from old.role and current_user <> 'service_role' then
  raise exception 'Profile role can only be changed by club administration';
 end if;
 return new;
end;
$$;
drop trigger if exists nsm_protect_profile_role on public.profiles;
create trigger nsm_protect_profile_role before update on public.profiles for each row execute function public.nsm_protect_profile_role();
drop policy if exists nsm_coach_read_assigned_teams on public.teams;
create policy nsm_coach_read_assigned_teams on public.teams for select to authenticated
using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='coach' and p.club_owner_id=teams.owner_id));
drop policy if exists nsm_coach_read_own_assignments on public.team_coaches;
create policy nsm_coach_read_own_assignments on public.team_coaches for select to authenticated using (coach_user_id=(select auth.uid()));
drop policy if exists nsm_coach_insert_own_assignments on public.team_coaches;
create policy nsm_coach_insert_own_assignments on public.team_coaches for insert to authenticated with check (
 coach_user_id=(select auth.uid())
 and owner_id=(select p.club_owner_id from public.profiles p where p.id=(select auth.uid()) and p.role='coach')
 and exists(select 1 from public.teams t where t.id=team_id and t.owner_id=team_coaches.owner_id and t.is_active=true)
);
drop policy if exists nsm_coach_update_own_assignments on public.team_coaches;
create policy nsm_coach_update_own_assignments on public.team_coaches for update to authenticated using (coach_user_id=(select auth.uid())) with check (
 coach_user_id=(select auth.uid())
 and owner_id=(select p.club_owner_id from public.profiles p where p.id=(select auth.uid()) and p.role='coach')
 and exists(select 1 from public.teams t where t.id=team_id and t.owner_id=team_coaches.owner_id)
);
drop policy if exists nsm_coach_delete_own_assignments on public.team_coaches;
create policy nsm_coach_delete_own_assignments on public.team_coaches for delete to authenticated using (coach_user_id=(select auth.uid()));
commit;