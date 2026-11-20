import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webPush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const allowedOrigins = new Set([
  "https://eyu8hh.github.io",
  "http://localhost:3000",
  "http://127.0.0.1:5500",
]);
const json = (body: unknown, status = 200, origin = "https://eyu8hh.github.io") =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-nsm-cron-token",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

type PushSubscriptionInput = {
  endpoint?: string;
  keys?: { p256dh?: string; auth?: string };
  expirationTime?: number | null;
};

async function getSecrets() {
  const { data, error } = await admin.rpc("nsm_get_push_secrets");
  if (error || !data?.nsm_vapid_public || !data?.nsm_vapid_private || !data?.nsm_push_cron_token) {
    throw new Error("PUSH_SECRETS_UNAVAILABLE");
  }
  return data as {
    nsm_vapid_public: string;
    nsm_vapid_private: string;
    nsm_push_cron_token: string;
  };
}

function configureWebPush(secrets: Awaited<ReturnType<typeof getSecrets>>) {
  webPush.setVapidDetails(
    "https://eyu8hh.github.io/noun-star-manager/",
    secrets.nsm_vapid_public,
    secrets.nsm_vapid_private,
  );
}

async function requireManager(req: Request) {
  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTH_REQUIRED");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new Error("AUTH_INVALID");
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id,role")
    .eq("id", data.user.id)
    .maybeSingle();
  if (profileError || profile?.role !== "manager") throw new Error("MANAGER_ONLY");
  return data.user;
}

function pageForCategory(category: string) {
  if (category === "finance") return "finance";
  if (category === "inventory") return "clubResources";
  if (category === "schedule") return "calendar";
  return "notifications";
}

async function sendToSubscription(
  subscription: { endpoint: string; p256dh: string; auth: string },
  payload: Record<string, unknown>,
) {
  return await webPush.sendNotification({
    endpoint: subscription.endpoint,
    keys: { p256dh: subscription.p256dh, auth: subscription.auth },
  }, JSON.stringify(payload), { TTL: 60 * 60 * 24 });
}

async function dispatchDueNotifications() {
  const { data: notifications, error } = await admin.rpc(
    "nsm_claim_due_push_notifications",
    { p_batch_size: 50 },
  );
  if (error) throw new Error("PUSH_CLAIM_FAILED");
  let sent = 0, skipped = 0, failed = 0;
  for (const notification of notifications || []) {
    const { data: subscriptions, error: subError } = await admin
      .from("nsm_push_subscriptions")
      .select("id,owner_id,endpoint,p256dh,auth")
      .eq("owner_id", notification.owner_id);
    if (subError) {
      failed++;
      await admin.from("club_notifications").update({ push_claimed_at: null }).eq("id", notification.id);
      continue;
    }
    if (!subscriptions?.length) {
      skipped++;
      await admin.from("club_notifications").update({ push_claimed_at: null }).eq("id", notification.id);
      continue;
    }
    const payload = {
      title: notification.title || "NOUN STAR",
      body: notification.body || "لديك إشعار جديد من النادي.",
      icon: "./assets/noun-star-logo.png",
      badge: "./assets/noun-star-logo.png",
      tag: "nsm-" + notification.id,
      notificationId: notification.id,
      url: "./?nsmPage=" + encodeURIComponent(pageForCategory(notification.category || "")),
    };
    let delivered = 0;
    for (const sub of subscriptions) {
      try {
        await sendToSubscription(sub, payload);
        delivered++;
        await admin.from("nsm_push_subscriptions")
          .update({ last_success_at: new Date().toISOString(), updated_at: new Date().toISOString() })
          .eq("id", sub.id);
      } catch (error) {
        const statusCode = Number((error as { statusCode?: number })?.statusCode || 0);
        if (statusCode === 404 || statusCode === 410) {
          await admin.from("nsm_push_subscriptions").delete().eq("id", sub.id);
        } else {
          console.error("push delivery failed", notification.id, statusCode);
        }
      }
    }
    if (delivered > 0) {
      await admin.from("club_notifications")
        .update({ push_sent_at: new Date().toISOString(), push_claimed_at: null })
        .eq("id", notification.id);
      sent++;
    } else {
      await admin.from("club_notifications").update({ push_claimed_at: null }).eq("id", notification.id);
      failed++;
    }
  }
  return { claimed: notifications?.length || 0, sent, skipped, failed };
}

