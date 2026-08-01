-- Add optional display name and emoji to profiles so users can personalize their identity.
-- Both nullable; app falls back to "Anónimo" + initial letter when not set.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS display_name TEXT,
  ADD COLUMN IF NOT EXISTS emoji TEXT;

-- Reasonable length/content constraints. Emoji is 1-8 characters to allow composite emoji (e.g. 👨‍💻).
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_display_name_length,
  ADD CONSTRAINT profiles_display_name_length CHECK (display_name IS NULL OR char_length(display_name) BETWEEN 1 AND 24);

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_emoji_length,
  ADD CONSTRAINT profiles_emoji_length CHECK (emoji IS NULL OR char_length(emoji) BETWEEN 1 AND 8);
