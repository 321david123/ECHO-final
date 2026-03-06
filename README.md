# ECHO

**Yik Yak for Mexican universities.** Anonymous campus feed: post, vote, comment — by campus (Tec de Monterrey, UNAM, ITAM, Ibero, UDLAP, etc.).

## Features (Yik Yak–style)

- **Anonymous posting** — 200 character “echos,” no usernames
- **Campus feed** — One campus at a time (Tec Mty, Tec GDL, Tec CDMX, UNAM, ITAM, Ibero, Anáhuac, UDLAP, Tec Puebla, Tec Querétaro)
- **Upvote / downvote** — Posts with score ≤ -5 are hidden (like Yik Yak)
- **Comments** — Anonymous replies on any post
- **Sort** — **Recientes** (new) or **Popular** (hot)
- **Polls** — Optional poll (question + 2–6 options) on a post; one vote per user
- **Images** — Attach a photo to a post; composer shows a preview before publishing

## Requirements

- Xcode 15+
- iOS 17+
- Swift 5.9+

## Run

1. Open `ECHO.xcodeproj` in Xcode.
2. Select the **ECHO** scheme and a simulator or device.
3. Build and run (⌘R).

### Supabase on your iPhone (or "Supabase no está configurado")

When running on a **physical device**, the scheme’s environment variables are often not passed, so the app can’t find the Supabase URL/key. Fix it by putting them in **Info.plist**:

1. In Xcode, open **ECHO/Info.plist**.
2. Set **ECHO_SUPABASE_URL** to your project URL (e.g. `https://xxxx.supabase.co`).
3. Set **ECHO_SUPABASE_ANON_KEY** to your anon key (from Supabase → Project Settings → API).

You can copy the values from your scheme’s environment variables or from the Supabase dashboard. After that, build and run on your iPhone again.

## Sign-in notes (for reviewer)

Pick any campus → Continuar → email **review@echoiosone.com** → Enviar código → code **123456** → Verificar. No institutional email or real OTP required.

## Project layout

```
ECHO/
├── ECHOApp.swift          # App entry, AppState
├── ContentView.swift      # Tab bar (Feed, Notificaciones, Perfil)
├── Models/
│   ├── Post.swift        # Post (body, score, comments, campus)
│   ├── Comment.swift     # Comment
│   ├── Campus.swift      # Mexican universities list
│   └── Vote.swift        # VoteDirection
├── Views/
│   ├── FeedView.swift    # Main feed + sort + campus picker
│   ├── PostRowView.swift # Row with vote buttons
│   ├── PostDetailView.swift # Post + comments + reply
│   ├── ComposeView.swift # New post (200 char limit)
│   └── CampusPickerView.swift
├── Services/
│   └── AppState.swift    # Posts, comments, votes, campus (in-memory)
└── Theme/
    └── Color+Theme.swift # echoGreen, echoOrange
```

## WorkOS + Supabase auth (exact setup)

To make the 6-digit email OTP flow work end-to-end, do these three things.

### 1. Supabase Dashboard — allow the app redirect URL

Supabase must allow the redirect URL that the app uses after magic-link sign-in.