Deno.serve(async (req: Request) => {
  const requestedOrigin = req.headers.get("Origin") ?? "";
  const origin = allowedOrigins.has(requestedOrigin) ? requestedOrigin : "https://eyu8hh.github.io";
  if (req.method === "OPTIONS") return new Response("ok", {
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-nsm-cron-token",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);

  let input: { action?: string; subscription?: PushSubscriptionInput; endpoint?: string };
  try { input = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400, origin); }

  try {
    const secrets = await getSecrets();
    configureWebPush(secrets);

    if (input.action === "dispatch-due") {
      const cronToken = req.headers.get("x-nsm-cron-token") || "";
      if (!cronToken || cronToken !== secrets.nsm_push_cron_token) {
        return json({ error: "Unauthorized" }, 401, origin);
      }
      return json({ ok: true, ...(await dispatchDueNotifications()) }, 200, origin);
    }

    const user = await requireManager(req);
    if (input.action === "public-key") {
      return json({ publicKey: secrets.nsm_vapid_public }, 200, origin);
    }

    if (input.action === "subscribe") {
      const sub = input.subscription;
      const endpoint = String(sub?.endpoint || "");
      const p256dh = String(sub?.keys?.p256dh || "");
      const auth = String(sub?.keys?.auth || "");
      if (!endpoint.startsWith("https://") || endpoint.length > 2048 || p256dh.length < 20 || auth.length < 8) {
        return json({ error: "Invalid push subscription" }, 400, origin);
      }
      const { error } = await admin.from("nsm_push_subscriptions").upsert({
        owner_id: user.id,
        endpoint,
        p256dh,
        auth,
        user_agent: (req.headers.get("user-agent") || "").slice(0, 300),
        updated_at: new Date().toISOString(),
      }, { onConflict: "endpoint" });
      if (error) throw new Error("SUBSCRIPTION_SAVE_FAILED");
      return json({ ok: true }, 200, origin);
    }

    if (input.action === "unsubscribe") {
      const endpoint = String(input.endpoint || "");
      if (!endpoint.startsWith("https://") || endpoint.length > 2048) {
        return json({ error: "Invalid endpoint" }, 400, origin);
      }
      const { error } = await admin.from("nsm_push_subscriptions")
        .delete().eq("owner_id", user.id).eq("endpoint", endpoint);
      if (error) throw new Error("SUBSCRIPTION_REMOVE_FAILED");
      return json({ ok: true }, 200, origin);
    }

    if (input.action === "test") {
      const { data: subscriptions, error } = await admin.from("nsm_push_subscriptions")
        .select("id,endpoint,p256dh,auth").eq("owner_id", user.id);
      if (error) throw new Error("SUBSCRIPTION_READ_FAILED");
      if (!subscriptions?.length) return json({ error: "NO_SUBSCRIPTION" }, 409, origin);
      const payload = {
        title: "NOUN STAR",
        body: "تم تفعيل إشعارات الهاتف بنجاح. ستصلك تنبيهات النادي حتى عند إغلاق الموقع.",
        icon: "./assets/noun-star-logo.png",
        badge: "./assets/noun-star-logo.png",
        tag: "nsm-push-test",
        url: "./?nsmPage=notifications",
      };
      let delivered = 0;
      for (const sub of subscriptions) {
        try {
          await sendToSubscription(sub, payload);
          delivered++;
        } catch (error) {
          const statusCode = Number((error as { statusCode?: number })?.statusCode || 0);
          if (statusCode === 404 || statusCode === 410) await admin.from("nsm_push_subscriptions").delete().eq("id", sub.id);
          else console.error("test push failed", statusCode);
        }
      }
      return json({ ok: delivered > 0, delivered }, delivered > 0 ? 200 : 502, origin);
    }

    if (input.action === "status") {
      const { count, error } = await admin.from("nsm_push_subscriptions")
        .select("id", { count: "exact", head: true }).eq("owner_id", user.id);
      if (error) throw new Error("SUBSCRIPTION_READ_FAILED");
      return json({ enabled: (count || 0) > 0, devices: count || 0 }, 200, origin);
    }

    return json({ error: "Unknown action" }, 400, origin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "PUSH_ERROR";
    const status = message === "AUTH_REQUIRED" || message === "AUTH_INVALID" ? 401
      : message === "MANAGER_ONLY" ? 403 : 500;
    console.error("nsm-push error", message);
    return json({ error: message }, status, origin);
  }
});
