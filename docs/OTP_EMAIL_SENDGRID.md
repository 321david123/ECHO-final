# OTP email sin dominio propio (SendGrid Single Sender)

Resend **no** permite usar su dominio compartido en producción; exige un dominio verificado. Para que el código OTP llegue sin configurar DNS ni dominio propio, usa **SendGrid con Single Sender Verification**: verificas **un solo correo** (por ejemplo un Gmail) y envías desde ahí.

---

## 1. Cuenta SendGrid

1. Regístrate en [sendgrid.com](https://sendgrid.com) (plan gratis: 100 emails/día).
2. Verifica tu cuenta (email, 2FA si lo pide).

---

## 2. Single Sender Verification (un solo correo, sin dominio)

1. En SendGrid: **Settings** → **Sender Authentication** → **Single Sender Verification**.
2. **Create New Sender**.
3. Rellena:
   - **From Name:** Echo Campus  
   - **From Email Address:** un correo que **tú** controles y puedas abrir (ej. `echocampus@gmail.com` o tu Gmail personal).  
   - **Reply To:** el mismo o otro que revises.  
   - **Company / Address:** lo que quieras (no afecta el envío).
4. Envía el formulario. SendGrid enviará un **correo de verificación** a esa dirección.
5. Abre ese correo y haz clic en el **link de verificación**. Cuando aparezca como **Verified** en SendGrid, ya puedes enviar desde ese correo.

No hace falta dominio ni DNS: solo ese correo verificado.

---

## 3. API Key de SendGrid

1. **Settings** → **API Keys** → **Create API Key**.
2. Nombre ej. `Echo Campus OTP`.
3. Permisos: **Restricted Access** → **Mail Send** → **Full Access** (o al menos enviar).
4. Crea y **copia la API key** (solo se muestra una vez).

---

## 4. Secrets en Supabase (Edge Function `request-otp`)

En el proyecto de Supabase:

1. **Edge Functions** → **request-otp** → **Secrets** (o **Project Settings** → **Edge Functions** → **Secrets**).
2. Añade:

| Secret               | Valor                                                                 |
|----------------------|-----------------------------------------------------------------------|
| `SENDGRID_API_KEY`   | La API key de SendGrid que copiaste.                                  |
| `EMAIL_FROM`         | El mismo correo que verificaste, ej. `echocampus@gmail.com` o `Echo Campus <echocampus@gmail.com>`. |

**Importante:** No pongas `RESEND_API_KEY` si vas a usar solo SendGrid (o la función usará Resend si está definida). Con `SENDGRID_API_KEY` + `EMAIL_FROM` la función enviará por SendGrid.

---

## 5. Desplegar la función

```bash
cd /ruta/al/proyecto/ECHO
supabase functions deploy request-otp --project-ref TU_PROJECT_REF
```

(O desde el dashboard de Supabase si despliegas desde ahí.)

---

## 6. Probar

Desde la app (o Postman) llama a la Edge Function `request-otp` con `email` (correo institucional válido, ej. @tec.mx) y `campus_id`. El usuario debe recibir el correo en su bandeja de entrada (o en spam la primera vez); el remitente será el correo que verificaste en SendGrid.

---

## Resumen

- **SendGrid Single Sender** = un correo verificado (ej. Gmail), **sin dominio ni DNS**.
- Secrets: `SENDGRID_API_KEY` + `EMAIL_FROM` (ese mismo correo).
- La función `request-otp` usa SendGrid si existe `SENDGRID_API_KEY`; si no, usa Resend (que sí requiere dominio verificado).
