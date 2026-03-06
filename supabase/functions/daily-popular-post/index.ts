// Daily popular post: run at 3pm (e.g. via cron). Finds the top post by score from the
// last 24 hours and sends a push to all users via OneSignal "Subscribed Users" segment.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ONE_SIGNAL_APP_ID = Deno.env.get("ONE_SIGNAL_APP_ID");
const ONE_SIGNAL_REST_API_KEY = Deno.env.get("ONE_SIGNAL_REST_API_KEY");

const TITLE = "Popular post from ECHO";
const MAX_BODY_LENGTH = 150;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...cors, Allow: "POST, GET, OPTIONS" } });
  }
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: rows, error: queryError } = await supabase
    .from("posts")
    .select("id, body")
    .gte("created_at", since)
    .eq("is_hidden", false)
    .order("score", { ascending: false })
    .limit(1);

  if (queryError || !rows?.length) {
    return new Response(
      JSON.stringify({ ok: true, skipped: "no_post", detail: queryError?.message ?? "no posts in last 24h" }),
      { status: 200, headers: { "Content-Type": "application/json", ...cors } }
    );
  }

  const post = rows[0] as { id: string; body: string };
  const bodyTrimmed = (post.body ?? "").trim();
  const content = bodyTrimmed.length <= MAX_BODY_LENGTH
    ? bodyTrimmed
    : bodyTrimmed.slice(0, MAX_BODY_LENGTH - 1).trim() + "…";

  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) {
    return new Response(
      JSON.stringify({ ok: true, skipped: "no_onesignal", post_id: post.id, content }),
      { status: 200, headers: { "Content-Type": "application/json", ...cors } }
    );
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
      included_segments: ["Subscribed Users"],
      headings: { en: TITLE },
      contents: { en: content || " " },
      data: { post_id: post.id },
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

  return new Response(
    JSON.stringify({ ok: true, post_id: post.id, content_length: content.length }),
    { status: 200, headers: { "Content-Type": "application/json", ...cors } }
  );
});
