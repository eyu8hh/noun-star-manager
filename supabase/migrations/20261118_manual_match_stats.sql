-- NOUN STAR MANAGER — manual match statistics without a tactical lineup
begin;
alter table public.match_lineups drop constraint if exists match_lineups_selection_status_check;
alter table public.match_lineups add constraint match_lineups_selection_status_check
  check (selection_status in ('starter','substitute','not_selected','manual'));
commit;
