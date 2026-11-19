-- Keep the public gallery's SELECT policy as the single read path for authenticated managers too.
drop policy if exists nsm_club_media_manager_read on public.club_media;
create index if not exists club_media_created_by_idx on public.club_media(created_by);
