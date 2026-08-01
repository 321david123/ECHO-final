-- ECHO: Reportes de posts/comentarios.
-- El usuario toca "Reportar", se guarda en esta tabla. Tú lo revisas en el dashboard.

CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
  comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT report_target CHECK (post_id IS NOT NULL OR comment_id IS NOT NULL)
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Usuarios solo pueden insertar (no leer los de otros).
CREATE POLICY "Users can insert their own reports"
  ON public.reports FOR INSERT
  WITH CHECK (reporter_id = auth.uid());

-- Solo tú (service_role / SQL editor) puede leer todos.
CREATE POLICY "Only service role reads reports"
  ON public.reports FOR SELECT
  USING (false);

CREATE INDEX IF NOT EXISTS idx_reports_post ON public.reports (post_id) WHERE post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_comment ON public.reports (comment_id) WHERE comment_id IS NOT NULL;
