# ☕️ Invita y Gana — evento de regreso a clases (Otoño 2026)

Sistema de referidos verificados. Un referido **cuenta** solo cuando el invitado:
descarga la app → se registra con su correo institucional → **publica su primer echo**.

## Escalera de premios

| Referidos | Premio | Tipo | ¿Se repite? |
|---|---|---|---|
| **1** | Badge OG 🐿️ (emoji exclusivo del squirrel de Echo para el avatar) | Digital, automático | No (legacy, permanente) |
| **5** | Perfil dorado ✨ (color de avatar exclusivo, **opcional** — el usuario elige si lo usa en sus posts) | Digital, automático | No (legacy, permanente) |
| **10** | Bebida Starbucks / Tim Hortons ☕️ | Física — la entregas tú | **Sí, cada 10** (20 = 2ª, 30 = 3ª…) |

Los digitales se desbloquean solos en la app (Perfil → Editar perfil); nada se aplica
automáticamente — el dorado y el squirrel son elección del usuario (importante en una
app anónima: el dorado hace linkeables sus posts entre sí, así que es opt-in). Solo las
bebidas requieren entrega: quedan en `referral_rewards` y te llega push con cada una.

### Evento limitado / legacy

Toda la comunicación en la app (banner, pantalla del evento, pushes y texto de invitación)
dice que es **solo del lanzamiento**: OG y dorado son para los primeros; al terminar el
evento nadie más los podrá conseguir, pero quien los ganó los conserva para siempre.
El fin del evento es decisión tuya y es manual: quita el banner en un update de la app y
deja de honrar nuevos desbloqueos (no hay fecha de corte automática en esta versión —
si quieres una, se puede agregar un flag `referral_event_active` en `app_config` después).

## Cómo funciona (técnico)

- Cada perfil tiene `profiles.referral_code` (6 caracteres, se genera solo).
- El invitado ingresa el código en la app (sheet "¿Quién te invitó?" que aparece una vez
  a cuentas nuevas, o desde Invita y Gana → "¿Te invitó un amig@?").
- `claim_referral` (RPC) valida: cuenta < 7 días, no es tu propio código, solo un
  referidor por usuario. Crea la fila `referrals` en `pending`.
- Trigger en `posts`: el primer echo del invitado pasa el referido a `completed` y manda
  el push del hito que toque (OG a 1, dorado a 5, bebida cada 10 + push a ti).
- Anti-abuso real: cada referido requiere un correo `@tec.mx` verificado distinto.

## Deploy (en orden)

1. **SQL** — pega `supabase/migrations/014_referrals.sql` completo en el SQL Editor
   del Dashboard (proyecto `skshtzifgqlbnloehncq`). Idempotente; no toca datos
   existentes; genera códigos para los perfiles actuales.
   *Nota:* el MCP de Supabase conectado en Claude apunta a otra cuenta (solo se ven
   `crossover-pitchlab` y `floreria-demo`) — reconéctalo con la cuenta dueña de ECHO
   si quieres que Claude aplique migraciones directo.

2. **App** — compila y sube el build a TestFlight/App Store. Si la migración aún no
   está aplicada, la app funciona normal y la sección de referidos no carga (silencioso).

3. **GitHub Pages** — sube `github-pages/` actualizado (el AASA ahora incluye `/i/*`
   para links de invitación). ⚠️ `404.html` sigue redirigiendo a `id0000000000` —
   **cámbialo por el App Store ID real de Echo Campus** o los invitados sin la app
   caerán en una página muerta.

4. **Push** — nada que hacer: reusa `push_notification_queue` → webhook → `send-push`.

## Operación del evento (tu parte)

**Bebidas pendientes de entrega:**
```sql
SELECT r.id, r.user_id, u.email, r.referral_count_at_award, r.created_at
FROM referral_rewards r JOIN auth.users u ON u.id = r.user_id
WHERE r.status = 'earned' ORDER BY r.created_at;
```

**Marcar entregada después de dar la bebida:**
```sql
UPDATE referral_rewards SET status = 'delivered' WHERE id = '<uuid>';
```

**Leaderboard del evento:**
```sql
SELECT p.referral_code, u.email, count(*) AS completados
FROM referrals r JOIN profiles p ON p.id = r.referrer_id JOIN auth.users u ON u.id = r.referrer_id
WHERE r.status = 'completed' GROUP BY 1, 2 ORDER BY completados DESC;
```

**Cambiar la meta de bebida (ej. 8):** `UPDATE app_config SET value='8' WHERE key='referrals_per_drink';`
y cambia `referralsPerDrink` en `AppState.swift` (requiere update de app — decide antes de lanzar).
Los hitos de 1 (OG) y 5 (dorado) están fijos en SQL y en la app.

## Post fijado de lanzamiento (sugerido)

Publica desde tu cuenta y fíjalo:
```sql
UPDATE posts SET is_pinned = true WHERE id = '<uuid-de-tu-post>';
```
Texto sugerido (≤200 chars):
> 🐿️ SOLO LANZAMIENTO: 1 amig@ con su primer echo = badge OG · 5 = perfil dorado · 10 = bebida Starbucks GRATIS (otra cada 10). Cuando acabe el evento, OG y dorado ya no existirán. Código en Perfil 👀

## Presupuesto estimado

Solo pagas la bebida: ~$120–150 MXN por cada **10** usuarios nuevos verificados
(≈ $12–15 MXN por usuario). 50 nuevos ≈ 5 bebidas ≈ $600–750 MXN. Los hitos de
1 y 5 son digitales y cuestan $0 — son los que generan la participación masiva.
