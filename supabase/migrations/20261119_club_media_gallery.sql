-- Public club media gallery: only manager-approved, consent-confirmed images are listed publicly.
create table if not exists public.club_media (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 media_type text not null check (media_type in ('player_card','match_photo')),
 player_id uuid references public.players(id) on delete set null, match_id uuid references public.matches(id) on delete set null,
 title text not null check (length(trim(title)) between 2 and 180), caption text, storage_path text not null unique,
 mime_type text not null check (mime_type in ('image/webp','image/jpeg','image/png')),
 byte_size bigint not null check (byte_size > 0 and byte_size <= 12582912),
 visibility text not null default 'public' check (visibility in ('public','hidden')),
 consent_confirmed boolean not null default false, created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint club_media_public_requires_consent check (visibility <> 'public' or consent_confirmed = true),
 constraint club_media_type_reference check ((media_type='player_card' and player_id is not null and match_id is null) or (media_type='match_photo' and player_id is null))
);
create index if not exists club_media_public_created_idx on public.club_media(visibility,created_at desc) where visibility='public';
create index if not exists club_media_owner_created_idx on public.club_media(owner_id,created_at desc);
create index if not exists club_media_player_idx on public.club_media(player_id) where player_id is not null;
create index if not exists club_media_match_idx on public.club_media(match_id) where match_id is not null;
alter table public.club_media enable row level security;
drop policy if exists nsm_club_media_public_read on public.club_media;
create policy nsm_club_media_public_read on public.club_media for select to anon,authenticated using (visibility='public' and consent_confirmed=true);
drop policy if exists nsm_club_media_manager_read on public.club_media;
create policy nsm_club_media_manager_read on public.club_media for select to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager'));
drop policy if exists nsm_club_media_manager_insert on public.club_media;
create policy nsm_club_media_manager_insert on public.club_media for insert to authenticated with check (owner_id=(select auth.uid()) and created_by=(select auth.uid()) and consent_confirmed=true and visibility='public' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager'));
drop policy if exists nsm_club_media_manager_update on public.club_media;
create policy nsm_club_media_manager_update on public.club_media for update to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager')) with check (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager'));
drop policy if exists nsm_club_media_manager_delete on public.club_media;
create policy nsm_club_media_manager_delete on public.club_media for delete to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager'));
grant select on public.club_media to anon,authenticated;
grant insert,update,delete on public.club_media to authenticated;
create or replace function public.nsm_guard_club_media()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or new.owner_id<>auth.uid() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager') then raise exception 'Only the club manager can publish club media'; end if;
 if new.created_by is distinct from auth.uid() then raise exception 'Invalid media creator'; end if;
 if new.visibility='public' and new.consent_confirmed is not true then raise exception 'Consent confirmation is required'; end if;
 if new.media_type='player_card' and not exists(select 1 from public.players p where p.id=new.player_id and p.owner_id=new.owner_id) then raise exception 'Player does not belong to this club'; end if;
 if new.match_id is not null and not exists(select 1 from public.matches m where m.id=new.match_id and m.owner_id=new.owner_id) then raise exception 'Match does not belong to this club'; end if;
 return new;
end; $$;
drop trigger if exists nsm_guard_club_media on public.club_media;
create trigger nsm_guard_club_media before insert or update on public.club_media for each row execute function public.nsm_guard_club_media();
revoke all on function public.nsm_guard_club_media() from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('noun-star-media','noun-star-media',true,12582912,array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists nsm_gallery_public_read on storage.objects;
create policy nsm_gallery_public_read on storage.objects for select to anon,authenticated using (bucket_id='noun-star-media');
drop policy if exists nsm_gallery_manager_insert on storage.objects;
create policy nsm_gallery_manager_insert on storage.objects for insert to authenticated with check (bucket_id='noun-star-media' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager'));
drop policy if exists nsm_gallery_manager_delete on storage.objects;
create policy nsm_gallery_manager_delete on storage.objects for delete to authenticated using (bucket_id='noun-star-media' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='manager'));
