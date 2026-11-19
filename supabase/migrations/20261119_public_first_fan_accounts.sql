-- NOUN STAR public-first experience, fan accounts, and manager-published content.
do $$
begin
  if exists (select 1 from pg_constraint where conrelid='public.profiles'::regclass and conname='profiles_role_check') then
    alter table public.profiles drop constraint profiles_role_check;
  end if;
end $$;
alter table public.profiles alter column role set default 'fan';
alter table public.profiles add constraint profiles_role_check check (role in ('manager','coach','player','fan'));
revoke insert, update, delete on public.profiles from authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, preferred_language) on public.profiles to authenticated;
create table if not exists public.audience_members (
 user_id uuid primary key references auth.users(id) on delete cascade,
 username text not null unique check (username ~ '^[a-z0-9_]{4,20}$'),
 display_name text not null check (length(trim(display_name)) between 1 and 80),
 notifications_enabled boolean not null default true,
 created_at timestamptz not null default now()
);
alter table public.audience_members enable row level security;
grant select on public.audience_members to authenticated;
grant update (display_name, notifications_enabled) on public.audience_members to authenticated;
drop policy if exists nsm_audience_member_read_self on public.audience_members;
create policy nsm_audience_member_read_self on public.audience_members for select to authenticated using (user_id=auth.uid());
drop policy if exists nsm_audience_member_update_self on public.audience_members;
create policy nsm_audience_member_update_self on public.audience_members for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
-- Empty allow-list: do not grant the former coach account public-site administration.
create table if not exists public.public_site_admins (user_id uuid primary key references auth.users(id) on delete cascade, granted_at timestamptz not null default now());
alter table public.public_site_admins enable row level security;
grant select on public.public_site_admins to authenticated;
drop policy if exists nsm_public_site_admin_read_self on public.public_site_admins;
create policy nsm_public_site_admin_read_self on public.public_site_admins for select to authenticated using (user_id=auth.uid());
create table if not exists public.public_posts (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 content_type text not null default 'news' check (content_type in ('news','announcement','event','contest')),
 audience text not null default 'all' check (audience in ('all','fans')),
 title text not null check (length(trim(title)) between 3 and 180),
 body text not null default '' check (length(body) <= 5000),
 image_url text check (image_url is null or length(image_url) <= 2000),
 publish_at timestamptz not null default now(),
 expires_at timestamptz,
 is_published boolean not null default false,
 notify_audience boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (expires_at is null or expires_at > publish_at)
);
create index if not exists nsm_public_posts_feed_idx on public.public_posts(is_published,publish_at desc) where is_published=true;
alter table public.public_posts enable row level security;
grant select on public.public_posts to anon,authenticated;
grant insert,update,delete on public.public_posts to authenticated;
drop policy if exists nsm_public_posts_public_read on public.public_posts;
create policy nsm_public_posts_public_read on public.public_posts for select to anon,authenticated using (
 is_published=true and publish_at<=now() and (expires_at is null or expires_at>now())
 and (audience='all' or (audience='fans' and exists(select 1 from public.audience_members am where am.user_id=auth.uid()))
));
drop policy if exists nsm_public_posts_admin_manage on public.public_posts;
create policy nsm_public_posts_admin_manage on public.public_posts for all to authenticated
using (owner_id=auth.uid() and exists(select 1 from public.public_site_admins a where a.user_id=auth.uid()))
with check (owner_id=auth.uid() and exists(select 1 from public.public_site_admins a where a.user_id=auth.uid()));
create table if not exists public.audience_notifications (
 id uuid primary key default gen_random_uuid(),
 post_id uuid unique references public.public_posts(id) on delete cascade,
 audience text not null check (audience in ('all','fans')),
 title text not null,
 body text not null default '',
 created_at timestamptz not null default now()
);
alter table public.audience_notifications enable row level security;
grant select on public.audience_notifications to anon,authenticated;
drop policy if exists nsm_audience_notifications_read on public.audience_notifications;
create policy nsm_audience_notifications_read on public.audience_notifications for select to anon,authenticated using (
 audience='all' or (audience='fans' and exists(select 1 from public.audience_members am where am.user_id=auth.uid()))
);
create table if not exists public.audience_notification_reads (
 notification_id uuid not null references public.audience_notifications(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 read_at timestamptz not null default now(),
 primary key(notification_id,user_id)
);
alter table public.audience_notification_reads enable row level security;
grant select,insert on public.audience_notification_reads to authenticated;
drop policy if exists nsm_notification_reads_self on public.audience_notification_reads;
create policy nsm_notification_reads_self on public.audience_notification_reads for select to authenticated using (user_id=auth.uid());
drop policy if exists nsm_notification_reads_insert_self on public.audience_notification_reads;
create policy nsm_notification_reads_insert_self on public.audience_notification_reads for insert to authenticated with check (user_id=auth.uid());
create table if not exists public.audience_signup_attempts (
 id bigint generated always as identity primary key,
 ip_hash text not null,
 created_at timestamptz not null default now()
);
create index if not exists nsm_audience_signup_attempts_recent_idx on public.audience_signup_attempts(ip_hash,created_at desc);
alter table public.audience_signup_attempts enable row level security;
create or replace function public.nsm_sync_public_post_notification()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
 if new.is_published and new.notify_audience then
  insert into public.audience_notifications(post_id,audience,title,body)
  values(new.id,new.audience,new.title,left(new.body,500))
  on conflict(post_id) do update set audience=excluded.audience,title=excluded.title,body=excluded.body;
 else
  delete from public.audience_notifications where post_id=new.id;
 end if;
 return new;
end $$;
drop trigger if exists nsm_public_post_notification on public.public_posts;
create trigger nsm_public_post_notification after insert or update of is_published,notify_audience,audience,title,body
on public.public_posts for each row execute function public.nsm_sync_public_post_notification();
drop trigger if exists nsm_public_posts_touch_updated_at on public.public_posts;
create trigger nsm_public_posts_touch_updated_at before update on public.public_posts for each row execute function public.nsm_touch_updated_at();
revoke all on function public.nsm_sync_public_post_notification() from public,anon,authenticated;
