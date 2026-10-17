ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_kind_check;
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_name_check;
ALTER TABLE conversations ALTER COLUMN name DROP NOT NULL;
ALTER TABLE conversations
  ADD CONSTRAINT conversations_kind_check CHECK (kind IN ('group', 'direct'));
ALTER TABLE conversations
  ADD CONSTRAINT conversations_name_check CHECK (
    kind = 'direct' OR (name IS NOT NULL AND char_length(name) BETWEEN 1 AND 80)
  );
