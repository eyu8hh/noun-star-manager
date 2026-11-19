-- Public poll creation belongs to the explicitly designated public-site manager only.
drop policy if exists nsm_audience_poll_owner_write on public.audience_polls;
create policy nsm_audience_poll_owner_write on public.audience_polls for all to authenticated
using (owner_id=auth.uid() and exists(select 1 from public.public_site_admins a where a.user_id=auth.uid()))
with check (owner_id=auth.uid() and exists(select 1 from public.public_site_admins a where a.user_id=auth.uid()));
