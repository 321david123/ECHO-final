// WorkOS Magic Auth: verify 6-digit code, ensure Supabase user exists, return magic link for app to complete session.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const WORKOS_API_KEY = Deno.env.get("WORKOS_API_KEY")!;
const WORKOS_CLIENT_ID = Deno.env.get("WORKOS_CLIENT_ID")!;
const WORKOS_API_BASE = "https://api.workos.com";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

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

  let body: { email?: string; code?: string; campus_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const campusId = typeof body.campus_id === "string" ? body.campus_id.trim() : "";
  if (!email || !code || !campusId) {
    return new Response(JSON.stringify({ error: "email, code, and campus_id required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  // 1. Verify with WorkOS
  const authRes = await fetch(`${WORKOS_API_BASE}/user_management/authenticate`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${WORKOS_API_KEY}`,
    },
    body: JSON.stringify({
      grant_type: "urn:workos:oauth:grant-type:magic-auth:code",
      client_id: WORKOS_CLIENT_ID,
      client_secret: WORKOS_API_KEY,
      code,
      email,
    }),
  });
  if (!authRes.ok) {
    const errBody = await authRes.text();
    console.error("WorkOS authenticate error:", authRes.status, errBody);
    return new Response(
      JSON.stringify({ error: "invalid_code" }),
      { status: 400, headers: { "Content-Type": "application/json", ...cors } }
    );
  }

  // 2. Ensure Supabase user exists
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data: listData } = await supabase.auth.admin.listUsers({ perPage: 1000 });
  const existing = listData?.users?.find((u) => u.email?.toLowerCase() === email);
  if (!existing) {
    const { error: createErr } = await supabase.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    if (createErr) {
      console.error("Supabase createUser error:", createErr);
      return new Response(
        JSON.stringify({ error: "Database error" }),
        { status: 500, headers: { "Content-Type": "application/json", ...cors } }
      );
    }
  }

  // 3. Generate magic link, extract token, verify OTP server-side to get session (no browser ever)
  const redirectTo = `echo://auth/callback?campus_id=${encodeURIComponent(campusId)}`;
  const { data: linkData, error: linkErr } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: { redirectTo },
  });
  if (linkErr || !linkData?.properties?.action_link) {
    console.error("Supabase generateLink error:", linkErr);
    return new Response(
      JSON.stringify({ error: "Failed to generate session" }),
      { status: 500, headers: { "Content-Type": "application/json", ...cors } }
    );
  }

  const actionLink = linkData.properties.action_link as string;
  const tokenHash = new URL(actionLink).searchParams.get("token");
  if (!tokenHash) {
    console.error("No token in action_link");
    return new Response(
      JSON.stringify({ error: "Invalid session link" }),
      { status: 500, headers: { "Content-Type": "application/json", ...cors } }
    );
  }

  // verifyOtp exchanges the one-time token for a session (returns access_token + refresh_token)
  const { data: sessionData, error: verifyErr } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: "magiclink",
  });
  if (verifyErr || !sessionData?.session) {
    console.error("Supabase verifyOtp error:", verifyErr);
    return new Response(
      JSON.stringify({ error: "Session exchange failed" }),
      { status: 500, headers: { "Content-Type": "application/json", ...cors } }
    );
  }

  const { access_token, refresh_token } = sessionData.session;
  return new Response(
    JSON.stringify({
      access_token,
      refresh_token,
      campus_id: campusId,
    }),
    { status: 200, headers: { "Content-Type": "application/json", ...cors } }
  );
});
