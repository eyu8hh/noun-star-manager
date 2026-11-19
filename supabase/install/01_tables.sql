-- NOUN STAR MANAGER — Supabase bootstrap schema (draft v2)
-- Fresh, dedicated Supabase project only. Review before applying.
-- Not yet executed against the live project; not production-verified.

begin;
create extension if not exists pgcrypto;

create or replace function public.nsm_touch_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at := now(); return new; end $$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  preferred_language text not null default 'ar' check (preferred_language in ('ar','fr')),
  role text not null default 'coach' check (role in ('manager','coach','player')),
  coach_code text,
  club_owner_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_coach_code_unique on public.profiles(lower(coach_code)) where coach_code is not null;
create index if not exists profiles_club_owner_id_idx on public.profiles(club_owner_id) where club_owner_id is not null;

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  short_name text, logo_url text, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(owner_id,name)
);
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  age_category text, season text, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(owner_id,club_id,name)
);
create table public.team_coaches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  coach_user_id uuid not null references auth.users(id) on delete cascade,
  assignment_type text not null default 'head' check (assignment_type in ('head','assistant')),
  assigned_at timestamptz not null default now(),
  unique(team_id,coach_user_id)
);
create table public.players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) > 0),
  shirt_number integer check (shirt_number between 1 and 99),
  primary_position text, birth_date date, phone text, photo_url text,
  availability text not null default 'available'
    check (availability in ('available','injured','suspended','unavailable')),
  notes text, user_id uuid references auth.users(id) on delete set null, login_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists players_user_id_unique on public.players(user_id) where user_id is not null;
