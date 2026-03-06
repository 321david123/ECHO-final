-- Add optional image to posts (URL from Supabase Storage).
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.posts.image_url IS 'Public URL of image in Storage bucket post-images.';

-- Create bucket in Dashboard: Storage → New bucket → name "post-images", Public = on.
-- Add policy: Storage → post-images → Policies → "Allow authenticated uploads" → INSERT for authenticated.
