begin;
create table if not exists public.player_evaluations (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 player_id uuid not null references public.players(id) on delete cascade,
 team_id uuid not null references public.teams(id) on delete cascade,
 coach_user_id uuid not null references auth.users(id) on delete restrict,
 period_start date not null,
 technical_score smallint not null check(technical_score between 1 and 10),
 tactical_score smallint not null check(tactical_score between 1 and 10),
 physical_score smallint not null check(physical_score between 1 and 10),
 discipline_score smallint not null check(discipline_score between 1 and 10),
 coach_note text not null default '' check(length(coach_note)<=3000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(player_id,team_id,coach_user_id,period_start)
);
create index if not exists player_evaluations_player_period_idx on public.player_evaluations(player_id,period_start desc);
alter table public.player_evaluations enable row level security;
grant select,insert,update,delete on public.player_evaluations to authenticated;
drop policy if exists nsm_evaluations_read on public.player_evaluations;
create policy nsm_evaluations_read on public.player_evaluations for select to authenticated using (
 owner_id=(select auth.uid())
 or exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid()))
 or exists(select 1 from public.team_coaches tc where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()))
);
drop policy if exists nsm_evaluations_write on public.player_evaluations;
create policy nsm_evaluations_write on public.player_evaluations for all to authenticated using (
 owner_id=(select auth.uid())
 or exists(select 1 from public.team_coaches tc where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()))
) with check (
 owner_id=(select auth.uid())
 or exists(select 1 from public.team_coaches tc where tc.team_id=player_evaluations.team_id and tc.coach_user_id=(select auth.uid()))
);
create table if not exists public.player_monthly_votes (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 month_start date not null,
 voter_player_id uuid not null references public.players(id) on delete cascade,
 candidate_player_id uuid not null references public.players(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique(owner_id,month_start,voter_player_id),
 check(voter_player_id<>candidate_player_id)
);
create index if not exists player_monthly_votes_month_idx on public.player_monthly_votes(owner_id,month_start,candidate_player_id);
alter table public.player_monthly_votes enable row level security;
grant select,insert on public.player_monthly_votes to authenticated;
drop policy if exists nsm_monthly_votes_read on public.player_monthly_votes;
create policy nsm_monthly_votes_read on public.player_monthly_votes for select to authenticated using (owner_id=(select auth.uid()) or exists(select 1 from public.players p where p.id=voter_player_id and p.user_id=(select auth.uid())) or exists(select 1 from public.players p where p.id=candidate_player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_monthly_votes_insert on public.player_monthly_votes;
create policy nsm_monthly_votes_insert on public.player_monthly_votes for insert to authenticated with check (
 exists(select 1 from public.players voter where voter.id=voter_player_id and voter.user_id=(select auth.uid()) and voter.owner_id=owner_id)
 and exists(select 1 from public.players candidate where candidate.id=candidate_player_id and candidate.owner_id=owner_id)
 and not exists(select 1 from public.player_monthly_votes v where v.owner_id=owner_id and v.month_start=player_monthly_votes.month_start and v.voter_player_id=voter_player_id)
);
create table if not exists public.audience_polls (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null check(length(trim(title)) between 3 and 180),
 description text not null default '' check(length(description)<=1000),
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 is_published boolean not null default false,
 created_at timestamptz not null default now(),
 check(ends_at>starts_at)
);
create table if not exists public.audience_poll_options (
 id uuid primary key default gen_random_uuid(),
 poll_id uuid not null references public.audience_polls(id) on delete cascade,
 label text not null check(length(trim(label)) between 1 and 120),
 sort_order integer not null default 0
);
create table if not exists public.audience_poll_votes (
 id uuid primary key default gen_random_uuid(),
 poll_id uuid not null references public.audience_polls(id) on delete cascade,
 option_id uuid not null references public.audience_poll_options(id) on delete cascade,
 voter_key text not null check(voter_key ~ '^[a-f0-9]{32,64}$'),
 created_at timestamptz not null default now(),
 unique(poll_id,voter_key)
);
create index if not exists audience_polls_public_idx on public.audience_polls(is_published,starts_at,ends_at);
create index if not exists audience_votes_poll_idx on public.audience_poll_votes(poll_id,option_id);
alter table public.audience_polls enable row level security;
alter table public.audience_poll_options enable row level security;
alter table public.audience_poll_votes enable row level security;
grant select,insert,update,delete on public.audience_polls to authenticated;
grant select,insert,update,delete on public.audience_poll_options to authenticated;
grant select,insert on public.audience_poll_votes to anon,authenticated;
drop policy if exists nsm_audience_poll_public_read on public.audience_polls;
create policy nsm_audience_poll_public_read on public.audience_polls for select to anon,authenticated using (is_published=true and now() between starts_at and ends_at or owner_id=(select auth.uid()));
drop policy if exists nsm_audience_poll_owner_write on public.audience_polls;
create policy nsm_audience_poll_owner_write on public.audience_polls for all to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
drop policy if exists nsm_audience_options_public_read on public.audience_poll_options;
create policy nsm_audience_options_public_read on public.audience_poll_options for select to anon,authenticated using(exists(select 1 from public.audience_polls p where p.id=poll_id and ((p.is_published=true and now() between p.starts_at and p.ends_at) or p.owner_id=(select auth.uid()))));
drop policy if exists nsm_audience_options_owner_write on public.audience_poll_options;
create policy nsm_audience_options_owner_write on public.audience_poll_options for all to authenticated using(exists(select 1 from public.audience_polls p where p.id=poll_id and p.owner_id=(select auth.uid()))) with check(exists(select 1 from public.audience_polls p where p.id=poll_id and p.owner_id=(select auth.uid())));
drop policy if exists nsm_audience_vote_read_owner on public.audience_poll_votes;
create policy nsm_audience_vote_read_owner on public.audience_poll_votes for select to authenticated using(exists(select 1 from public.audience_polls p where p.id=poll_id and p.owner_id=(select auth.uid())));
drop policy if exists nsm_audience_vote_public_insert on public.audience_poll_votes;
create policy nsm_audience_vote_public_insert on public.audience_poll_votes for insert to anon,authenticated with check(
 voter_key ~ '^[a-f0-9]{32,64}$'
 and exists(select 1 from public.audience_polls p join public.audience_poll_options o on o.poll_id=p.id where p.id=poll_id and o.id=option_id and p.is_published=true and now() between p.starts_at and p.ends_at)
);
commit;