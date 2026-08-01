-- Denormalize author display_name and emoji on posts at insert time so feed rendering
-- is a single query. If a user later changes their profile display, old posts keep the
-- name/emoji they had at the time of posting (similar to how Reddit/Twitter work).

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS author_display_name TEXT,
  ADD COLUMN IF NOT EXISTS author_emoji TEXT;

ALTER TABLE public.posts
  DROP CONSTRAINT IF EXISTS posts_author_display_name_length,
  ADD CONSTRAINT posts_author_display_name_length CHECK (author_display_name IS NULL OR char_length(author_display_name) BETWEEN 1 AND 24);

ALTER TABLE public.posts
  DROP CONSTRAINT IF EXISTS posts_author_emoji_length,
  ADD CONSTRAINT posts_author_emoji_length CHECK (author_emoji IS NULL OR char_length(author_emoji) BETWEEN 1 AND 8);
