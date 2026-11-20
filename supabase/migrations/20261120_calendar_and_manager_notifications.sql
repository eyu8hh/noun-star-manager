create table if not exists public.club_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 160),
  event_type text not null default 'other' check (event_type = any (array['training','meeting','match','financial_due','admin','other']::text[])),
  starts_at timestamptz not null,
  ends_at timestamptz,
  team_id uuid references public.teams(id) on delete set null,
  location text,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint club_events_valid_time check (ends_at is null or ends_at >= starts_at)
);
create index if not exists club_events_owner_starts_idx on public.club_events(owner_id, starts_at);
create index if not exists club_events_team_starts_idx on public.club_events(team_id, starts_at);
alter table public.club_events enable row level security;
grant select, insert, update, delete on public.club_events to authenticated;
create policy club_events_manager_select on public.club_events for select to authenticated using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
create policy club_events_manager_insert on public.club_events for insert to authenticated with check (owner_id = (select auth.uid()) and created_by = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
create policy club_events_manager_update on public.club_events for update to authenticated using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager')) with check (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
create policy club_events_manager_delete on public.club_events for delete to authenticated using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));

create table if not exists public.club_notifications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category = any (array['finance','inventory','schedule','admin']::text[])),
  source_key text not null,
  source_id uuid,
  title text not null check (length(trim(title)) between 2 and 160),
  body text not null default '',
  scheduled_for timestamptz,
  read_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint club_notifications_source_unique unique(owner_id, source_key)
);
create index if not exists club_notifications_owner_unread_idx on public.club_notifications(owner_id, read_at, dismissed_at, created_at desc);
alter table public.club_notifications enable row level security;
grant select, insert, update on public.club_notifications to authenticated;
create policy club_notifications_manager_select on public.club_notifications for select to authenticated using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
create policy club_notifications_manager_insert on public.club_notifications for insert to authenticated with check (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
create policy club_notifications_manager_update on public.club_notifications for update to authenticated using (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager')) with check (owner_id = (select auth.uid()) and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'manager'));
