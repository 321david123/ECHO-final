-- Accent color for the profile avatar background. Stored as a short string name
-- (e.g. "green", "blue") that the app maps to an actual Color. Nullable; app
-- defaults to "green" when absent.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS accent_color TEXT;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_accent_color_length,
  ADD CONSTRAINT profiles_accent_color_length CHECK (accent_color IS NULL OR char_length(accent_color) BETWEEN 1 AND 16);

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS author_accent_color TEXT;

ALTER TABLE public.posts
  DROP CONSTRAINT IF EXISTS posts_author_accent_color_length,
  ADD CONSTRAINT posts_author_accent_color_length CHECK (author_accent_color IS NULL OR char_length(author_accent_color) BETWEEN 1 AND 16);
