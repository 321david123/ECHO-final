-- ECHO migration 011: replies a comentarios, búsqueda full-text, hashtags,
-- reacciones extra (1 al día por tipo por usuario), notificaciones de reply
-- y `kind` en payload de push para deep-linking.
--
-- Construye sobre 001-008 + 010 (no requiere 009).
-- Asume que push_notification_queue y device_tokens existen (creadas según README).

-- =========================================================
-- 1) Replies a comentarios (un nivel)
-- =========================================================
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS parent_comment_id UUID
  REFERENCES public.comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_comments_parent ON public.comments(parent_comment_id);

-- =========================================================
-- 2) Búsqueda full-text en posts (idioma español)
-- =========================================================
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('spanish', coalesce(body, ''))) STORED;

CREATE INDEX IF NOT EXISTS idx_posts_tsv ON public.posts USING GIN(tsv);

-- =========================================================
-- 3) Hashtags (#palabra). Trigger extrae al insertar.
-- =========================================================
CREATE TABLE IF NOT EXISTS public.post_tags (
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tag TEXT NOT NULL CHECK (char_length(tag) BETWEEN 2 AND 30),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_post_tags_tag ON public.post_tags(tag, created_at DESC);

ALTER TABLE public.post_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_tags select via post visibility" ON public.post_tags;
CREATE POLICY "post_tags select via post visibility"
  ON public.post_tags FOR SELECT
  USING (
    post_id IN (
      SELECT id FROM public.posts
      WHERE is_hidden = false
        AND campus_id IN (SELECT campus_id FROM public.profiles WHERE id = auth.uid())
    )
  );

CREATE OR REPLACE FUNCTION public.extract_post_hashtags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT regexp_matches(NEW.body, '#([[:alnum:]_]{2,30})', 'g') AS arr
  LOOP
    INSERT INTO public.post_tags(post_id, tag)
    VALUES (NEW.id, lower(rec.arr[1]))
    ON CONFLICT DO NOTHING;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_extract_post_hashtags ON public.posts;
CREATE TRIGGER tr_extract_post_hashtags
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.extract_post_hashtags();

-- =========================================================
-- 4) Reacciones extra (🔥 😂 💯)
--    Constraint: 1 vez al día (UTC) por usuario por tipo de reacción (global).
-- =========================================================
CREATE TABLE IF NOT EXISTS public.post_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction TEXT NOT NULL CHECK (reaction IN ('fire', 'laugh', 'hundred')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_post_reactions_post ON public.post_reactions(post_id, reaction);
CREATE INDEX IF NOT EXISTS idx_post_reactions_user_created ON public.post_reactions(user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_reactions_unique_user_daily
  ON public.post_reactions (user_id, reaction, ((created_at AT TIME ZONE 'UTC')::date));

ALTER TABLE public.post_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_reactions select for visible posts" ON public.post_reactions;
CREATE POLICY "post_reactions select for visible posts"
  ON public.post_reactions FOR SELECT
  USING (
    post_id IN (
      SELECT id FROM public.posts
      WHERE is_hidden = false
        AND campus_id IN (SELECT campus_id FROM public.profiles WHERE id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "post_reactions insert own" ON public.post_reactions;
CREATE POLICY "post_reactions insert own"
  ON public.post_reactions FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- =========================================================
-- 5) Triggers de notificación: TODOS incluyen `kind` en el JSON payload
--    para que la app pueda hacer deep-linking al post o conversación correctos.
-- =========================================================

-- 5a. Reply a comentario (NUEVO)
CREATE OR REPLACE FUNCTION public.notify_comment_reply()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_author UUID;
BEGIN
  IF NEW.parent_comment_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT author_id INTO v_parent_author FROM public.comments WHERE id = NEW.parent_comment_id;
  IF v_parent_author IS NULL OR v_parent_author = NEW.author_id THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
  VALUES (
    v_parent_author,
    'comment_reply',
    'Te respondieron',
    'Alguien respondió tu comentario.',
    jsonb_build_object(
      'kind', 'comment_reply',
      'post_id', NEW.post_id,
      'comment_id', NEW.id
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_comment_reply_notify ON public.comments;
CREATE TRIGGER tr_comment_reply_notify
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_comment_reply();

-- 5b. Comentario en mi post (REEMPLAZA el del README para incluir `kind`)
CREATE OR REPLACE FUNCTION public.notify_comment_on_post()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_author_id UUID;
BEGIN
  -- Si es reply (tiene parent), el trigger notify_comment_reply se encarga.
  IF NEW.parent_comment_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT author_id INTO v_author_id FROM public.posts WHERE id = NEW.post_id;
  IF v_author_id IS NOT NULL AND v_author_id != NEW.author_id THEN
    INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
    VALUES (
      v_author_id,
      'comment',
      'Nuevo comentario',
      'Alguien comentó en tu publicación.',
      jsonb_build_object(
        'kind', 'comment',
        'post_id', NEW.post_id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_comment_notify ON public.comments;
CREATE TRIGGER tr_comment_notify
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_comment_on_post();

-- 5c. Milestones de votos en post (REEMPLAZA el del README)
CREATE OR REPLACE FUNCTION public.notify_post_score_milestone()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.author_id IS NOT NULL
     AND NEW.score IN (5, 10, 20, 100)
     AND (OLD.score IS NULL OR OLD.score < NEW.score)
     AND NEW.score > COALESCE(OLD.score, 0)
  THEN
    INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
    VALUES (
      NEW.author_id,
      'post_milestone',
      'Tu ECHO va en alza',
      'Tu publicación llegó a ' || NEW.score || ' votos.',
      jsonb_build_object(
        'kind', 'post_milestone',
        'post_id', NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_post_score_milestone ON public.posts;
CREATE TRIGGER tr_post_score_milestone
  AFTER UPDATE OF score ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_post_score_milestone();

-- 5d. DM nuevo (REEMPLAZA el del README)
CREATE OR REPLACE FUNCTION public.notify_private_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_post_author_id UUID;
  v_initiator_id UUID;
  v_recipient_id UUID;
BEGIN
  SELECT post_author_id, initiator_id INTO v_post_author_id, v_initiator_id
  FROM public.conversations WHERE id = NEW.conversation_id;
  IF NEW.sender_id = v_initiator_id THEN
    v_recipient_id := v_post_author_id;
  ELSE
    v_recipient_id := v_initiator_id;
  END IF;
  IF v_recipient_id IS NOT NULL THEN
    INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
    VALUES (
      v_recipient_id,
      'dm',
      'Nuevo mensaje',
      'Te enviaron un mensaje directo.',
      jsonb_build_object(
        'kind', 'dm',
        'conversation_id', NEW.conversation_id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_private_message_notify ON public.private_messages;
CREATE TRIGGER tr_private_message_notify
  AFTER INSERT ON public.private_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_private_message();

-- (admin_new_post de migración 009 no se reescribe aquí porque no aplicaste 009;
--  cuando la apliques, su payload ya incluye 'kind' = 'admin_new_post'.)
