-- Publish only explicitly approved fixtures/results to the public site.
alter table public.matches add column if not exists is_public boolean not null default false;
create or replace function public.nsm_public_match_feed()
returns table(
 match_id uuid, team_name text, opponent_name text, match_date timestamptz,
 venue text, home_away text, goals_for integer, goals_against integer,
 status text, competition_name text
)
language sql stable security definer set search_path=''
as $$
 select m.id,t.name,m.opponent_name,m.match_date,m.venue,m.home_away,
        m.goals_for,m.goals_against,m.status,c.name
 from public.matches m
 join public.teams t on t.id=m.team_id
 left join public.competitions c on c.id=m.competition_id
 where m.is_public=true
   and m.status in ('scheduled','finished')
   and m.match_date >= now()-interval '90 days'
 order by m.match_date asc
 limit 30
$$;
revoke all on function public.nsm_public_match_feed() from public;
grant execute on function public.nsm_public_match_feed() to anon,authenticated;
