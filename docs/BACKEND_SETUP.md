# ECHO — Backend setup (Supabase + optional Fly.io)

The app uses **Supabase** for auth and database. Optionally you can run a small API on **Fly.io** (e.g. for custom verification emails or cron jobs).

---

## 1. Supabase

### Create a project

1. Go to [supabase.com](https://supabase.com) and create a project (e.g. `echo-mx`).
2. In **Project Settings → API** copy:
   - **Project URL** (e.g. `https://xxxx.supabase.co`)
   - **anon public** key

### Run the schema

1. In Supabase dashboard open **SQL Editor**.
2. Paste and run the contents of **`supabase/migrations/001_echo_schema.sql`** (from this repo root).
3. This creates: `campuses`, `profiles`, `posts`, `comments`, `votes`, triggers, and RLS policies.
4. Run **`supabase/migrations/003_posts_image_url.sql`** to add the optional `image_url` column to `posts`.

**Post images:** To allow photo attachments, create a Storage bucket: **Storage** → **New bucket** → name `post-images`, set **Public bucket** to on. Add a policy so authenticated users can upload: **Policies** → **New policy** → allow **INSERT** for authenticated.

### Auth settings

1. **Authentication → Providers**: enable **Anonymous**. The app uses anonymous sign-in: user picks campus and taps Entrar (no email, no OTP).
2. (Optional) Under **Email** disable “Confirm email” if you want to skip confirmation for development.
3. For production, keep email confirmation and configure SMTP in **Project Settings → Auth**.

**Passwordless OTP code:** The app uses email OTP only (no password). Supabase sends an **8-digit** token by default. In **Authentication → Email Templates**, edit the **Magic Link** template so the email shows the code: use `{{ .Token }}` in the body (e.g. “Tu código ECHO es: {{ .Token }}”). Users enter this 8-digit code in the app to sign in.

### Custom SMTP (avoid rate limits)

Supabase’s built-in email has a low rate limit and **only sends to your project’s team members**. For the app to work with **every user** (any @tec.mx, etc.), you **must** use **Custom SMTP**. Turn on **Authentication → Emails → SMTP Settings → Enable custom SMTP** and configure a provider (e.g. Resend: host `smtp.resend.com`, port `465`, username `resend`, password = API key, sender = your verified domain). Then Supabase will send OTP emails to any address. (If you leave default SMTP, only team-invited emails receive the code.)

**504 timeout / "context deadline exceeded" on OTP:** Supabase waits a limited time for your SMTP provider to accept the email; you **cannot** increase this timeout on hosted Supabase. The reliable fix is to **stop using SMTP** and use the **Send Email Auth Hook** so Supabase calls an Edge Function that sends via Resend’s **HTTP API** (fast, no SMTP timeout). See [SEND_EMAIL_HOOK_PASOS.md](docs/SEND_EMAIL_HOOK_PASOS.md) for Custom OTP (recommended) and Auth Hook options.

**What to put in the form:**

| Field | What to use |
|-------|-------------|
| **Sender email address** | An email you control that will appear as “From” (e.g. `noreply@yourdomain.com` or your Gmail). |
| **Sender name** | Name shown in the inbox (e.g. `ECHO` or `ECHO App`). |
| **Host** | Your SMTP server hostname (see below). |
| **Port** | Usually `587` (TLS) or `465` (SSL). |
| **Username** | SMTP username (often your email or an API username). |
| **Password** | SMTP password or **App Password** (not your normal email password for Gmail). |
| **Minimum interval per user** | e.g. `60` seconds between emails to the same user. |

**Option A — Gmail (quick testing)**

1. Use a Gmail account. Turn on [2-Step Verification](https://myaccount.google.com/security).
2. Create an [App Password](https://myaccount.google.com/apppasswords): Google Account → Security → 2-Step Verification → App passwords. Generate one for “Mail”.
3. In Supabase SMTP:
   - **Sender email:** your Gmail (e.g. `you@gmail.com`)
   - **Sender name:** `ECHO`
   - **Host:** `smtp.gmail.com`
   - **Port:** `587`
   - **Username:** your full Gmail address
   - **Password:** the 16-character App Password (no spaces)

**Option B — Zoho Mail (domain email, e.g. contacto@sonriemexico.org)**

For Zoho Mail with your own domain (not @zoho.com), use the **smtppro** server:

| Field | Value |
|-------|--------|
| **Sender email address** | Your Zoho address (e.g. `contacto@sonriemexico.org` or `noreply@sonriemexico.org`) |
| **Sender name** | `ECHO` (or the name you want in the inbox) |
| **Host** | `smtppro.zoho.com` |
| **Port** | `465` (SSL) or `587` (TLS) |
| **Username** | Your full Zoho email (e.g. `contacto@sonriemexico.org`) |
| **Password** | Your Zoho Mail account password. If you have 2FA enabled, create an [app-specific password](https://accounts.zoho.com/home#security/application_passwords) in Zoho Account → Security → Application-Specific Passwords. |
| **Minimum interval per user** | `60` (or as you prefer) |

Note: If your account is **@zoho.com** (personal), use host `smtp.zoho.com` instead of `smtppro.zoho.com`.

**If you get "Error sending email" with Zoho (diagnóstico paso a paso):**

1. **Ver el error real** — En Supabase: **Logs** (menú izquierdo) o **Authentication → Logs**. Busca la línea del intento de envío; ahí suele aparecer el mensaje del servidor SMTP (ej. "Authentication failed", "Connection refused"). Eso indica si falla contraseña, puerto o conexión.

2. **Contraseña de aplicación (lo más común)** — Si tienes **verificación en dos pasos (2FA)** en Zoho, la contraseña normal **no sirve** para SMTP. Tienes que usar una *Application-Specific Password*:
   - Entra a [Zoho Accounts](https://accounts.zoho.com) (la cuenta que usa contacto@sonriemexico.org).
   - **Security** → **Application-Specific Passwords** → **Generate New Password** (nombre ej. "Supabase" o "ECHO").
   - Copia la contraseña de 16 caracteres y pégala en Supabase SMTP (campo Password). Sin espacios al inicio/final.

3. **Probar puerto 465 en lugar de 587** — Si usas 587 y sigue fallando, cambia en Supabase a **Port: 465** y guarda. Algunos entornos conectan mejor con SSL (465) que con STARTTLS (587).

4. **Región de Zoho** — Si tu organización Zoho está en **Europa** o **India**, el host debe ser:
   - EU: `smtppro.zoho.eu`
   - India: `smtppro.zoho.in`
   - México/global: `smtppro.zoho.com`
   Puedes comprobarlo en Zoho Mail → Configuración → Cuentas → configuración del servidor.

5. **Límite de envío** — Zoho Mail Free suele tener ~50 correos/día. Si superas el límite, dejará de enviar hasta el día siguiente.

6. **Error "554 5.7.8 Access Restricted" de Zoho** — Zoho Mail **bloquea** el envío SMTP desde servidores de terceros (como los de Supabase). No es un fallo de contraseña ni de puerto; es una restricción de política. En ese caso hay que usar otro proveedor (Resend, ZeptoMail, SendGrid, etc.).

7. **Alternativa recomendada si Zoho Mail no funciona** — Usar un proveedor transaccional que Supabase documenta explícitamente:
   - **[Resend](https://resend.com)** — Cuenta gratis, verificas tu dominio (sonriemexico.org), creas API Key y en Supabase pones: Host `smtp.resend.com`, Port `465`, Username `resend`, Password = API Key, Sender = `team@sonriemexico.org` (o un subdominio que verifiques). [Guía Resend + Supabase](https://resend.com/docs/send-with-supabase-smtp).
   - **[ZeptoMail](https://www.zoho.com/zeptomail/)** (de Zoho) — Servicio transaccional de Zoho con SMTP pensado para apps; suele dar menos problemas que Zoho Mail para envío desde terceros.

**Entrega a correos institucionales (@tec.mx, Outlook/M365):** El SMTP por defecto de Supabase (`noreply@mail.app.supabase.io`) suele llegar bien a bandeja en muchos correos universitarios. Custom SMTP con tu propio dominio (ej. Resend + team@sonriemexico.org) puede no verse al principio en Outlook/institucionales porque el dominio es nuevo; para desarrollo puedes usar el SMTP por defecto (límite ~2/hora) y reservar custom SMTP para cuando necesites volumen o cuando el dominio tenga más reputación.

**Resend marca "sent" pero no llega el correo:** (1) Revisa **spam/correo no deseado** y la pestaña "Promociones" en Gmail. (2) En Resend Dashboard → **Emails** revisa el estado del envío (delivered / bounced / etc.) y que el destinatario sea el correcto. (3) Comprueba que el **dominio** (ej. sonriemexico.org) esté **verificado** en Resend con los registros DNS (SPF, DKIM) que te indica Resend; si no está verde, muchos proveedores (Gmail, Outlook) rechazan o mandan a spam. (4) Con dominio nuevo o sin historial, los primeros correos pueden tardar unos minutos o ir a spam hasta que mejore la reputación.

**Option C — Transactional provider (production)**

Use a service like [Resend](https://resend.com), [SendGrid](https://sendgrid.com), or [Mailgun](https://www.mailgun.com). They give you SMTP credentials and higher limits.

- **Resend:** Dashboard → Domains (verify your domain) → API Keys. Use **SMTP** section: host `smtp.resend.com`, port `465`, username `resend`, password = your API key. Sender email must be from your verified domain (e.g. `noreply@yourdomain.com`).
- **SendGrid:** Settings → SMTP Relay. Sender = verified single sender or domain; host `smtp.sendgrid.net`, port `587`, username `apikey`, password = your API key.

After saving, Supabase will send all auth emails (including the OTP) through your SMTP so you’re no longer limited by the default provider.

### Send Email Hook (avoid 504 timeout)

If you get **504 / context deadline exceeded** with custom SMTP (e.g. Resend), the fix is to send auth emails via the **Send Email Auth Hook** so Supabase uses Resend’s **HTTP API** instead of SMTP. The timeout is on Supabase’s side and cannot be increased; the hook returns quickly so the request does not time out.

1. **Prerequisites:** Resend account, domain verified, API key. Custom SMTP can stay configured; when the hook is enabled, the hook is used and SMTP is not.

2. **Create and deploy the Edge Function** (from the repo root):
   ```bash
   npx supabase functions deploy send-email --no-verify-jwt
   ```
   The function lives in `supabase/functions/send-email/index.ts` and sends the OTP using Resend’s API.

3. **Secrets** (Dashboard → Project Settings → Edge Functions → Secrets, or CLI):
   - `RESEND_API_KEY` = your Resend API key
   - `SEND_EMAIL_HOOK_SECRET` = from Dashboard → **Authentication → Hooks** → Send Email Hook → “Generate secret” (copy the value, e.g. `v1,whsec_...`)
   - Optional: `EMAIL_FROM` = e.g. `ECHO <team@sonriemexico.org>` (default in code is that)

4. **Enable the hook:** Dashboard → **Authentication → Hooks** → **Send Email** → Enable, set URL to:
   `https://<project-ref>.supabase.co/functions/v1/send-email`  
   (Replace `<project-ref>` with your project reference from Project Settings → General.)

5. **Disable custom SMTP** (optional but recommended): Authentication → Emails → SMTP Settings → turn off “Enable custom SMTP”. The hook will send all auth emails; no SMTP is used.

After this, OTP requests should complete without 504. The app code does not need changes.

**"Email rate exceeded":** This comes from **Supabase Auth** rate limits (not the hook or Resend). In Dashboard → **Authentication → Rate Limits** you can increase e.g. OTPs per hour and the per-user cooldown so users can request codes more often during testing or production.

### Connect the iOS app

You must pass the Supabase URL and anon key to the app. Two options:

**Option A — Environment variables (recommended for dev)**

In Xcode: **Edit Scheme → Run → Arguments → Environment Variables** add:

- `ECHO_SUPABASE_URL` = your project URL (e.g. `https://xxxx.supabase.co`)
- `ECHO_SUPABASE_ANON_KEY` = your anon key

**Option B — Info.plist**

1. Add to the app’s **Info.plist** (or a custom `Supabase-Info.plist` included in the target):

```xml
<key>ECHO_SUPABASE_URL</key>
<string>https://YOUR_PROJECT.supabase.co</string>
<key>ECHO_SUPABASE_ANON_KEY</key>
<string>your-anon-key-here</string>
```

2. Do **not** commit real keys to git. Use a template plist or CI secrets.

If neither URL nor key is set, the app runs in **mock mode** (in-memory data, no real auth).

---

## 2. Fly.io (optional)

Use Fly.io when you need:

- Custom verification emails (e.g. 6-digit code to institutional email)
- Cron jobs (e.g. hide old posts, cleanup)
- A REST API that isn’t just Supabase CRUD

### Example: small API for “send verification code”

1. **Create an app** (e.g. Node/Express or Go):

   - **POST** `/send-code`: body `{ "email": "...", "campusId": "..." }`.  
     Validate domain (e.g. `@tec.mx`), generate 6-digit code, store in Redis or DB with TTL, send email via Resend/SendGrid.
   - **POST** `/verify-code`: body `{ "email": "...", "code": "..." }`.  
     If valid, return a short-lived JWT or token the iOS app can send to Supabase (e.g. custom claim or Edge Function that creates the user).

2. **Deploy on Fly.io**:

   ```bash
   fly launch
   fly secrets set RESEND_API_KEY=...
   fly deploy
   ```

3. In the iOS app, call this API from the onboarding “Send code” / “Verify code” flow instead of (or in addition to) Supabase Auth.  
   The app currently uses **Supabase Auth with email OTP** (no password); only institutional emails allowed per campus.

---

## 3. Flow summary

| Step | Supabase | iOS app |
|------|----------|--------|
| Onboarding | User selects campus → enter institutional email → OTP sent → verify 6-digit code | `AuthService.sendOTP`, `verifyOTP`; domain checked with `Campus.allows(email:)`; then `createProfile(campusId)` |
| Feed | RLS: user sees posts where `campus_id` = profile’s campus | `DatabaseService.fetchPosts(campusId)` |
| New post | Insert into `posts` (author_id optional for anonymity) | `DatabaseService.insertPost` |
| Vote | Upsert `votes`; trigger updates `posts.score` | `DatabaseService.setVote` |
| Comments | Insert into `comments`; trigger increments `posts.comment_count` | `DatabaseService.insertComment`, `fetchComments` |
| Karma | Sum of `posts.score` where `author_id` = current user | `DatabaseService.fetchMyKarma` |
| Sign out | `auth.signOut()` | `AuthService.signOut()`; clear local state |

---

## 4. Security notes

- The **anon** key is safe to use in the iOS app; RLS restricts what rows users can read/write.
- Never put the **service_role** key in the app.
- For production, enable email confirmation in Supabase and (optionally) restrict signups by domain in Supabase Auth or via an Edge Function / Fly.io API.
