import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

function randomHex(bytes = 4) {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  return [...data].map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase();
}
async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((v) => v.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration missing" }, 500);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Authentication required" }, 401);
  const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await callerClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);
  const callerId = authData.user.id;
  const { data: callerProfile, error: callerProfileError } = await admin.from("profiles").select("id,role").eq("id", callerId).maybeSingle();
  if (callerProfileError || callerProfile?.role !== "manager") return json({ error: "Only the current bootstrap manager can perform this setup" }, 403);

  let input: { setup_token?: string; display_name?: string; password?: string };
  try { input = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const setupToken = String(input.setup_token ?? "").trim();
  const displayName = String(input.display_name ?? "").trim();
  const password = String(input.password ?? "");
  if (!/^[a-f0-9]{64}$/i.test(setupToken)) return json({ error: "Invalid or expired setup token" }, 400);
  if (displayName.length < 2 || displayName.length > 100) return json({ error: "Enter the manager's full display name" }, 400);
  if (password.length < 12 || password.length > 72) return json({ error: "The new manager password must be 12–72 characters" }, 400);

  const [{ data: managers, error: managersError }, { count: clubCount, error: clubError }] = await Promise.all([
    admin.from("profiles").select("id").eq("role", "manager"),
    admin.from("clubs").select("id", { count: "exact", head: true }),
  ]);
  if (managersError || clubError) return json({ error: "Could not verify the initial club state" }, 500);
  if (!managers || managers.length !== 1 || managers[0].id !== callerId || (clubCount ?? 0) !== 0) {
    return json({ error: "Initial manager setup is no longer available" }, 409);
  }

  const tokenHash = await sha256(setupToken);
  const { data: consumed, error: consumeError } = await admin.from("nsm_manager_bootstrap_tokens")
    .update({ used_at: new Date().toISOString() })
    .eq("token_hash", tokenHash).is("used_at", null).gt("expires_at", new Date().toISOString())
    .select("token_hash").maybeSingle();
  if (consumeError || !consumed) return json({ error: "Invalid, expired, or already used setup token" }, 400);

  const managerCode = "M-" + randomHex(4);
  const coachCode = "C-" + randomHex(4);
  const managerEmail = "manager+" + managerCode.slice(2).toLowerCase() + "@login.nounstar.club";
  const coachEmail = "coach+" + coachCode.slice(2).toLowerCase() + "@login.nounstar.club";
  const oldEmail = authData.user.email ?? null;

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: managerEmail, password, email_confirm: true, user_metadata: { display_name: displayName },
  });
  if (createError || !created.user) return json({ error: createError?.message ?? "Could not create manager account" }, 400);
  const managerId = created.user.id;
  let clubId: string | null = null;
  let oldProfileChanged = false;
  let settingsMoved = false;
  let publicAdminAdded = false;

  const rollback = async () => {
    if (oldProfileChanged) await admin.from("profiles").update({ role: "manager", club_owner_id: null, coach_code: null }).eq("id", callerId);
    if (settingsMoved) await admin.from("settings").update({ owner_id: callerId }).eq("owner_id", managerId);
    if (publicAdminAdded) await admin.from("public_site_admins").delete().eq("user_id", managerId);
    if (clubId) await admin.from("clubs").delete().eq("id", clubId);
    await admin.auth.admin.deleteUser(managerId);
    if (oldEmail) await admin.auth.admin.updateUserById(callerId, { email: oldEmail, email_confirm: true });
  };

  const { error: profileError } = await admin.from("profiles").update({ role: "manager", display_name: displayName }).eq("id", managerId);
  if (profileError) { await rollback(); return json({ error: "Could not assign manager role: " + profileError.message }, 500); }

  const { data: club, error: clubInsertError } = await admin.from("clubs")
    .insert({ owner_id: managerId, name: "NOUN STAR FOOTBALL CLUB", short_name: "NOUN STAR" }).select("id").single();
  if (clubInsertError || !club) { await rollback(); return json({ error: "Could not create the club workspace" }, 500); }
  clubId = club.id;

  const { error: publicAdminError } = await admin.from("public_site_admins").insert({ user_id: managerId });
  if (publicAdminError) { await rollback(); return json({ error: "Could not grant public-site management: " + publicAdminError.message }, 500); }
  publicAdminAdded = true;

  const { error: settingsError } = await admin.from("settings").update({ owner_id: managerId, coach_name: displayName }).eq("owner_id", callerId);
  if (settingsError) { await rollback(); return json({ error: "Could not transfer club settings: " + settingsError.message }, 500); }
  settingsMoved = true;

  const { error: oldProfileError } = await admin.from("profiles")
    .update({ role: "coach", club_owner_id: managerId, coach_code: coachCode }).eq("id", callerId);
  if (oldProfileError) { await rollback(); return json({ error: "Could not convert the previous account to coach: " + oldProfileError.message }, 500); }
  oldProfileChanged = true;

  const { error: emailError } = await admin.auth.admin.updateUserById(callerId, { email: coachEmail, email_confirm: true });
  if (emailError) { await rollback(); return json({ error: "Could not assign the coach login code: " + emailError.message }, 500); }

  return json({
    success: true,
    manager_code: managerCode,
    coach_code: coachCode,
    manager_name: displayName,
    message: "The new manager account and club workspace are ready. The previous account is now a coach.",
  }, 201);
});