1. Go to [Supabase Dashboard](https://supabase.com/dashboard) → your project.
2. Open **Authentication** → **URL Configuration** (or **Auth** → **Providers** / **Redirect URLs** in older UI).
3. Under **Redirect URLs**, add this **exact** URL:
   ```text
   echo://auth/callback
   ```
4. Save.  
   (Supabase will allow `echo://auth/callback` and `echo://auth/callback?campus_id=...`; the app uses the latter with a query param.)

### 2. Edge Function secrets

Set these secrets for your Supabase project (e.g. Dashboard → **Project Settings** → **Edge Functions** → **Secrets**, or via CLI below).

**Required for both functions:**

| Secret name           | Description                          | Where to get it                    |
|-----------------------|--------------------------------------|------------------------------------|
| `WORKOS_API_KEY`      | WorkOS API key (secret)               | WorkOS Dashboard → API Keys        |
| `WORKOS_CLIENT_ID`    | WorkOS Client ID (public)             | WorkOS Dashboard → Configuration   |

**Required only for `workos-verify-otp`** (Supabase often injects these automatically; set them if the function fails):

| Secret name                   | Description                    |
|-------------------------------|--------------------------------|
| `SUPABASE_URL`                | Your project URL               |
| `SUPABASE_SERVICE_ROLE_KEY`   | Service role key (Dashboard → Settings → API) |

CLI example (run from project root, replace values):

```bash
supabase secrets set WORKOS_API_KEY=sk_test_xxxx
supabase secrets set WORKOS_CLIENT_ID=client_xxxx
# Only if not auto-injected:
supabase secrets set SUPABASE_URL=https://xxxx.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

### 3. Deploy the Edge Functions

From the project root:

```bash
supabase functions deploy workos-send-otp
supabase functions deploy workos-verify-otp
```

After this, the app can call `workos-send-otp` (send 6-digit code) and `workos-verify-otp` (verify code and return magic link); the app opens the link and completes sign-in via `echo://auth/callback`.

### 4. Supabase schema for polls (optional)

To enable **polls on posts**, add these in the Supabase SQL editor:

```sql
-- Add poll columns to posts
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS poll_question TEXT,
  ADD COLUMN IF NOT EXISTS poll_options JSONB;

-- One vote per user per post (option_index 0-based)
CREATE TABLE IF NOT EXISTS poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  option_index INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_poll_votes_post_id ON poll_votes(post_id);

-- If poll_votes already exists without this constraint, add it so the app’s vote upsert works:
-- ALTER TABLE poll_votes ADD CONSTRAINT poll_votes_post_user_unique UNIQUE (post_id, user_id);

-- Restrict access: only authenticated users, and users can only write their own vote
ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated can read poll votes"
  ON poll_votes FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert their own poll vote"
  ON poll_votes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own poll vote"
  ON poll_votes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own poll vote"
  ON poll_votes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
```

Run the RLS block in the Supabase SQL editor after creating the table. Then the table is no longer open to anonymous access.

### 5. Push notifications: device tokens and RLS

Run this in the Supabase SQL editor to store APNs device tokens and secure the table:

```sql
-- Store one device token per user (last device wins). Used by send-push Edge Function.
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  device_token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own device token"
  ON device_tokens FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

In Supabase, `auth.users` is the default auth table, so `REFERENCES auth.users(id)` is correct and no change is needed. (Only adjust or drop the `REFERENCES` if you use a custom auth schema.)

The notification tables and triggers below match a schema where `posts` has `author_id`, `comments` has `author_id` and `post_id`, `conversations` has `post_author_id` and `initiator_id`, and `private_messages` has `conversation_id` and `sender_id`—same as in your project.

### 6. Push notification queue and triggers

The app sends pushes when: **post reaches 5, 10, 20, or 100 upvotes**; **someone comments on the user’s post**; **someone sends a private message**. Run the following in the SQL editor (after enabling the `pg_net` extension if you use it, or use Database Webhooks instead; see below).

```sql
-- Queue table: one row per push to send. Triggers insert here; Edge Function processes.
CREATE TABLE IF NOT EXISTS push_notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  payload JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Optional: allow Edge Function (service role) to delete after sending.
ALTER TABLE push_notification_queue ENABLE ROW LEVEL SECURITY;
-- Triggers (e.g. on comments) run as the authenticated user; they need to insert into the queue.
CREATE POLICY "Authenticated can insert into queue"
  ON push_notification_queue FOR INSERT
  TO authenticated
  WITH CHECK (true);
CREATE POLICY "Service role can manage queue"
  ON push_notification_queue FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
```

Then add triggers that insert into `push_notification_queue`:

**6a. Post score milestones (5, 10, 20, 100)**  
*(Assumes `posts` has `author_id` and a trigger keeps `score` updated from `votes`.)*  
The trigger only runs when the score **increases** to one of these values (e.g. 4 → 5). When testing manually, set the post’s score to a lower value first (e.g. 4), save, then set it to 5 and save again. Also ensure the post has `author_id` set.

```sql
CREATE OR REPLACE FUNCTION notify_post_score_milestone()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.author_id IS NOT NULL
     AND NEW.score IN (5, 10, 20, 100)
     AND (OLD.score IS NULL OR OLD.score < NEW.score)
     AND NEW.score > COALESCE(OLD.score, 0)
  THEN
    INSERT INTO push_notification_queue (user_id, kind, title, body, payload)
    VALUES (
      NEW.author_id,
      'post_milestone',
      'Tu ECHO va en alza',
      'Tu publicación llegó a ' || NEW.score || ' votos.',
      jsonb_build_object('post_id', NEW.id)
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_post_score_milestone ON posts;
CREATE TRIGGER tr_post_score_milestone
  AFTER UPDATE OF score ON posts
  FOR EACH ROW
  EXECUTE FUNCTION notify_post_score_milestone();
```

**6b. New comment on a post** (notify post author, skip if commenter is the author).  
*(Ensure the `comments` table has an `author_id` column.)*

```sql
CREATE OR REPLACE FUNCTION notify_comment_on_post()
RETURNS TRIGGER AS $$
DECLARE
  v_author_id UUID;
BEGIN
  SELECT author_id INTO v_author_id FROM posts WHERE id = NEW.post_id;
  IF v_author_id IS NOT NULL AND v_author_id != NEW.author_id THEN
    INSERT INTO push_notification_queue (user_id, kind, title, body, payload)
    VALUES (
      v_author_id,
      'comment',
      'Nuevo comentario',
      'Alguien comentó en tu publicación.',
      jsonb_build_object('post_id', NEW.post_id)
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- CommentRow has author_id; ensure comments table has author_id column.
DROP TRIGGER IF EXISTS tr_comment_notify ON comments;
CREATE TRIGGER tr_comment_notify
  AFTER INSERT ON comments
  FOR EACH ROW
  EXECUTE FUNCTION notify_comment_on_post();
```

**6c. New private message** (notify the other participant):

```sql
CREATE OR REPLACE FUNCTION notify_private_message()
RETURNS TRIGGER AS $$
DECLARE
  v_post_author_id UUID;
  v_initiator_id UUID;
  v_recipient_id UUID;
BEGIN
  SELECT post_author_id, initiator_id INTO v_post_author_id, v_initiator_id
  FROM conversations WHERE id = NEW.conversation_id;
  IF NEW.sender_id = v_initiator_id THEN
    v_recipient_id := v_post_author_id;
  ELSE
    v_recipient_id := v_initiator_id;
  END IF;
  IF v_recipient_id IS NOT NULL THEN
    INSERT INTO push_notification_queue (user_id, kind, title, body, payload)
    VALUES (
      v_recipient_id,
      'dm',
      'Nuevo mensaje',
      'Te enviaron un mensaje directo.',
      jsonb_build_object('conversation_id', NEW.conversation_id)
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_private_message_notify ON private_messages;
CREATE TRIGGER tr_private_message_notify
  AFTER INSERT ON private_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_private_message();
```

**Invoking the Edge Function**  
- **Option A – Database Webhook (recommended):** In Supabase Dashboard → **Database** → **Webhooks**, add a webhook on table `push_notification_queue` for **Insert**. Set the URL to your Edge Function: `https://<project-ref>.supabase.co/functions/v1/send-push`. Use **HTTP Headers** to add `Authorization: Bearer <SUPABASE_ANON_KEY>` (or service role key) so the function can be invoked. The function receives the new row and sends the push via OneSignal.
- **Option B – pg_net:** From a trigger you can call `net.http_post` to the same URL with the row as JSON body (requires the `pg_net` extension).

**OneSignal and iOS Push**  
1. **OneSignal:** Create an app at [OneSignal](https://onesignal.com), add an iOS platform and upload your APNs key (.p8) or certificate. In Supabase → **Edge Functions** → **send-push** → **Secrets**, set `ONE_SIGNAL_APP_ID` and `ONE_SIGNAL_REST_API_KEY`.
2. **Xcode:** Enable **Push Notifications** in the ECHO target → **Signing & Capabilities** → **+ Capability** → **Push Notifications**. Use a real device or a simulator that supports push when testing.
3. The app already requests notification permission and registers the APNs token with Supabase (`device_tokens`). The Edge Function registers that token with OneSignal (by external_user_id) when sending, so no OneSignal SDK is required in the app.

**Daily popular post (3pm)**  
To send a “Popular post from ECHO” notification to all users once a day at 3pm:

1. Deploy the function:  
   `supabase functions deploy daily-popular-post`  
   It uses the same secrets as `send-push` (`ONE_SIGNAL_APP_ID`, `ONE_SIGNAL_REST_API_KEY`).

2. The function finds the **highest-scoring post from the last 24 hours** (not hidden), uses its body as the notification content (truncated to 150 characters), and sends to OneSignal’s **“Subscribed Users”** segment. Title: *“Popular post from ECHO”*; body: the post text (or truncated with “…”).

3. Schedule it daily at **3pm** (e.g. Mexico City): use an external cron ([cron-job.org](https://cron-job.org), GitHub Actions, or a cloud scheduler) to **POST** (or GET) to  
   `https://<project-ref>.supabase.co/functions/v1/daily-popular-post`  
   with header `Authorization: Bearer <SUPABASE_ANON_KEY>`. Set the cron to 3:00 PM in your timezone (e.g. `America/Mexico_City`).

---

## Backend (next steps)

Data is **in-memory** only. To ship:

1. Add a backend (Firebase, Supabase, or custom API).
2. Replace `AppState` usage with API calls (fetch feed, post, comment, vote).
3. Add auth (e.g. phone or .edu email) if you want verified campus.
4. Add reporting/moderation and push notifications.

## License

Use and modify as you need for your product.



resend api key: re_XWJF4nME_43cjUcmJNLERwUJVmTvZgz7E

supabase access token: sbp_73119fedf9a89e5bdcdac5aa6034e63229fb0691

workos api:sk_test_a2V5XzAxS0g5VEtENjhZMllOU0JNVFJUSjJKU1ZKLDd4SFN3VW9udHJldGZLdkl0TElYYnRxRzM

client id workos:
client_01KH9TKDREZWXQ8ZJ3YFZMK2EG

review@echoiosone.com

onesignal app id:
c274d7ea-3cd0-48c4-87fc-628dce6d455d


onesignal api key:
os_v2_app_yj2np2r42bemjb74mkg443kflxlyimgqn4zexfm5dtxsviflzi2tv76qby54j6f2t2e2g2fnz2slrrhfykcwiluco7s6q3hzd2ucc2a

onesignal app id:
c274d7ea-3cd0-48c4-87fc-628dce6d455d
