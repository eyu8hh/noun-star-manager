-- Tighten direct API execution of profile-role trigger helpers.
revoke execute on function public.nsm_guard_profile_role_change() from public,anon,authenticated;
grant execute on function public.nsm_guard_profile_role_change() to service_role;
revoke execute on function public.nsm_protect_profile_role() from public,anon,authenticated;
grant execute on function public.nsm_protect_profile_role() to service_role;
alter function public.nsm_protect_profile_role() set search_path=public,pg_temp;
revoke execute on function public.nsm_set_profile_role(uuid,text) from public,anon;
grant execute on function public.nsm_set_profile_role(uuid,text) to authenticated,service_role;
