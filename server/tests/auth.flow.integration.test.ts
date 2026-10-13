import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config.js';
import type { EmailSender } from '../src/email.js';

const enabled = Boolean(process.env.DATABASE_URL);
describe.skipIf(!enabled)('authentication flow (PostgreSQL)', () => {
  it('registers, verifies, logs in, refreshes and logs out one device', async () => {
    const db = new pg.Pool({ connectionString: process.env.DATABASE_URL });
    const sent: string[] = [];
    const email: EmailSender = {
      async send(_to, _subject, text) {
        sent.push(text);
      },
    };
    const app = await buildApp({
      db,
      emailSender: email,
      cfg: { ...config, DATABASE_URL: process.env.DATABASE_URL! },
    });
    const address = `integration-${randomUUID()}@example.com`;
    const deviceId = randomUUID();
    const register = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: address,
        password: 'correct horse battery staple',
        displayName: 'Test',
        deviceId,
      },
    });
    expect(register.statusCode).toBe(201);
    const token = sent[0].match(/token=([^\s]+)/)?.[1];
    expect(token).toBeTruthy();
    expect(
      (await app.inject({ method: 'POST', url: '/auth/verify-email', payload: { token } }))
        .statusCode,
    ).toBe(200);
    const login = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: address, password: 'correct horse battery staple', deviceId },
    });
    expect(login.statusCode).toBe(200);
    const credentials = login.json();
    const refresh = await app.inject({
      method: 'POST',
      url: '/auth/refresh',
      payload: { token: credentials.refreshToken, deviceId },
    });
    expect(refresh.statusCode).toBe(200);
    const refreshedCredentials = refresh.json();
    expect(
      (
        await app.inject({
          method: 'POST',
          url: '/auth/logout',
          payload: { token: refreshedCredentials.refreshToken, deviceId },
        })
      ).statusCode,
    ).toBe(204);
    expect(
      (
        await app.inject({
          method: 'POST',
          url: '/auth/refresh',
          payload: { token: refreshedCredentials.refreshToken, deviceId },
        })
      ).statusCode,
    ).toBe(401);
    await app.close();
    await db.end();
  });
});
