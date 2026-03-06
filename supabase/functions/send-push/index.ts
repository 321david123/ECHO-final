// Send push notification: called by Database Webhook on push_notification_queue insert.
// Requires ONE_SIGNAL_APP_ID and ONE_SIGNAL_REST_API_KEY. Fetches device token from
// device_tokens, registers it with OneSignal (legacy add player) if needed, then sends
// via OneSignal create notification with include_aliases (external_id = user_id).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ONE_SIGNAL_APP_ID = Deno.env.get("ONE_SIGNAL_APP_ID");
const ONE_SIGNAL_REST_API_KEY = Deno.env.get("ONE_SIGNAL_REST_API_KEY");

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

interface QueueRecord {
  id?: string;
  user_id: string;
  kind?: string;
  title: string;
  body: string;
  payload?: Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...cors, Allow: "POST, OPTIONS" } });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  let record: QueueRecord;
  try {
    const body = await req.json();
    // Database Webhook sends { type, table, record, ... }; direct call may send { user_id, title, body }.
    record = (body.record ?? body) as QueueRecord;
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const userId = typeof record.user_id === "string" ? record.user_id.trim() : "";
  const title = typeof record.title === "string" ? record.title.trim() : "ECHO";
  const bodyText = typeof record.body === "string" ? record.body.trim() : "";
  if (!userId) {
    return new Response(JSON.stringify({ error: "user_id required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) {
    console.log("send-push: ONE_SIGNAL_APP_ID or ONE_SIGNAL_REST_API_KEY not set; skipping push.");
    return new Response(JSON.stringify({ ok: true, skipped: "no_onesignal" }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("device_token")
    .eq("user_id", userId);

  const deviceTokens = (tokens ?? []).map((r: { device_token: string }) => r.device_token).filter(Boolean);

  for (const token of deviceTokens) {
    try {
      await fetch("https://onesignal.com/api/v1/players", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Basic ${ONE_SIGNAL_REST_API_KEY}`,
        },
        body: JSON.stringify({
          app_id: ONE_SIGNAL_APP_ID,
          device_type: 0,
          identifier: token,
          external_user_id: userId,
          notification_types: 1,
        }),
      });
    } catch (e) {
      console.error("OneSignal add player error:", e);
    }
  }

  const notifRes = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Key ${ONE_SIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify({
      app_id: ONE_SIGNAL_APP_ID,
      target_channel: "push",
      include_aliases: { external_id: [userId] },
      contents: { en: bodyText || " " },
      headings: { en: title },
      data: record.payload ?? {},
    }),
  });

  if (!notifRes.ok) {
    const errText = await notifRes.text();
    console.error("OneSignal create notification error:", notifRes.status, errText);
    return new Response(
      JSON.stringify({ error: "Push send failed", detail: errText }),
      { status: 500, headers: { "Content-Type": "application/json", ...cors } }
    );
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors },
  });
});
