import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pool } from './db.js';
await pool.query(
  'CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())',
);
const files = (await readdir(new URL('../migrations/', import.meta.url)))
  .filter((f) => f.endsWith('.sql'))
  .sort();
for (const name of files) {
  const applied = await pool.query('SELECT 1 FROM schema_migrations WHERE name=$1', [name]);
  if (!applied.rowCount) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        await readFile(join(new URL('../migrations/', import.meta.url).pathname, name), 'utf8'),
      );
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [name]);
      await client.query('COMMIT');
      console.log(`Applied ${name}`);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}
await pool.end();
