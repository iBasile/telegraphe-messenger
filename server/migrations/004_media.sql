CREATE TABLE IF NOT EXISTS media (
  id UUID PRIMARY KEY,
  conversation_id UUID NOT NULL,
  owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  object_key TEXT NOT NULL UNIQUE,
  content_type TEXT NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm')),
  byte_size BIGINT NOT NULL CHECK (byte_size > 0),
  width INTEGER NOT NULL CHECK (width > 0),
  height INTEGER NOT NULL CHECK (height > 0),
  duration_seconds INTEGER,
  thumbnail_object_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS media_conversation_idx ON media(conversation_id);
CREATE INDEX IF NOT EXISTS media_expiry_idx ON media(expires_at);
