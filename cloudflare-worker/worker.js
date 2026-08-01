/**
 * ECHO Supabase Proxy — Cloudflare Worker
 * 
 * Purpose: Universities / networks can block *.supabase.co via DNS filtering.
 * This Worker proxies all traffic to Supabase under your own domain so the app
 * keeps working regardless of DNS-level blocks.
 * 
 * Supports: REST, Auth, Storage, Edge Functions.
 * Does NOT support: Realtime (WebSockets). ECHO doesn't use it, so this is fine.
 */

const SUPABASE_HOST = "skshtzifgqlbnloehncq.supabase.co";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/__health") {
      return new Response("ok", {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      });
    }

    const targetUrl = `https://${SUPABASE_HOST}${url.pathname}${url.search}`;

    // Re-create the request pointed at Supabase. Passing `request` as the init
    // preserves method, headers, and body streaming correctly.
    const newRequest = new Request(targetUrl, request);
    // Let fetch set the Host header based on the target URL.
    newRequest.headers.delete("host");

    try {
      const response = await fetch(newRequest);
      return response;
    } catch (err) {
      console.error("Proxy error:", err);
      return new Response(
        JSON.stringify({ error: "proxy_error", message: String(err) }),
        {
          status: 502,
          headers: { "Content-Type": "application/json" },
        }
      );
    }
  },
};
