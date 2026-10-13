import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';

describe('auth integration prerequisites', () => {
  it('exposes a health endpoint without database access', async () => {
    const app = await buildApp({ db: undefined });
    const response = await app.inject({ method: 'GET', url: '/health' });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'ok' });
    await app.close();
  });
});
