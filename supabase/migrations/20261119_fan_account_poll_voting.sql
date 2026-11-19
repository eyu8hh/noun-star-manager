-- Public voting is open to browse, but each registered loyal fan gets one vote per poll.
alter table public.audience_poll_votes add column if not exists voter_user_id uuid references auth.users(id) on delete cascade;
create unique index if not exists nsm_audience_poll_one_vote_per_fan on public.audience_poll_votes(poll_id,voter_user_id) where voter_user_id is not null;
revoke insert on public.audience_poll_votes from anon;
grant insert,select on public.audience_poll_votes to authenticated;
drop policy if exists nsm_audience_vote_public_insert on public.audience_poll_votes;
drop policy if exists nsm_audience_vote_fan_insert on public.audience_poll_votes;
create policy nsm_audience_vote_fan_insert on public.audience_poll_votes for insert to authenticated with check (
 voter_user_id=auth.uid()
 and exists(select 1 from public.audience_members am where am.user_id=auth.uid())
 and exists(select 1 from public.audience_polls p join public.audience_poll_options o on o.poll_id=p.id
            where p.id=poll_id and o.id=option_id and p.is_published=true and now() between p.starts_at and p.ends_at)
);
drop policy if exists nsm_audience_vote_self_read on public.audience_poll_votes;
create policy nsm_audience_vote_self_read on public.audience_poll_votes for select to authenticated using (voter_user_id=auth.uid());
