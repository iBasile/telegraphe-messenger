import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const proto = await readFile(new URL('../../proto/telegraphe.proto', import.meta.url));
const generated = await readFile(
  new URL('../src/generated/telegraphe.ts', import.meta.url),
  'utf8',
);
const expected = createHash('sha256').update(proto).digest('hex');
const actual = generated.match(/proto-sha256: ([a-f0-9]{64})/)?.[1];
if (actual !== expected) {
  throw new Error(
    `Generated protobuf types are stale: expected ${expected}, found ${actual ?? 'none'}`,
  );
}
console.log('Generated protobuf types are up to date.');
