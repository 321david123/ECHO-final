#!/usr/bin/env node
/**
 * Quick test: send one WorkOS Magic Auth OTP to an email.
 * Use your @tec.mx (or any) address and check if the email lands in Inbox or Quarantine.
 *
 * Prereqs:
 * 1. WorkOS account + create an app at https://dashboard.workos.com
 * 2. Authentication → enable "Magic Auth"
 * 3. API Keys → copy the Secret key (sk_...)
 *
 * Run:
 *   cd workos-test && npm install @workos-inc/node
 *   WORKOS_API_KEY=sk_xxx node send-otp.mjs yourname@tec.mx
 */

import { WorkOS } from "@workos-inc/node";

const apiKey = process.env.WORKOS_API_KEY;
const email = process.argv[2] || process.env.TEST_EMAIL;

if (!apiKey) {
  console.error("Set WORKOS_API_KEY (Secret key from WorkOS Dashboard → API Keys)");
  process.exit(1);
}
if (!email || !email.includes("@")) {
  console.error("Usage: node send-otp.mjs <email>");
  console.error("Example: node send-otp.mjs yourname@tec.mx");
  process.exit(1);
}

const workos = new WorkOS(apiKey);

try {
  const magicAuth = await workos.userManagement.createMagicAuth({
    email: email.trim().toLowerCase(),
  });
  console.log("Sent. Check your email:", email);
  console.log("Look in Inbox first, then Junk/Quarantine. Code expires in 10 minutes.");
  console.log("(WorkOS sends from access@workos-mail.com)");
} catch (err) {
  console.error("Error:", err.message || err);
  if (err.code) console.error("Code:", err.code);
  process.exit(1);
}
