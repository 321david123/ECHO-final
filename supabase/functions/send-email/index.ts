// Send Email Auth Hook — sends OTP via SendGrid (no domain) or Resend. Avoids 504 from Supabase SMTP.
// SendGrid: SENDGRID_API_KEY + EMAIL_FROM (Single Sender verified email). Resend: RESEND_API_KEY + EMAIL_FROM (verified domain).
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const sendgridKey = Deno.env.get("SENDGRID_API_KEY");
const resendKey = Deno.env.get("RESEND_API_KEY");
const emailFromRaw = Deno.env.get("EMAIL_FROM") ?? "";

function parseFrom(raw: string): { name: string; email: string } {
  const match = raw.match(/^(.+?)\s*<([^>]+)>$/);
  if (match) return { name: match[1].trim(), email: match[2].trim().toLowerCase() };
  if (raw.includes("@")) return { name: "Echo Campus", email: raw.trim().toLowerCase() };
  return { name: "Echo Campus", email: "" };
}

const hookSecretRaw = Deno.env.get("SEND_EMAIL_HOOK_SECRET") as string;
const hookSecret = hookSecretRaw ? hookSecretRaw.replace("v1,whsec_", "") : "";
const fromParsed = parseFrom(emailFromRaw);

const emptyOk = () => new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { "Allow": "POST, OPTIONS" } });
  }
  // Only POST has a body; GET/HEAD etc. return 200 so we never trigger "405" from Supabase
  if (req.method !== "POST") {
    return emptyOk();
  }

  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);

  try {
    const wh = new Webhook(hookSecret);
    const { user, email_data } = wh.verify(payload, headers) as {
      user: { email: string };
      email_data: {
        token: string;
        token_hash: string;
        redirect_to: string;
        email_action_type: string;
        site_url: string;
        token_new: string;
        token_hash_new: string;
      };
    };

    const token = email_data.token ?? email_data.token_new ?? "";
    const subject = "Echo Campus – código de verificación";
    const text = `Hola,\n\nSolicitaste entrar a Echo Campus con tu correo institucional. Tu código es:\n\n${token}\n\nIntroduce este código en la app. El código expira en 10 minutos.\n\n— Echo Campus`;
    const html = `<p>Hola,</p><p>Solicitaste entrar a <strong>Echo Campus</strong> con tu correo institucional. Tu código es:</p><p style="font-size:24px;letter-spacing:2px;"><strong>${token}</strong></p><p>Introduce este código en la app. El código expira en 10 minutos.</p><p>— Echo Campus</p>`;

    if (sendgridKey && fromParsed.email) {
      const sgRes = await fetch("https://api.sendgrid.com/v3/mail/send", {
        method: "POST",
        headers: { "Authorization": `Bearer ${sendgridKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          personalizations: [{ to: [{ email: user.email }] }],
          from: { email: fromParsed.email, name: fromParsed.name },
          subject,
          content: [{ type: "text/plain", value: text }, { type: "text/html", value: html }],
        }),
      });
      if (!sgRes.ok) {
        console.error("SendGrid error:", await sgRes.text());
        return new Response(JSON.stringify({ error: { message: "Failed to send email" } }), { status: 500, headers: { "Content-Type": "application/json" } });
      }
    } else if (resendKey && fromParsed.email) {
      const { Resend } = await import("npm:resend@4.0.0");
      const resend = new Resend(resendKey);
      const fromStr = `${fromParsed.name} <${fromParsed.email}>`;
      const { error } = await resend.emails.send({ from: fromStr, to: [user.email], subject, text, html });
      if (error) {
        console.error("Resend error:", error);
        return new Response(JSON.stringify({ error: { message: error.message } }), { status: 500, headers: { "Content-Type": "application/json" } });
      }
    } else {
      console.error("Set SENDGRID_API_KEY + EMAIL_FROM or RESEND_API_KEY + EMAIL_FROM");
      return new Response(JSON.stringify({ error: { message: "Email not configured" } }), { status: 500, headers: { "Content-Type": "application/json" } });
    }
  } catch (err) {
    console.error("Send email hook error:", err);
    return new Response(
      JSON.stringify({ error: { message: String(err) } }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
