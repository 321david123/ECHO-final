// Send Email Auth Hook — same as send-email; use this name if send-email returns 405 (routing cache).
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { Resend } from "npm:resend@4.0.0";

const resend = new Resend(Deno.env.get("RESEND_API_KEY") as string);
const hookSecretRaw = Deno.env.get("SEND_EMAIL_HOOK_SECRET") as string;
const hookSecret = hookSecretRaw ? hookSecretRaw.replace("v1,whsec_", "") : "";
// Use RESEND_USE_SHARED_DOMAIN=true to send from onboarding@resend.dev (often better delivery to Outlook/edu)
const useResendDomain = Deno.env.get("RESEND_USE_SHARED_DOMAIN") === "true";
const fromAddress = useResendDomain ? "ECHO <onboarding@resend.dev>" : (Deno.env.get("EMAIL_FROM") ?? "ECHO <yo@davidmtz.me>");

const emptyOk = () => new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { "Allow": "POST, OPTIONS" } });
  }
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
    const subject = "Código ECHO";
    const text = `Tu código de verificación ECHO:\n\n${token}`;
    const html = `<p>Tu código de verificación ECHO:</p><p><strong>${token}</strong></p>`;

    const { error } = await resend.emails.send({
      from: fromAddress,
      to: [user.email],
      subject,
      text,
      html,
    });

    if (error) {
      console.error("Resend error:", error);
      return new Response(
        JSON.stringify({ error: { message: error.message } }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
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
