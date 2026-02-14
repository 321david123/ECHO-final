# Configurar envío de códigos OTP (lo que sí funciona)

**Resumen:** Con **Custom SMTP** Supabase suele dar **504 timeout**. Hay dos caminos que evitan el timeout: **(1) OTP propio** (recomendado) o **(2) Auth Hook** (Resend API). Con cualquiera, los correos a Gmail suelen llegar; a @tec.mx/Outlook a veces van a spam.

---

## Recomendado: OTP propio (request-otp / verify-otp)

La app ya usa este flujo por defecto: **no pasa por el envío de email de Supabase**, así que no hay 504 ni límites de Auth para el envío.

1. **Migración:** En Supabase **SQL Editor** ejecuta el contenido de **`supabase/migrations/002_otp_codes.sql`** (crea la tabla `otp_codes`).
2. **Desplegar las dos funciones:**
   ```bash
   supabase functions deploy request-otp --no-verify-jwt
   supabase functions deploy verify-otp --no-verify-jwt
   ```
3. **Secretos** (desde la raíz del repo, con el proyecto enlazado):
   ```bash
   # Obligatorio: API key de Resend (Resend → API Keys → Create)
   supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxx

   # Opcional: otro remitente (por defecto ya se usa yo@davidmtz.me)
   supabase secrets set EMAIL_FROM="ECHO <yo@davidmtz.me>"

   # Opcional: enviar desde dominio de Resend (mejor llegada a Outlook/@tec.mx)
   supabase secrets set RESEND_USE_SHARED_DOMAIN=true
   ```
   Por defecto los correos salen de **ECHO &lt;yo@davidmtz.me&gt;** (dominio verificado en Resend). Con `RESEND_USE_SHARED_DOMAIN=true` salen de `ECHO <onboarding@resend.dev>`.
4. **Desactiva el Auth Hook** (Dashboard → **Authentication** → **Hooks** → Send Email → desactivar o borrar URL). Así Supabase no envía correos; la app llama a `request-otp` y `verify-otp` directamente.
5. **Custom SMTP:** Puedes dejarlo desactivado. No se usa en este flujo.

Flujo: la app llama a `request-otp` (email + campus_id) → la función guarda un código en `otp_codes` y envía el correo con Resend → el usuario introduce el código → la app llama a `verify-otp` (email + code) → la función devuelve un token de magic link → la app hace `verifyOTP` con Supabase Auth y queda la sesión.

---

## Alternativa: Auth Hook (Resend API)

1. **Desactiva Custom SMTP** para no tener 504: Dashboard → **Emails** → **SMTP Settings** → desactiva **Enable custom SMTP** y guarda.
2. **Activa el Send Email Hook:** Dashboard → **Authentication** → **Hooks** → Send Email → **URL:** `https://skshtzifgqlbnloehncq.supabase.co/functions/v1/auth-send-email` → guarda.
3. Secretos ya configurados: `RESEND_API_KEY`, `SEND_EMAIL_HOOK_SECRET`. Si no, ver pasos más abajo.
4. Los códigos se envían por Resend sin timeout. Para @tec.mx: revisar spam o usar Gmail/correo personal para registrarse.

---

---

## 1. Instalar Supabase CLI (si no la tienes)

```bash
brew install supabase/tap/supabase
```

