-- Private messages: only creatable from a post (message the post author).
-- One conversation per (post, initiator); participants are post_author + initiator.

CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  post_author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  initiator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT conversations_post_initiator_unique UNIQUE (post_id, initiator_id),
  CONSTRAINT conversations_no_self_message CHECK (post_author_id != initiator_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_post ON public.conversations(post_id);
CREATE INDEX IF NOT EXISTS idx_conversations_post_author ON public.conversations(post_author_id);
CREATE INDEX IF NOT EXISTS idx_conversations_initiator ON public.conversations(initiator_id);

CREATE TABLE IF NOT EXISTS public.private_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (char_length(body) <= 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_private_messages_conversation ON public.private_messages(conversation_id);

-- RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.private_messages ENABLE ROW LEVEL SECURITY;

-- Participants: post_author or initiator
CREATE POLICY "Conversations: participants can view"
  ON public.conversations FOR SELECT
  USING (auth.uid() = post_author_id OR auth.uid() = initiator_id);

CREATE POLICY "Conversations: initiator can insert (when messaging post author)"
  ON public.conversations FOR INSERT
  WITH CHECK (auth.uid() = initiator_id AND auth.uid() != post_author_id);

-- Messages: only participants can read/insert
CREATE POLICY "Private messages: participants can view"
  ON public.private_messages FOR SELECT
  USING (
    conversation_id IN (
      SELECT id FROM public.conversations
      WHERE post_author_id = auth.uid() OR initiator_id = auth.uid()
    )
  );

CREATE POLICY "Private messages: participants can insert"
  ON public.private_messages FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id
    AND conversation_id IN (
      SELECT id FROM public.conversations
      WHERE post_author_id = auth.uid() OR initiator_id = auth.uid()
    )
  );
