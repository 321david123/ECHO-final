// WorkOS Magic Auth: send 6-digit OTP to email. Validates campus domain.
const WORKOS_API_KEY = Deno.env.get("WORKOS_API_KEY")!;
const WORKOS_API_BASE = "https://api.workos.com";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

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

  let body: { email?: string; campus_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const campusId = typeof body.campus_id === "string" ? body.campus_id.trim() : "";
  if (!email || !campusId) {
    return new Response(JSON.stringify({ error: "email and campus_id required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }
  if (!allowedDomain(email, campusId)) {
    return new Response(JSON.stringify({ error: "invalid_email_domain" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...cors },
    });
  }

  const res = await fetch(`${WORKOS_API_BASE}/user_management/magic_auth`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${WORKOS_API_KEY}`,
    },
    body: JSON.stringify({ email }),
  });
  if (!res.ok) {
    const errBody = await res.text();
    console.error("WorkOS createMagicAuth error:", res.status, errBody);
    return new Response(
      JSON.stringify({ error: "Failed to send code" }),
      { status: 500, headers: { "Content-Type": "application/json", ...cors } }
    );
  }
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors },
  });
});
