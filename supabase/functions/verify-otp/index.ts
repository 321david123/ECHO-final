// Custom OTP: check code in DB, then exchange for Supabase session via admin generateLink (magiclink).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...cors, Allow: "POST, OPTIONS" } });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "Content-Type": "application/json", ...cors } });
  }

  let body: { email?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: { "Content-Type": "application/json", ...cors } });
  }

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const code = typeof body.code === "string" ? body.code.trim() : "";
  if (!email || !code) {
    return new Response(JSON.stringify({ error: "email and code required" }), { status: 400, headers: { "Content-Type": "application/json", ...cors } });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  const { data: row, error: selectErr } = await supabase
    .from("otp_codes")
    .select("code, expires_at")
    .eq("email", email)
    .maybeSingle();

  if (selectErr || !row) {
    return new Response(JSON.stringify({ error: "invalid_code" }), { status: 401, headers: { "Content-Type": "application/json", ...cors } });
  }
  if (row.code !== code) {
    return new Response(JSON.stringify({ error: "invalid_code" }), { status: 401, headers: { "Content-Type": "application/json", ...cors } });
  }
  if (new Date(row.expires_at) < new Date()) {
    await supabase.from("otp_codes").delete().eq("email", email);
    return new Response(JSON.stringify({ error: "code_expired" }), { status: 401, headers: { "Content-Type": "application/json", ...cors } });
  }

  await supabase.from("otp_codes").delete().eq("email", email);

  const { data: linkData, error: linkErr } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
  });

  if (linkErr) {
    console.error("generateLink error:", linkErr);
    return new Response(JSON.stringify({ error: linkErr.message }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
  }

  const props = (linkData as { user?: unknown; properties?: { hashed_token?: string; action_link?: string } })?.properties;
  const hashedToken = props?.hashed_token;
  if (!hashedToken) {
    console.error("generateLink missing hashed_token:", linkData);
    return new Response(JSON.stringify({ error: "Missing token" }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
  }

  return new Response(
    JSON.stringify({ token: hashedToken }),
    { status: 200, headers: { "Content-Type": "application/json", ...cors } }
  );
});
