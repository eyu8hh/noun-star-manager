-- NOUN STAR MANAGER — manually tracked opponent fixtures
-- Apply after the base schema. Safe to re-run.
begin;
alter table public.competition_teams
  add column if not exists remaining_matches integer not null default 0 check (remaining_matches >= 0);
commit;
