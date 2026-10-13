import { describe, expect, it } from 'vitest';
import { GroupPermissionError, requireAdmin } from '../src/groups.js';
import { MemoryMessageRouter } from '../src/router.js';

describe('group permissions', () => {
  it('rejects members for administrator actions', () => {
    expect(() => requireAdmin('member')).toThrow(GroupPermissionError);
    expect(() => requireAdmin(undefined)).toThrow(GroupPermissionError);
    expect(() => requireAdmin('admin')).not.toThrow();
  });
});

describe('group fan-out router', () => {
  it('delivers to each connected member and not to a removed member', async () => {
    const router = new MemoryMessageRouter();
    const received = new Map<string, number>();
    for (const device of ['a', 'b', 'removed']) {
      received.set(device, 0);
      await router.register(device, () => received.set(device, (received.get(device) ?? 0) + 1));
    }
    await router.route('a', new Uint8Array([1]));
    await router.route('b', new Uint8Array([1]));
    await router.unregister('removed');
    expect(received).toEqual(
      new Map([
        ['a', 1],
        ['b', 1],
        ['removed', 0],
      ]),
    );
  });
});
