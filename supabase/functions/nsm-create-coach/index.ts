import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration missing" }, 500);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Authentication required" }, 401);

  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: callerData, error: callerError } = await callerClient.auth.getUser(token);
  if (callerError || !callerData.user) return json({ error: "Invalid session" }, 401);
  const managerId = callerData.user.id;

  const { data: managerProfile, error: profileError } = await admin
    .from("profiles").select("role").eq("id", managerId).maybeSingle();
  if (profileError || managerProfile?.role !== "manager") {
    return json({ error: "Only the club manager can create coach accounts" }, 403);
  }

  let input: { email?: string; password?: string; display_name?: string; team_id?: string };
  try { input = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const email = String(input.email ?? "").trim().toLowerCase();
  const password = String(input.password ?? "");
  const displayName = String(input.display_name ?? "").trim();
  const teamId = String(input.team_id ?? "").trim();

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "A valid email is required" }, 400);
  if (password.length < 10) return json({ error: "Password must contain at least 10 characters" }, 400);
  if (!displayName) return json({ error: "Coach name is required" }, 400);

  if (teamId) {
    const { data: team, error: teamError } = await admin
      .from("teams").select("id").eq("id", teamId).eq("owner_id", managerId).maybeSingle();
    if (teamError || !team) return json({ error: "Selected team was not found in this club" }, 404);
  }

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });
  if (createError || !created.user) return json({ error: createError?.message ?? "Account creation failed" }, 400);

  const coachId = created.user.id;
  const { error: roleError } = await admin.from("profiles")
    .update({ display_name: displayName, role: "coach" }).eq("id", coachId);

  if (roleError) {
    await admin.auth.admin.deleteUser(coachId);
    return json({ error: "Could not assign coach role: " + roleError.message }, 500);
  }

  if (teamId) {
    const { error: assignmentError } = await admin.from("team_coaches").insert({
      owner_id: managerId, team_id: teamId, coach_user_id: coachId,
    });
    if (assignmentError) {
      await admin.auth.admin.deleteUser(coachId);
      return json({ error: "Could not assign coach to team: " + assignmentError.message }, 500);
    }
  }

  return json({ id: coachId, display_name: displayName, role: "coach", team_id: teamId || null }, 201);
});
