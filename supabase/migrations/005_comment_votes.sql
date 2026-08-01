-- Comment votes: one vote per user per comment (mirrors post votes)
CREATE TABLE IF NOT EXISTS public.comment_votes (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  comment_id UUID NOT NULL REFERENCES public.comments(id) ON DELETE CASCADE,
  direction SMALLINT NOT NULL CHECK (direction IN (-1, 0, 1)),
  PRIMARY KEY (user_id, comment_id)
);

CREATE INDEX IF NOT EXISTS idx_comment_votes_comment ON public.comment_votes(comment_id);

-- Trigger: update comment score when a comment vote changes
CREATE OR REPLACE FUNCTION public.update_comment_score()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.comments SET score = score - OLD.direction WHERE id = OLD.comment_id;
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.comments SET score = score - OLD.direction + NEW.direction WHERE id = NEW.comment_id;
    RETURN NEW;
  ELSE
    UPDATE public.comments SET score = score + NEW.direction WHERE id = NEW.comment_id;
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS comment_votes_update_score ON public.comment_votes;
CREATE TRIGGER comment_votes_update_score
  AFTER INSERT OR UPDATE OR DELETE ON public.comment_votes
  FOR EACH ROW EXECUTE FUNCTION public.update_comment_score();

-- RLS
ALTER TABLE public.comment_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own comment votes"
  ON public.comment_votes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own comment vote"
  ON public.comment_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own comment vote"
  ON public.comment_votes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own comment vote"
  ON public.comment_votes FOR DELETE USING (auth.uid() = user_id);
