begin;
create or replace function public.nsm_player_vote_candidates()
returns table(player_id uuid,full_name text,shirt_number integer)
language sql stable security definer set search_path=''
as $$
 select p.id,p.full_name,p.shirt_number
 from public.players me
 join public.team_players mine on mine.player_id=me.id and mine.is_current=true
 join public.team_players mate on mate.team_id=mine.team_id and mate.is_current=true
 join public.players p on p.id=mate.player_id and p.owner_id=me.owner_id
 where me.user_id=(select auth.uid()) and p.id<>me.id
 order by p.full_name
$$;
revoke all on function public.nsm_player_vote_candidates() from public;
grant execute on function public.nsm_player_vote_candidates() to authenticated;
drop policy if exists nsm_monthly_votes_insert on public.player_monthly_votes;
create policy nsm_monthly_votes_insert on public.player_monthly_votes for insert to authenticated with check(
 exists(select 1 from public.players voter where voter.id=voter_player_id and voter.user_id=(select auth.uid()) and voter.owner_id=owner_id)
 and exists(select 1 from public.team_players mine join public.team_players mate on mate.team_id=mine.team_id and mate.is_current=true join public.players candidate on candidate.id=mate.player_id where mine.player_id=voter_player_id and mine.is_current=true and candidate.id=candidate_player_id and candidate.owner_id=owner_id)
 and not exists(select 1 from public.player_monthly_votes v where v.owner_id=owner_id and v.month_start=player_monthly_votes.month_start and v.voter_player_id=voter_player_id)
);
commit;