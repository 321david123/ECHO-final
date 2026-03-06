// Custom OTP: generate code, store in DB, send email via SendGrid (no domain needed) or Resend.
// SendGrid: use Single Sender Verification (one verified email, no domain). Set SENDGRID_API_KEY + EMAIL_FROM (e.g. echocampus@gmail.com).
// Resend: requires verified domain. Set RESEND_API_KEY + EMAIL_FROM (e.g. Echo Campus <noreply@yourdomain.com>).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sendgridKey = Deno.env.get("SENDGRID_API_KEY");
const resendKey = Deno.env.get("RESEND_API_KEY");
const emailFromRaw = Deno.env.get("EMAIL_FROM") ?? "";

function parseFrom(raw: string): { name: string; email: string } {
  const match = raw.match(/^(.+?)\s*<([^>]+)>$/);
  if (match) return { name: match[1].trim(), email: match[2].trim().toLowerCase() };
  if (raw.includes("@")) return { name: "Echo Campus", email: raw.trim().toLowerCase() };
  return { name: "Echo Campus", email: "" };
}

const fromParsed = parseFrom(emailFromRaw);

// Allowed email domains per campus_id (must match app Campus.allowedEmailDomains)
const CAMPUS_DOMAINS: Record<string, string[]> = {
  "tec-monterrey": ["tec.mx", "itesm.mx"],
  "tec-gdl": ["tec.mx", "itesm.mx"],
  "tec-cdmx": ["tec.mx", "itesm.mx"],
  "tec-puebla": ["tec.mx", "itesm.mx"],
  "tec-queretaro": ["tec.mx", "itesm.mx"],
  "unam": ["unam.mx", "comunidad.unam.mx", "alumno.unam.mx"],
  "itam": ["itam.mx"],
  "ibero": ["ibero.mx", "uia.mx"],
  "anahuac": ["anahuac.mx"],
  "udlap": ["udlap.mx"],
};

function allowedDomain(email: string, campusId: string): boolean {
  const domains = CAMPUS_DOMAINS[campusId];
  if (!domains) return false;
  const lower = email.toLowerCase().trim();
  const at = lower.indexOf("@");
  if (at === -1) return false;
  const domain = lower.slice(at + 1);
  return domains.some((d) => domain === d || domain.endsWith("." + d));
}

function genCode(): string {
  const n = 10000000 + Math.floor(Math.random() * 90000000);
  return String(n);
}

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...cors, Allow: "POST, OPTIONS" } });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "Content-Type": "application/json", ...cors } });
  }

  let body: { email?: string; campus_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: { "Content-Type": "application/json", ...cors } });
  }

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const campusId = typeof body.campus_id === "string" ? body.campus_id.trim() : "";
  if (!email || !campusId) {
    return new Response(JSON.stringify({ error: "email and campus_id required" }), { status: 400, headers: { "Content-Type": "application/json", ...cors } });
  }
  if (!allowedDomain(email, campusId)) {
    return new Response(JSON.stringify({ error: "invalid_email_domain" }), { status: 400, headers: { "Content-Type": "application/json", ...cors } });
  }

  const code = genCode();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 min

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  const { error: dbErr } = await supabase.from("otp_codes").upsert(
    { email, code, expires_at: expiresAt.toISOString(), created_at: new Date().toISOString() },
    { onConflict: "email" }
  );
  if (dbErr) {
    console.error("otp_codes upsert error:", dbErr);
    return new Response(JSON.stringify({ error: "Database error" }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
  }

  const subject = "Echo Campus – código de verificación";
  const text = `Hola,\n\nSolicitaste entrar a Echo Campus con tu correo institucional. Tu código es:\n\n${code}\n\nIntroduce este código en la app. El código expira en 10 minutos.\n\n— Echo Campus`;
  const html = `<p>Hola,</p><p>Solicitaste entrar a <strong>Echo Campus</strong> con tu correo institucional. Tu código es:</p><p style="font-size:24px;letter-spacing:2px;"><strong>${code}</strong></p><p>Introduce este código en la app. El código expira en 10 minutos.</p><p>— Echo Campus</p>`;

  if (sendgridKey) {
    if (!fromParsed.email) {
      return new Response(JSON.stringify({ error: "EMAIL_FROM required for SendGrid (use a Single Sender verified email, e.g. you@gmail.com)" }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
    }
    const sgRes = await fetch("https://api.sendgrid.com/v3/mail/send", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${sendgridKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        personalizations: [{ to: [{ email }] }],
        from: { email: fromParsed.email, name: fromParsed.name },
        subject,
        content: [
          { type: "text/plain", value: text },
          { type: "text/html", value: html },
        ],
      }),
    });
    if (!sgRes.ok) {
      const errBody = await sgRes.text();
      console.error("SendGrid error:", sgRes.status, errBody);
      return new Response(JSON.stringify({ error: "Failed to send email" }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
    }
  } else if (resendKey) {
    if (!fromParsed.email) {
      return new Response(JSON.stringify({ error: "Resend requires a verified domain: set EMAIL_FROM (e.g. Echo Campus <noreply@yourdomain.com>)" }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
    }
    const { Resend } = await import("npm:resend@4.0.0");
    const resend = new Resend(resendKey);
    const fromStr = `${fromParsed.name} <${fromParsed.email}>`;
    const { error: resendErr } = await resend.emails.send({ from: fromStr, to: [email], subject, text, html });
    if (resendErr) {
      console.error("Resend error:", resendErr);
      return new Response(JSON.stringify({ error: resendErr.message }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
    }
  } else {
    return new Response(JSON.stringify({ error: "Set SENDGRID_API_KEY (recommended: no domain needed) or RESEND_API_KEY, and EMAIL_FROM" }), { status: 500, headers: { "Content-Type": "application/json", ...cors } });
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "Content-Type": "application/json", ...cors } });
});
