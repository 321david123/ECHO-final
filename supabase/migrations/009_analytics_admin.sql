-- ECHO: admin push on new posts + analytics (sessions, events, post views)
-- Run in Supabase SQL Editor after 001–008 migrations and push_notification_queue setup.

-- ---------------------------------------------------------------------------
-- 1) Admin config (solo tú recibes push cuando alguien publica)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_config IS 'App-wide config. Set admin_user_id to your auth.users UUID.';

-- RLS: nadie desde la app lee esto; solo service_role / SQL editor
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

INSERT INTO public.app_config (key, value) VALUES
  ('admin_user_id', 'REEMPLAZA_CON_TU_UUID'),
  ('notify_admin_on_new_post', 'true'),
  ('admin_notify_title', 'Nuevo post en ECHO'),
  ('admin_notify_body_max_chars', '120')
ON CONFLICT (key) DO NOTHING;

-- Obtén tu UUID con:
--   SELECT id, email FROM auth.users WHERE email = 'tu@email.com';

CREATE OR REPLACE FUNCTION public.config_text(p_key TEXT, p_default TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT value FROM public.app_config WHERE key = p_key), p_default);
$$;

CREATE OR REPLACE FUNCTION public.notify_admin_on_new_post()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
  v_enabled TEXT;
  v_title TEXT;
  v_max INT;
  v_body TEXT;
  v_campus TEXT;
BEGIN
  v_enabled := public.config_text('notify_admin_on_new_post', 'false');
  IF v_enabled IS DISTINCT FROM 'true' THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_admin_id := public.config_text('admin_user_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
  END;

  IF v_admin_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- No te notifiques tus propios posts
  IF NEW.author_id IS NOT NULL AND NEW.author_id = v_admin_id THEN
    RETURN NEW;
  END IF;

  SELECT short_name INTO v_campus FROM public.campuses WHERE id = NEW.campus_id;
  v_title := COALESCE(public.config_text('admin_notify_title'), 'Nuevo post en ECHO');
  v_max := COALESCE(public.config_text('admin_notify_body_max_chars', '120')::int, 120);
  v_body := left(trim(NEW.body), v_max);
  IF v_campus IS NOT NULL AND v_campus <> '' THEN
    v_body := '[' || v_campus || '] ' || v_body;
  END IF;

  INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
  VALUES (
    v_admin_id,
    'admin_new_post',
    v_title,
    v_body,
    jsonb_build_object('kind', 'admin_new_post', 'post_id', NEW.id, 'campus_id', NEW.campus_id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_admin_new_post ON public.posts;
CREATE TRIGGER tr_notify_admin_new_post
  AFTER INSERT ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admin_on_new_post();

-- ---------------------------------------------------------------------------
-- 2) Sesiones (aperturas y tiempo en app)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  duration_seconds INT GENERATED ALWAYS AS (
    CASE
      WHEN ended_at IS NOT NULL THEN GREATEST(0, EXTRACT(EPOCH FROM (ended_at - started_at))::int)
      ELSE GREATEST(0, EXTRACT(EPOCH FROM (last_heartbeat_at - started_at))::int)
    END
  ) STORED,
  app_version TEXT,
  platform TEXT NOT NULL DEFAULT 'ios',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_sessions_user_started ON public.app_sessions(user_id, started_at DESC);

ALTER TABLE public.app_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own sessions"
  ON public.app_sessions FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own open sessions"
  ON public.app_sessions FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own sessions"
  ON public.app_sessions FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 3) Eventos genéricos (pantallas, taps, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES public.app_sessions(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  properties JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_events_user_created ON public.app_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_events_name ON public.app_events(name, created_at DESC);

ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own events"
  ON public.app_events FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own events"
  ON public.app_events FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 4) Vistas de posts (impresiones)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.post_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'feed' CHECK (source IN ('feed', 'detail', 'explore')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_post_views_post ON public.post_views(post_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_views_user ON public.post_views(user_id, created_at DESC);

-- Una vista por usuario/post/día (evita inflar números al hacer scroll)
CREATE UNIQUE INDEX IF NOT EXISTS idx_post_views_unique_daily
  ON public.post_views(post_id, user_id, ((created_at AT TIME ZONE 'UTC')::date));

ALTER TABLE public.post_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own post views"
  ON public.post_views FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own post views"
  ON public.post_views FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 5) Vistas SQL para dashboard (correr como service_role en SQL Editor)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.analytics_user_summary AS
SELECT
  p.id AS user_id,
  p.campus_id,
  c.short_name AS campus,
  p.created_at AS joined_at,
  (SELECT count(*)::int FROM public.posts po WHERE po.author_id = p.id) AS posts_count,
  (SELECT count(*)::int FROM public.comments cm WHERE cm.author_id = p.id) AS comments_count,
  (SELECT count(*)::int FROM public.app_sessions s WHERE s.user_id = p.id) AS session_count,
  (SELECT COALESCE(sum(s.duration_seconds), 0)::bigint FROM public.app_sessions s WHERE s.user_id = p.id) AS total_time_seconds,
  (SELECT max(s.started_at) FROM public.app_sessions s WHERE s.user_id = p.id) AS last_seen_at
FROM public.profiles p
LEFT JOIN public.campuses c ON c.id = p.campus_id;

CREATE OR REPLACE VIEW public.analytics_post_views AS
SELECT
  po.id AS post_id,
  left(po.body, 80) AS body_preview,
  po.campus_id,
  po.score,
  po.comment_count,
  po.created_at,
  count(pv.id)::int AS view_count,
  count(DISTINCT pv.user_id)::int AS unique_viewers
FROM public.posts po
LEFT JOIN public.post_views pv ON pv.post_id = po.id
GROUP BY po.id;

COMMENT ON VIEW public.analytics_user_summary IS 'Resumen por usuario; consultar con service_role en Dashboard.';
COMMENT ON VIEW public.analytics_post_views IS 'Vistas e impresiones por post.';

-- Solo tú (SQL Editor / service_role) ves agregados; la app no expone estas vistas.
REVOKE ALL ON public.analytics_user_summary FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.analytics_post_views FROM PUBLIC, anon, authenticated;
