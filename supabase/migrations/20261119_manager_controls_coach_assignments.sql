-- Manager-controlled staff assignments and strict team visibility for coaches.
drop policy if exists nsm_coach_insert_own_assignments on public.team_coaches;
drop policy if exists nsm_coach_update_own_assignments on public.team_coaches;
drop policy if exists nsm_coach_delete_own_assignments on public.team_coaches;

drop policy if exists nsm_coach_read_assigned_teams on public.teams;
create policy nsm_coach_read_assigned_teams
on public.teams
for select
to authenticated
using (
  exists (
    select 1
    from public.team_coaches tc
    where tc.team_id = teams.id
      and tc.coach_user_id = (select auth.uid())
  )
);
