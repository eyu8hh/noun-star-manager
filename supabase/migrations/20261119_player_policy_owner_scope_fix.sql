begin;
drop policy if exists nsm_player_change_request_insert on public.player_profile_change_requests;
create policy nsm_player_change_request_insert on public.player_profile_change_requests for insert to authenticated with check(
 status='pending' and reviewed_by is null and reviewed_at is null
 and exists(select 1 from public.players p where p.id=player_profile_change_requests.player_id and p.user_id=(select auth.uid()) and p.owner_id=player_profile_change_requests.owner_id)
);
drop policy if exists nsm_monthly_votes_insert on public.player_monthly_votes;
create policy nsm_monthly_votes_insert on public.player_monthly_votes for insert to authenticated with check(
 exists(select 1 from public.players voter where voter.id=player_monthly_votes.voter_player_id and voter.user_id=(select auth.uid()) and voter.owner_id=player_monthly_votes.owner_id)
 and exists(select 1 from public.team_players mine join public.team_players mate on mate.team_id=mine.team_id and mate.is_current=true join public.players candidate on candidate.id=mate.player_id join public.teams team on team.id=mine.team_id where mine.player_id=player_monthly_votes.voter_player_id and mine.is_current=true and candidate.id=player_monthly_votes.candidate_player_id and candidate.owner_id=player_monthly_votes.owner_id and team.owner_id=player_monthly_votes.owner_id)
 and not exists(select 1 from public.player_monthly_votes v where v.owner_id=player_monthly_votes.owner_id and v.month_start=player_monthly_votes.month_start and v.voter_player_id=player_monthly_votes.voter_player_id)
);
drop policy if exists nsm_evaluations_write on public.player_evaluations;
create policy nsm_evaluations_write on public.player_evaluations for all to authenticated using(
 owner_id=(select auth.uid())
 or exists(select 1 from public.team_coaches tc join public.teams t on t.id=tc.team_id where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()) and t.owner_id=player_evaluations.owner_id)
) with check(
 owner_id=(select auth.uid())
 or exists(select 1 from public.team_coaches tc join public.teams t on t.id=tc.team_id where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()) and t.owner_id=player_evaluations.owner_id)
);
commit;