create unique index if not exists players_login_code_unique on public.players(lower(login_code)) where login_code is not null;
create table public.player_profile_change_requests (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 player_id uuid not null references public.players(id) on delete cascade,
 field_key text not null check (field_key in ('full_name','shirt_number','primary_position','birth_date','phone','notes')),
 current_value text,
 proposed_value text not null check (length(trim(proposed_value)) > 0 and length(proposed_value) <= 2000),
 reason text not null default '' check (length(reason) <= 1000),
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 review_note text check (review_note is null or length(review_note) <= 1000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists player_change_requests_owner_status_idx on public.player_profile_change_requests(owner_id,status,created_at desc);
create index if not exists player_change_requests_player_idx on public.player_profile_change_requests(player_id,created_at desc);
create table public.team_players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  joined_on date not null default current_date, left_on date,
  is_current boolean not null default true, created_at timestamptz not null default now(),
  check (left_on is null or left_on >= joined_on)
);
create unique index team_players_one_current on public.team_players(player_id) where is_current;
create table public.player_team_history (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  joined_on date not null, left_on date, stats_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (left_on is null or left_on >= joined_on)
);
create table public.competitions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null, season text,
  points_win integer not null default 3 check (points_win >= 0),
  points_draw integer not null default 1 check (points_draw >= 0),
  points_loss integer not null default 0 check (points_loss >= 0),
  target_position integer check (target_position is null or target_position > 0),
  notes text, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.competition_teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  competition_id uuid not null references public.competitions(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  opponent_name text, manual_points integer not null default 0,
  remaining_matches integer not null default 0 check (remaining_matches >= 0),
  played integer not null default 0 check (played >= 0),
  won integer not null default 0 check (won >= 0),
  drawn integer not null default 0 check (drawn >= 0),
  lost integer not null default 0 check (lost >= 0),
  goals_for integer not null default 0 check (goals_for >= 0),
  goals_against integer not null default 0 check (goals_against >= 0),
  check (team_id is not null or nullif(trim(opponent_name),'') is not null)
);
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  competition_id uuid references public.competitions(id) on delete set null,
  opponent_name text not null, match_date timestamptz not null, venue text,
  duration_minutes integer not null default 90 check (duration_minutes between 1 and 300),
  home_away text not null default 'home' check (home_away in ('home','away')),
  goals_for integer check (goals_for is null or goals_for >= 0),
  goals_against integer check (goals_against is null or goals_against >= 0),
  status text not null default 'scheduled'
    check (status in ('scheduled','in_progress','finished','postponed','cancelled')),
  report text, finalized_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.match_lineups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  selection_status text not null default 'starter'
    constraint match_lineups_selection_status_check check (selection_status in ('starter','substitute','not_selected','manual')),
  position text, shirt_number integer check (shirt_number is null or shirt_number between 1 and 99),
  started_minute integer check (started_minute between 0 and 300),
  ended_minute integer check (ended_minute between 0 and 300),
  minutes_played integer check (minutes_played between 0 and 300),
  unique(match_id,player_id)
);
create table public.match_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid references public.players(id) on delete set null,
  related_player_id uuid references public.players(id) on delete set null,
  event_type text not null check (event_type in
    ('goal','assist','yellow_card','red_card','substitution_on','substitution_off','note')),
  minute integer check (minute between 0 and 300), details text,
  created_at timestamptz not null default now()
);
create table public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  session_date timestamptz not null, title text, location text, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.training_drills (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  category text not null check (category in ('technical','tactical','physical','finishing','transition')),
  age_group text, players_count integer not null default 8 check (players_count between 2 and 50),
  duration_minutes integer not null default 12 check (duration_minutes between 1 and 240),
  equipment text, objective_ar text not null, objective_fr text,
  instructions_ar text not null, instructions_fr text,
  coaching_points jsonb not null default '[]'::jsonb check (jsonb_typeof(coaching_points) = 'array'),
  match_application_ar text, match_application_fr text,
  stages jsonb not null default '[]'::jsonb check (jsonb_typeof(stages) = 'array'),
  diagram jsonb not null default '{"marks":[]}'::jsonb check (jsonb_typeof(diagram) = 'object'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.training_session_drills (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.training_sessions(id) on delete cascade,
  drill_id uuid references public.training_drills(id) on delete cascade,
  builtin_drill_key text,
  sort_order integer not null default 1 check (sort_order > 0),
  constraint training_session_drill_one_ref check ((drill_id is not null and builtin_drill_key is null) or (drill_id is null and builtin_drill_key is not null))
);

create unique index training_session_drills_custom_unique on public.training_session_drills(session_id,drill_id) where drill_id is not null;
create unique index training_session_drills_builtin_unique on public.training_session_drills(session_id,builtin_drill_key) where builtin_drill_key is not null;

create table public.training_attendance (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.training_sessions(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  attendance_status text not null default 'present'
    check (attendance_status in ('present','absent','excused','injured')),
  reason text, unique(session_id,player_id)
);
create table public.injuries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  injury_name text not null, started_on date not null default current_date,
  expected_return date, actual_return date, notes text,
  status text not null default 'active' check (status in ('active','recovered')),
  created_at timestamptz not null default now()
);
create table public.absences (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  absence_date date not null, reason text, created_at timestamptz not null default now()
);
create table public.suspensions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  reason text not null,
  incident_match_id uuid references public.matches(id) on delete set null,
  matches_remaining integer not null default 1 check (matches_remaining >= 0),
  status text not null default 'active'
    check (status in ('pending','active','served','cancelled')),
  confirmed_at timestamptz, notes text, created_at timestamptz not null default now()
);
create table public.suspension_match_log (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  suspension_id uuid not null references public.suspensions(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  matches_before integer not null check (matches_before > 0),
  status_before text not null check (status_before = 'active'),
  confirmed_at_before timestamptz,
  created_at timestamptz not null default now(),
  unique(owner_id,suspension_id,match_id)
);

create table public.settings (
  owner_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  coach_name text not null default '',
  language text not null default 'ar' check (language in ('ar','fr')),
  yellow_card_threshold integer not null default 3 check (yellow_card_threshold > 0),
  updated_at timestamptz not null default now()
);


drop policy if exists nsm_player_read_own_lineups on public.match_lineups;
create policy nsm_player_read_own_lineups on public.match_lineups for select to authenticated using(exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_match_events on public.match_events;
create policy nsm_player_read_own_match_events on public.match_events for select to authenticated using(exists(select 1 from public.players p where p.id=match_events.player_id and p.user_id=(select auth.uid())) or exists(select 1 from public.players p where p.id=match_events.related_player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_matches on public.matches;
create policy nsm_player_read_own_matches on public.matches for select to authenticated using(exists(select 1 from public.match_lineups ml join public.players p on p.id=ml.player_id where ml.match_id=matches.id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_training_attendance on public.training_attendance;
create policy nsm_player_read_own_training_attendance on public.training_attendance for select to authenticated using(exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_training_sessions on public.training_sessions;
create policy nsm_player_read_own_training_sessions on public.training_sessions for select to authenticated using(exists(select 1 from public.training_attendance ta join public.players p on p.id=ta.player_id where ta.session_id=training_sessions.id and p.user_id=(select auth.uid())));
create or replace function public.nsm_public_poll_results(p_poll_id uuid) returns table(option_id uuid,label text,vote_count bigint) language sql stable security definer set search_path='' as $$ select o.id,o.label,count(v.id)::bigint from public.audience_poll_options o join public.audience_polls p on p.id=o.poll_id left join public.audience_poll_votes v on v.option_id=o.id and v.poll_id=p.id where p.id=p_poll_id and p.is_published=true and now() between p.starts_at and p.ends_at group by o.id,o.label,o.sort_order order by o.sort_order,o.label $$;
revoke all on function public.nsm_public_poll_results(uuid) from public;
grant execute on function public.nsm_public_poll_results(uuid) to anon,authenticated;

-- Player evaluations, monthly team awards and public audience polls.
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
