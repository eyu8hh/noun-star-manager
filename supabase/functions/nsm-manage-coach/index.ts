import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration missing" }, 500);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Authentication required" }, 401);
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: callerData, error: callerError } = await caller.auth.getUser(token);
  if (callerError || !callerData.user) return json({ error: "Invalid session" }, 401);
  const managerId = callerData.user.id;
  const { data: manager, error: managerError } = await admin.from("profiles")
    .select("role").eq("id", managerId).maybeSingle();
  if (managerError || manager?.role !== "manager") return json({ error: "Only the club manager can manage coaches" }, 403);

  let input: { action?: string; coach_id?: string };
  try { input = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const action = String(input.action ?? "");
  if (action === "list") {
    const { data: coaches, error } = await admin.from("profiles")
      .select("id,display_name,coach_code,created_at").eq("role", "coach")
      .eq("club_owner_id", managerId).order("display_name", { ascending: true });
    if (error) return json({ error: "Could not load coach accounts" }, 500);
    const results = await Promise.all((coaches ?? []).map(async (coach) => {
      const { data, error: authError } = await admin.auth.admin.getUserById(coach.id);
      if (authError) throw authError;
      const until = data.user?.banned_until ?? null;
      return { ...coach, is_frozen: Boolean(until && Date.parse(until) > Date.now()) };
    }));
    return json({ coaches: results });
  }

  const coachId = String(input.coach_id ?? "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(coachId)) {
    return json({ error: "Invalid coach account" }, 400);
  }
  const { data: coach, error: coachError } = await admin.from("profiles")
    .select("id,role,club_owner_id").eq("id", coachId).maybeSingle();
  if (coachError || !coach || coach.role !== "coach" || coach.club_owner_id !== managerId || coachId === managerId) {
    return json({ error: "Coach account not found in this club" }, 404);
  }

  if (action === "freeze" || action === "unfreeze") {
    const { error } = await admin.auth.admin.updateUserById(coachId, {
      ban_duration: action === "freeze" ? "876000h" : "none",
    });
    if (error) return json({ error: error.message || "Could not update coach access" }, 500);
    return json({ success: true, action });
  }

  if (action === "remove") {
    const { error: banError } = await admin.auth.admin.updateUserById(coachId, { ban_duration: "876000h" });
    if (banError) return json({ error: banError.message || "Could not disable coach access" }, 500);
    const { error: assignmentError } = await admin.from("team_coaches")
      .delete().eq("coach_user_id", coachId).eq("owner_id", managerId);
    if (assignmentError) return json({ error: "Account disabled, but assignments could not be detached. Retry the removal." }, 500);
    const { error: profileError } = await admin.from("profiles")
      .update({ club_owner_id: null, coach_code: null }).eq("id", coachId).eq("role", "coach").eq("club_owner_id", managerId);
    if (profileError) return json({ error: "Account disabled and assignments detached, but club removal did not finish. Retry the removal." }, 500);
    return json({ success: true, action, preserved_account: true });
  }
  return json({ error: "Unsupported action" }, 400);
});
