-- ECHO: Pinned posts (avisos del admin, sin votos)
-- Solo el admin puede fijar posts vía SQL/dashboard.

ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_posts_pinned ON public.posts (is_pinned) WHERE is_pinned = true;
