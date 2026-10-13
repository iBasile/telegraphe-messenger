CREATE TABLE IF NOT EXISTS mailbox (
  id BIGSERIAL PRIMARY KEY,
  recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL,
  client_id UUID NOT NULL,
  envelope BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (recipient_device_id, client_id)
);
CREATE INDEX IF NOT EXISTS mailbox_device_cursor_idx ON mailbox(recipient_device_id, id);

CREATE TABLE IF NOT EXISTS mailbox_cursors (
  device_id UUID PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  acknowledged_id BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
