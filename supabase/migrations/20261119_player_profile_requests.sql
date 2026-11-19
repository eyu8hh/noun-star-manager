begin;
alter table public.players add column if not exists login_code text;
create unique index if not exists players_login_code_unique on public.players(lower(login_code)) where login_code is not null;
create unique index if not exists players_user_id_unique on public.players(user_id) where user_id is not null;
create table if not exists public.player_profile_change_requests (
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
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists player_change_requests_owner_status_idx on public.player_profile_change_requests(owner_id,status,created_at desc);
create index if not exists player_change_requests_player_idx on public.player_profile_change_requests(player_id,created_at desc);
alter table public.player_profile_change_requests enable row level security;
revoke all on public.player_profile_change_requests from anon;
grant select,insert,update on public.player_profile_change_requests to authenticated;
drop policy if exists nsm_player_change_request_read on public.player_profile_change_requests;
create policy nsm_player_change_request_read on public.player_profile_change_requests for select to authenticated
using (exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())) or owner_id=(select auth.uid()));
drop policy if exists nsm_player_change_request_insert on public.player_profile_change_requests;
create policy nsm_player_change_request_insert on public.player_profile_change_requests for insert to authenticated
with check (status='pending' and reviewed_by is null and reviewed_at is null and exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid()) and p.owner_id=player_profile_change_requests.owner_id));
drop policy if exists nsm_player_change_request_manager_update on public.player_profile_change_requests;
create policy nsm_player_change_request_manager_update on public.player_profile_change_requests for update to authenticated
using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));
drop policy if exists nsm_player_read_own_profile on public.players;
create policy nsm_player_read_own_profile on public.players for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists nsm_player_read_own_team on public.team_players;
create policy nsm_player_read_own_team on public.team_players for select to authenticated
using (exists(select 1 from public.players p where p.id=player_id and p.user_id=(select auth.uid())));
drop policy if exists nsm_player_read_own_team_details on public.teams;
create policy nsm_player_read_own_team_details on public.teams for select to authenticated
using (exists(select 1 from public.team_players tp join public.players p on p.id=tp.player_id where tp.team_id=teams.id and p.user_id=(select auth.uid()) and tp.is_current=true));
create or replace function public.nsm_touch_change_request()
returns trigger language plpgsql set search_path = '' as $$ begin new.updated_at:=now(); return new; end $$;
drop trigger if exists nsm_touch_change_request on public.player_profile_change_requests;
create trigger nsm_touch_change_request before update on public.player_profile_change_requests for each row execute function public.nsm_touch_change_request();
commit;