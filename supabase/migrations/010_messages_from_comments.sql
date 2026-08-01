-- ECHO: 1) DM desde un comentario (no solo desde el post)
--       2) Auto-upvote del autor cuando crea un post
-- Correr en SQL Editor.

-- ---------------------------------------------------------------------------
-- 1) conversations.comment_id (NULL para conversaciones legacy “mensaje al autor del post”)
-- ---------------------------------------------------------------------------
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS comment_id UUID REFERENCES public.comments(id) ON DELETE SET NULL;

-- Reemplaza el UNIQUE viejo (post_id, initiator_id) por uno que incluye el comment.
-- Así un mismo usuario puede abrir varias conversaciones desde el mismo post:
--   una con el autor del post (comment_id NULL) y/o una con cada comentarista.
ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_post_initiator_unique;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_unique_post_initiator_target
  ON public.conversations (
    post_id,
    initiator_id,
    COALESCE(comment_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

CREATE INDEX IF NOT EXISTS idx_conversations_comment ON public.conversations(comment_id);

-- ---------------------------------------------------------------------------
-- 2) Auto-upvote del autor del post (el post sale con score = 1 ya votado por su autor)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.author_self_upvote()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.author_id IS NOT NULL THEN
    INSERT INTO public.votes (user_id, post_id, direction)
    VALUES (NEW.author_id, NEW.id, 1)
    ON CONFLICT (user_id, post_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_post_author_self_upvote ON public.posts;
CREATE TRIGGER tr_post_author_self_upvote
  AFTER INSERT ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.author_self_upvote();
