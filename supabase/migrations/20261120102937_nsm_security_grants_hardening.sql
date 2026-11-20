begin;

-- This RPC is not used by the current frontend or Edge Functions.
-- Role provisioning is performed by trusted service-role Edge Functions.
revoke all on function public.nsm_set_profile_role(uuid,text) from public, anon, authenticated;
grant execute on function public.nsm_set_profile_role(uuid,text) to service_role;

-- Voting candidates are specific to an authenticated player account.
revoke all on function public.nsm_player_vote_candidates() from public, anon;
grant execute on function public.nsm_player_vote_candidates() to authenticated;

-- Signup rate-limit records are accessed only by the nsm-create-fan Edge Function
-- through its service-role client; the browser must not have table privileges.
revoke all on table public.audience_signup_attempts from public, anon, authenticated;
grant all on table public.audience_signup_attempts to service_role;

commit;
