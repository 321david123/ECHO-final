# WorkOS OTP deliverability test

Quick test to see if WorkOS Magic Auth emails land in **Inbox** or **Quarantine** for @tec.mx (Microsoft 365). If they land in Inbox, we'll integrate WorkOS into the app.

## 1. WorkOS setup (one-time)

1. Sign up at [dashboard.workos.com](https://dashboard.workos.com).
2. Create an application if you don’t have one.
3. **Authentication** → enable **Magic Auth**.
4. **API Keys** → copy your **Secret key** (`sk_...`). Do not use the Client ID for this script.

## 2. Install and run

```bash
cd workos-test
npm install @workos-inc/node
WORKOS_API_KEY=sk_your_secret_key node send-otp.mjs yourname@tec.mx
```

Use a real @tec.mx (or other institutional) address.

## 3. Check deliverability

- Check **Inbox** first.
- Then **Junk** / **Quarantine** (and the Outlook Defender quarantine portal if your org uses it).
- The email is from **access@workos-mail.com**; the subject and body are set by WorkOS.

If the email lands in **Inbox**, we proceed with full WorkOS integration. If it’s in Quarantine only, we fall back to other options (e.g. IT whitelist).
