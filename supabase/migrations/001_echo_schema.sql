-- ECHO: Schema for Supabase (auth + profiles, posts, comments, votes)
-- Run this in Supabase SQL Editor or via supabase db push

-- Campuses (reference data; matches app Campus.id)
CREATE TABLE IF NOT EXISTS public.campuses (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  short_name TEXT NOT NULL,
  city TEXT NOT NULL
);

INSERT INTO public.campuses (id, name, short_name, city) VALUES
  ('tec-monterrey', 'Tecnológico de Monterrey', 'Tec', 'Monterrey'),
  ('tec-gdl', 'Tec de Monterrey - Guadalajara', 'Tec GDL', 'Guadalajara'),
  ('tec-cdmx', 'Tec de Monterrey - CDMX', 'Tec CDMX', 'Ciudad de México'),
  ('unam', 'UNAM', 'UNAM', 'Ciudad de México'),
  ('itam', 'ITAM', 'ITAM', 'Ciudad de México'),
  ('ibero', 'Universidad Iberoamericana', 'Ibero', 'Ciudad de México'),
  ('anahuac', 'Universidad Anáhuac', 'Anáhuac', 'Ciudad de México'),
  ('udlap', 'UDLAP', 'UDLAP', 'Puebla'),
  ('tec-puebla', 'Tec de Monterrey - Puebla', 'Tec Puebla', 'Puebla'),
  ('tec-queretaro', 'Tec de Monterrey - Querétaro', 'Tec Qro', 'Querétaro')
ON CONFLICT (id) DO NOTHING;

-- User profile (linked to auth.users; one row per user)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  campus_id TEXT NOT NULL REFERENCES public.campuses(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Posts (anonymous; author_id optional for true anonymity, or set for karma)
CREATE TABLE IF NOT EXISTS public.posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  body TEXT NOT NULL CHECK (char_length(body) <= 200),
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  campus_id TEXT NOT NULL REFERENCES public.campuses(id),
  score INT NOT NULL DEFAULT 0,
  comment_count INT NOT NULL DEFAULT 0,
  is_hidden BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_posts_campus_created ON public.posts(campus_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_campus_score ON public.posts(campus_id, score DESC);

-- Comments
CREATE TABLE IF NOT EXISTS public.comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  score INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_comments_post ON public.comments(post_id, created_at);

-- One vote per user per post
CREATE TABLE IF NOT EXISTS public.votes (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  direction SMALLINT NOT NULL CHECK (direction IN (-1, 0, 1)),
  PRIMARY KEY (user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_votes_post ON public.votes(post_id);

-- Trigger: update post score when vote changes
CREATE OR REPLACE FUNCTION public.update_post_score()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET score = score - OLD.direction WHERE id = OLD.post_id;
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.posts SET score = score - OLD.direction + NEW.direction WHERE id = NEW.post_id;
    RETURN NEW;
  ELSE
    UPDATE public.posts SET score = score + NEW.direction WHERE id = NEW.post_id;
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS votes_update_score ON public.votes;
CREATE TRIGGER votes_update_score
  AFTER INSERT OR UPDATE OR DELETE ON public.votes
  FOR EACH ROW EXECUTE FUNCTION public.update_post_score();

-- Trigger: hide post when score <= -5
CREATE OR REPLACE FUNCTION public.maybe_hide_post()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.score <= -5 THEN
    NEW.is_hidden := true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS posts_maybe_hide ON public.posts;
CREATE TRIGGER posts_maybe_hide
  BEFORE UPDATE OF score ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.maybe_hide_post();

-- Trigger: increment comment_count on post when comment inserted
CREATE OR REPLACE FUNCTION public.increment_comment_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.posts SET comment_count = comment_count + 1 WHERE id = NEW.post_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS comments_count ON public.comments;
CREATE TRIGGER comments_count
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.increment_comment_count();

-- RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campuses ENABLE ROW LEVEL SECURITY;

-- Campuses: read by everyone
CREATE POLICY "Campuses are viewable by everyone"
  ON public.campuses FOR SELECT USING (true);

-- Profiles: user can read/update own; can read others' campus for feed
CREATE POLICY "Users can view all profiles"
  ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Posts: anyone authenticated can read posts for their campus; insert/update with auth
CREATE POLICY "Users can view non-hidden posts in their campus"
  ON public.posts FOR SELECT
  USING (
    is_hidden = false
    AND campus_id IN (SELECT campus_id FROM public.profiles WHERE id = auth.uid())
  );
CREATE POLICY "Users can insert posts in their campus"
  ON public.posts FOR INSERT
  WITH CHECK (
    campus_id IN (SELECT campus_id FROM public.profiles WHERE id = auth.uid())
  );
CREATE POLICY "Users can update own posts"
  ON public.posts FOR UPDATE USING (author_id = auth.uid());

-- Comments: read for posts in user's campus; insert for authenticated
CREATE POLICY "Users can view comments for posts in their campus"
  ON public.comments FOR SELECT
  USING (
    post_id IN (
      SELECT id FROM public.posts
      WHERE campus_id IN (SELECT campus_id FROM public.profiles WHERE id = auth.uid())
    )
  );
CREATE POLICY "Users can insert comments"
  ON public.comments FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- Votes: user can manage own votes
CREATE POLICY "Users can view own votes"
  ON public.votes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own vote"
  ON public.votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own vote"
  ON public.votes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own vote"
  ON public.votes FOR DELETE USING (auth.uid() = user_id);

-- Allow anon read for campuses only (for onboarding picker before login)
CREATE POLICY "Anon can read campuses"
  ON public.campuses FOR SELECT TO anon USING (true);