O desde [supabase.com/docs/guides/cli](https://supabase.com/docs/guides/cli).

---

## 2. Iniciar sesión y enlazar el proyecto

```bash
cd /Users/davidmartinez/Desktop/ECHO
supabase login
supabase link --project-ref TU_PROJECT_REF
```

**TU_PROJECT_REF:** en Supabase Dashboard → Project Settings → General → "Reference ID" (ej. `skshtzifgqlbnloehncq`).

---

## 3. Desplegar la función

Si **send-email** te da 405 al usarla como hook, despliega la alternativa **auth-send-email** (mismo código, otro nombre para evitar caché de Supabase):

```bash
supabase functions deploy auth-send-email --no-verify-jwt
```

URL de esta función: `https://TU_PROJECT_REF.supabase.co/functions/v1/auth-send-email`  
**Cópiala** para el paso 5.

(O bien despliega `send-email` si prefieres: `supabase functions deploy send-email --no-verify-jwt` → URL `.../functions/v1/send-email`.)

---

## 4. Crear el secreto del Hook y configurar secretos

1. Entra a [Supabase Dashboard](https://supabase.com/dashboard) → tu proyecto **ECHO**.
2. **Authentication** → **Hooks** (menú izquierdo).
3. En **Send Email**, clic en **Create Hook** o **Enable**.
4. En **URL** de momento deja vacío o pon cualquier cosa; guarda.
5. **Generate Secret** y **copia el valor** (ej. `v1,whsec_xxxxx`).

Luego configura los secretos de la función (en la terminal):

```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxx
supabase secrets set SEND_EMAIL_HOOK_SECRET="v1,whsec_xxxxx"
```

- **RESEND_API_KEY:** en [Resend](https://resend.com) → API Keys → Create → copia la clave.
- **SEND_EMAIL_HOOK_SECRET:** el que copiaste en el paso anterior.

(Opcional) Si quieres otro remitente:

```bash
supabase secrets set EMAIL_FROM="ECHO <team@sonriemexico.org>"
```

**Si no te llega a Outlook / @tec.mx:** Prueba enviar desde el dominio de Resend (suele llegar mejor a Microsoft):
```bash
supabase secrets set RESEND_USE_SHARED_DOMAIN=true
```
Luego redeploy: `supabase functions deploy auth-send-email --no-verify-jwt`. Los correos saldrán de `ECHO <onboarding@resend.dev>`. Para volver a tu dominio, borra el secreto o pon `RESEND_USE_SHARED_DOMAIN=false` y redeploy.

---

## 5. Poner la URL del Hook

1. Dashboard → **Authentication** → **Hooks**.
2. En **Send Email**, edita el hook.
3. **URL:** pega la URL de tu función, por ejemplo:
   `https://TU_PROJECT_REF.supabase.co/functions/v1/auth-send-email`  
   (o `.../send-email` si desplegaste esa)
4. Guarda / **Create**.

---

## 6. (Opcional) Desactivar Custom SMTP

Para que solo se use el hook y no SMTP:

1. **Authentication** → **Emails** → **SMTP Settings**.
2. Desactiva **Enable custom SMTP** y guarda.

---

## 7. Probar

En la app, pide un código a un correo (ej. @tec.mx). Debería completar sin 504 y llegar el correo "Código ECHO" con el código.

Si algo falla, revisa **Logs** en Supabase (Edge Functions → send-email → Logs) y que los secretos estén bien.

---

## "Email rate exceeded"

Ese mensaje viene de **Supabase Auth**, no del hook ni de Resend. Auth limita cuántos OTP/correos se pueden pedir (por defecto ~30 OTP/hora y 60 s entre envíos al mismo usuario).

**Subir los límites:** Dashboard → **Authentication** → **Rate Limits**. El campo "Rate limit for sending emails" a veces **no se puede editar** hasta que tengas Custom SMTP configurado. Dos opciones:

**Opción A — Activar Custom SMTP solo para desbloquear el límite**  
El envío lo sigue haciendo el **hook** (Resend API); SMTP no se usa cuando el hook está activo. Pero si Supabase ve SMTP configurado, suele dejar subir el límite:
1. **Authentication** → **Emails** → **SMTP Settings** → **Enable custom SMTP**.
2. Pon Resend: Host `smtp.resend.com`, Port `465`, Username `resend`, Password = tu API key, Sender = `team@sonriemexico.org`.
3. Guarda. Vuelve a **Rate Limits** y sube "Rate limit for sending emails" (ej. 30 o 60). Guarda.

**Opción B — Subir el límite por API (sin tocar SMTP)**  
Desde tu máquina (necesitas un [Access Token](https://supabase.com/dashboard/account/tokens) de la cuenta):
```bash
export SUPABASE_ACCESS_TOKEN="tu_access_token"
export PROJECT_REF="tu_project_ref"

curl -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"rate_limit_email_sent": 60}'
```
Sustituye `tu_access_token` y `tu_project_ref` (Project Settings → General → Reference ID). Con eso pasas a 60 emails/hora aunque el dashboard no deje tocar el campo.
