import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import cors from '@fastify/cors';
import { z } from 'zod';
import { randomUUID } from 'node:crypto';
import type pg from 'pg';
import { config as defaultConfig, type Config } from './config.js';
import {
  accessToken,
  hashPassword,
  hashToken,
  randomToken,
  refreshExpiry,
  verifyPassword,
} from './auth.js';
import { createEmailSender, type EmailSender } from './email.js';
import { pool as defaultPool } from './db.js';
import { MemoryMailboxStore, PostgresMailboxStore, type MailboxStore } from './mailbox.js';
import { MemoryMessageRouter, type MessageRouter } from './router.js';
import { MemoryPresenceStore, type RedisPresenceStore } from './presence.js';
import { registerWebSocket } from './websocket.js';
import { broadcastSystemEvent, GroupPermissionError, groupRole, requireAdmin } from './groups.js';
import { MinioMediaStorage, type MediaStorage } from './media.js';
import { Metrics } from './metrics.js';
import type { NotificationQueue } from './notifications.js';

const credentials = z.object({
  email: z
    .string()
    .email()
    .transform((v) => v.toLowerCase()),
  password: z.string().min(12).max(128),
});
const device = z.object({
  deviceId: z.string().uuid(),
  deviceName: z.string().max(100).optional(),
});
const profile = z
  .object({
    displayName: z.string().trim().min(1).max(80).optional(),
    avatarUrl: z
      .string()
      .url()
      .max(500)
      .refine(
        (url) => url.startsWith('https://') || url.startsWith('http://'),
        { message: 'L’URL de l’avatar doit débuter par http:// ou https://' },
      )
      .nullable()
      .optional(),
  })
  .refine((v) => v.displayName !== undefined || v.avatarUrl !== undefined);
const tokenBody = z.object({ token: z.string().min(20) });
const bad = (reply: FastifyReply, message: string): FastifyReply =>
  reply.code(400).send({ error: message });

export interface AppOptions {
  db?: pg.Pool;
  emailSender?: EmailSender;
  cfg?: Config;
  mailbox?: MailboxStore;
  router?: MessageRouter;
  presence?: RedisPresenceStore | MemoryPresenceStore;
  mediaStorage?: MediaStorage;
  notificationQueue?: NotificationQueue;
  metrics?: Metrics;
}
export async function buildApp(options: AppOptions = {}): Promise<FastifyInstance> {
  const cfg = options.cfg ?? defaultConfig;
  const db = options.db ?? defaultPool;
  const email = options.emailSender ?? createEmailSender(cfg);
  const metrics = options.metrics ?? new Metrics();
  const DUMMY_HASH = await hashPassword('dummy-constant-time-password-hash');
  const app = Fastify({
    logger: { redact: ['req.headers.authorization', 'body.password', 'body.token'] },
  });
  await app.register(cors);
  app.addHook('onSend', async (_request, reply) => {
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('X-Frame-Options', 'DENY');
    reply.header('Referrer-Policy', 'no-referrer');
    reply.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
    reply.header('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none';");
  });
  await app.register(rateLimit, { max: 100, timeWindow: '1 minute' });
  await app.register(jwt, { secret: cfg.JWT_SECRET });
  const mailbox = options.mailbox ?? new PostgresMailboxStore(db);
  const messageRouter = options.router ?? new MemoryMessageRouter();
  await registerWebSocket(app, {
    db,
    mailbox,
    router: messageRouter,
    presence: options.presence ?? new MemoryPresenceStore(),
    protocolVersion: cfg.PROTOCOL_VERSION,
    notificationQueue: options.notificationQueue,
    metrics,
    messageRateMax: cfg.MESSAGE_RATE_MAX,
  });
  app.decorate('config', cfg);
  app.decorate('authenticate', async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      await request.jwtVerify();
    } catch {
      await reply.code(401).send({ error: 'Authentification requise' });
    }
  });
  const auth = async (request: FastifyRequest): Promise<{ userId: string; deviceId: string }> => ({
    userId: request.user.sub,
    deviceId: request.user.deviceId,
  });
  const groupMailbox = mailbox;
  const groupRouter = messageRouter;
  const mediaStorage = options.mediaStorage ?? new MinioMediaStorage(cfg);
  app.get('/health', async () => ({ status: 'ok' }));
  app.get('/metrics', async (_request, reply) => {
    const result = await db.query<{ count: string }>('SELECT count(*) FROM mailbox');
    return reply
      .type('text/plain; version=0.0.4')
      .send(metrics.render(Number(result.rows[0].count)));
  });
  app.post('/devices/push-token', { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = z
      .object({
        deviceId: z.string().uuid(),
        platform: z.literal('android'),
        token: z.string().min(20).max(4096),
      })
      .safeParse(request.body);
    if (!parsed.success) return bad(reply, 'Jeton push invalide');
    const { userId } = await auth(request);
    if (parsed.data.deviceId !== request.user.deviceId)
      return reply.code(403).send({ error: 'Accès refusé' });
    await db.query(
      `INSERT INTO push_tokens (device_id,user_id,platform,token)
       VALUES ($1,$2,$3,$4)
       ON CONFLICT (device_id,platform) DO UPDATE SET token=EXCLUDED.token,updated_at=now()`,
      [parsed.data.deviceId, userId, parsed.data.platform, parsed.data.token],
    );
    return reply.code(204).send();
  });
  app.get('/mailbox', { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = z
      .object({ cursor: z.coerce.number().int().nonnegative().default(0) })
      .safeParse(request.query);
    if (!parsed.success) return bad(reply, 'Curseur invalide');
    const items = (await mailbox.pending(request.user.deviceId)).filter(
      (item) => item.id > parsed.data.cursor,
    );
    return {
      cursor: items.at(-1)?.id ?? parsed.data.cursor,
      items: items.map((item) => ({
        id: item.id,
        clientId: item.clientId,
        envelope: Buffer.from(item.envelope).toString('base64'),
      })),
    };
  });
  app.post('/mailbox/:clientId/ack', { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = z.object({ clientId: z.string().uuid() }).safeParse(request.params);
    if (!parsed.success) return bad(reply, 'Message invalide');
    await mailbox.acknowledge(request.user.deviceId, parsed.data.clientId);
    return reply.code(204).send();
  });
  app.post(
    '/auth/register',
    { config: { rateLimit: { max: 5, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const parsed = credentials
        .merge(
          z.object({
            displayName: z.string().trim().min(1).max(80),
            deviceId: z.string().uuid(),
            deviceName: z.string().max(100).optional(),
          }),
        )
        .safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Données d’inscription invalides');
      const data = parsed.data;
      const client = await db.connect();
      try {
        await client.query('BEGIN');
        const exists = await client.query('SELECT 1 FROM users WHERE email=$1', [data.email]);
        if (exists.rowCount) {
          await client.query('ROLLBACK');
          return reply.code(409).send({ error: 'Adresse déjà utilisée' });
        }
        const userId = randomUUID();
        await client.query(
          'INSERT INTO users (id,email,password_hash,display_name) VALUES ($1,$2,$3,$4)',
          [userId, data.email, await hashPassword(data.password), data.displayName],
        );
        await client.query('INSERT INTO devices (id,user_id,name) VALUES ($1,$2,$3)', [
          data.deviceId,
          userId,
          data.deviceName ?? null,
        ]);
        const token = randomToken();
        await client.query(
          'INSERT INTO email_verification_tokens (token_hash,user_id,expires_at) VALUES ($1,$2,$3)',
          [hashToken(token), userId, new Date(Date.now() + 86400000)],
        );
        await client.query('COMMIT');
        await email.send(
          data.email,
          'Vérifiez votre adresse e-mail',
          `${cfg.PUBLIC_APP_URL}/auth/verify-email?token=${token}`,
        );
        return reply.code(201).send({ id: userId, message: 'Vérifiez votre adresse e-mail' });
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },
  );
  app.post(
    '/auth/verify-email',
    { config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const parsed = tokenBody.safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Jeton invalide');
      const client = await db.connect();
      try {
        await client.query('BEGIN');
        const result = await client.query(
          'UPDATE email_verification_tokens SET used_at=now() WHERE token_hash=$1 AND used_at IS NULL AND expires_at>now() RETURNING user_id',
          [hashToken(parsed.data.token)],
        );
        if (!result.rowCount) {
          await client.query('ROLLBACK');
          return reply.code(400).send({ error: 'Jeton invalide ou expiré' });
        }
        await client.query('UPDATE users SET email_verified_at=now(), updated_at=now() WHERE id=$1', [
          result.rows[0].user_id,
        ]);
        await client.query('COMMIT');
        return { message: 'Adresse e-mail vérifiée' };
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    },
  );
  app.post(
    '/auth/login',
    { config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const parsed = credentials.merge(device).safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Identifiants invalides');
      const d = parsed.data;
      const result = await db.query(
        'SELECT id,password_hash,email_verified_at FROM users WHERE email=$1',
        [d.email],
      );
      const user = result.rows[0];
      const validPassword = await verifyPassword(
        user ? user.password_hash : DUMMY_HASH,
        d.password,
      );
      if (!user || !validPassword)
        return reply.code(401).send({ error: 'Identifiants invalides' });
      if (!user.email_verified_at)
        return reply.code(403).send({ error: 'Adresse e-mail non vérifiée' });
      const userId = user.id;

      // Prevent device hijacking
      const existingDevice = await db.query('SELECT user_id FROM devices WHERE id=$1', [
        d.deviceId,
      ]);
      if (existingDevice.rowCount && existingDevice.rows[0].user_id !== userId) {
        return reply.code(403).send({ error: 'Cet appareil est déjà associé à un autre compte' });
      }

      await db.query(
        'INSERT INTO devices (id,user_id,name) VALUES ($1,$2,$3) ON CONFLICT (id) DO UPDATE SET last_seen_at=now(),name=EXCLUDED.name',
        [d.deviceId, userId, d.deviceName ?? null],
      );
      const raw = randomToken();
      await db.query(
        'INSERT INTO sessions (id,user_id,device_id,refresh_token_hash,expires_at) VALUES ($1,$2,$3,$4,$5)',
        [randomUUID(), userId, d.deviceId, hashToken(raw), refreshExpiry(cfg)],
      );
      return {
        accessToken: await accessToken(app, userId, d.deviceId),
        refreshToken: raw,
        user: { id: userId, email: d.email },
      };
    },
  );
  app.post(
    '/auth/refresh',
    { config: { rateLimit: { max: 30, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const parsed = tokenBody
        .merge(z.object({ deviceId: z.string().uuid() }))
        .safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Jeton invalide');
      const old = parsed.data;
      const tokenH = hashToken(old.token);

      const client = await db.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query(
          'SELECT id,user_id FROM sessions WHERE refresh_token_hash=$1 AND device_id=$2 AND revoked_at IS NULL AND expires_at>now() FOR UPDATE',
          [tokenH, old.deviceId],
        );
        if (!found.rowCount) {
          // Detect refresh token replay / theft
          const alreadyRevoked = await client.query(
            'SELECT id FROM sessions WHERE refresh_token_hash=$1 AND device_id=$2 AND revoked_at IS NOT NULL',
            [tokenH, old.deviceId],
          );
          if (alreadyRevoked.rowCount) {
            await client.query('UPDATE sessions SET revoked_at=now() WHERE device_id=$1', [
              old.deviceId,
            ]);
          }
          await client.query('COMMIT');
          return reply.code(401).send({ error: 'Jeton invalide ou expiré' });
        }
        const raw = randomToken();
        await client.query('UPDATE sessions SET revoked_at=now() WHERE id=$1', [found.rows[0].id]);
        await client.query(
          'INSERT INTO sessions (id,user_id,device_id,refresh_token_hash,expires_at) VALUES ($1,$2,$3,$4,$5)',
          [randomUUID(), found.rows[0].user_id, old.deviceId, hashToken(raw), refreshExpiry(cfg)],
        );
        await client.query('COMMIT');
        return {
          accessToken: await accessToken(app, found.rows[0].user_id, old.deviceId),
          refreshToken: raw,
        };
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    },
  );
  app.post(
    '/auth/logout',
    { config: { rateLimit: { max: 30, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const parsed = tokenBody
        .merge(z.object({ deviceId: z.string().uuid() }))
        .safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Jeton invalide');
      await db.query(
        'UPDATE sessions SET revoked_at=now() WHERE refresh_token_hash=$1 AND device_id=$2',
        [hashToken(parsed.data.token), parsed.data.deviceId],
      );
      return reply.code(204).send();
    },
  );
  app.post(
    '/auth/password-reset/request',
    { config: { rateLimit: { max: 5, timeWindow: '15 minutes' } } },
    async (request) => {
      const parsed = z.object({ email: z.string().email() }).safeParse(request.body);
      if (parsed.success) {
        const found = await db.query('SELECT id FROM users WHERE email=$1', [
          parsed.data.email.toLowerCase(),
        ]);
        if (found.rowCount) {
          const raw = randomToken();
          await db.query(
            'INSERT INTO password_reset_tokens (token_hash,user_id,expires_at) VALUES ($1,$2,$3)',
            [hashToken(raw), found.rows[0].id, new Date(Date.now() + 3600000)],
          );
          await email.send(
            parsed.data.email,
            'Réinitialisation du mot de passe',
            `${cfg.PUBLIC_APP_URL}/auth/password-reset?token=${raw}`,
          );
        }
      }
      return { message: 'Si cette adresse existe, un e-mail a été envoyé' };
    },
  );
  app.post(
    '/auth/password-reset/confirm',
    { config: { rateLimit: { max: 5, timeWindow: '15 minutes' } } },
    async (request, reply) => {
      const parsed = tokenBody
        .merge(z.object({ password: z.string().min(12).max(128) }))
        .safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Données invalides');
      const client = await db.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query(
          'UPDATE password_reset_tokens SET used_at=now() WHERE token_hash=$1 AND used_at IS NULL AND expires_at>now() RETURNING user_id',
          [hashToken(parsed.data.token)],
        );
        if (!found.rowCount) {
          await client.query('ROLLBACK');
          return reply.code(400).send({ error: 'Jeton invalide ou expiré' });
        }
        await client.query('UPDATE users SET password_hash=$1,updated_at=now() WHERE id=$2', [
          await hashPassword(parsed.data.password),
          found.rows[0].user_id,
        ]);
        await client.query('UPDATE sessions SET revoked_at=now() WHERE user_id=$1', [
          found.rows[0].user_id,
        ]);
        await client.query('COMMIT');
        return { message: 'Mot de passe modifié' };
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    },
  );
  app.get('/profile', { preHandler: app.authenticate }, async (request, reply) => {
    const { userId } = await auth(request);
    const result = await db.query(
      'SELECT id,email,display_name AS "displayName",avatar_url AS "avatarUrl",email_verified_at AS "emailVerifiedAt" FROM users WHERE id=$1',
      [userId],
    );
    if (!result.rowCount) return reply.code(404).send({ error: 'Utilisateur introuvable' });
    return result.rows[0];
  });
  app.patch('/profile', { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = profile.safeParse(request.body);
    if (!parsed.success) return bad(reply, 'Profil invalide');
    const { userId } = await auth(request);
    const p = parsed.data;
    const updates: string[] = [];
    const values: (string | null)[] = [];
    let idx = 1;
    if (p.displayName !== undefined) {
      updates.push(`display_name=$${idx++}`);
      values.push(p.displayName);
    }
    if (p.avatarUrl !== undefined) {
      updates.push(`avatar_url=$${idx++}`);
      values.push(p.avatarUrl);
    }
    updates.push('updated_at=now()');
    values.push(userId);
    const result = await db.query(
      `UPDATE users SET ${updates.join(', ')} WHERE id=$${idx} RETURNING id,email,display_name AS "displayName",avatar_url AS "avatarUrl"`,
      values,
    );
    return result.rows[0];
  });
  const mediaBody = z.object({
    conversationId: z.string().uuid(),
    kind: z.enum(['photo', 'video']),
    contentType: z.enum([
      'image/jpeg',
      'image/png',
      'image/webp',
      'video/mp4',
      'video/quicktime',
      'video/webm',
    ]),
    byteSize: z.number().int().positive(),
    width: z.number().int().positive().max(20_000),
    height: z.number().int().positive().max(20_000),
    durationSeconds: z.number().int().nonnegative().nullable().optional(),
    thumbnail: z.boolean().default(false),
  });
  const mediaID = z.object({ mediaId: z.string().uuid() });
  const conversationAccess = async (conversationId: string, userId: string): Promise<boolean> => {
    const result = await db.query(
      'SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',
      [conversationId, userId],
    );
    return result.rowCount !== 0;
  };
  app.post(
    '/media/presign-upload',
    {
      preHandler: app.authenticate,
      config: {
        rateLimit: { max: cfg.MEDIA_UPLOAD_RATE_MAX, timeWindow: '1 minute' },
      },
    },
    async (request, reply) => {
      const parsed = mediaBody.safeParse(request.body);
      if (!parsed.success) return bad(reply, 'Métadonnées média invalides');
      const { userId } = await auth(request);
      const data = parsed.data;
      const groupCheck = await db.query('SELECT 1 FROM conversations WHERE id=$1', [
        data.conversationId,
      ]);
      if (groupCheck.rowCount && !(await conversationAccess(data.conversationId, userId)))
        return reply.code(403).send({ error: 'Accès refusé' });
      const maxBytes =
        data.kind === 'photo' ? cfg.MEDIA_PHOTO_MAX_BYTES : cfg.MEDIA_VIDEO_MAX_BYTES;
      if (data.byteSize > maxBytes)
        return reply
          .code(413)
          .send({ error: `Média trop volumineux (maximum ${maxBytes} octets)` });
      if (data.kind === 'video' && (data.durationSeconds ?? 0) > cfg.MEDIA_VIDEO_MAX_SECONDS)
        return reply.code(413).send({ error: 'Vidéo trop longue' });
      const id = randomUUID();
      const objectKey = `media/${data.conversationId}/${id}/original`;
      const thumbnailObjectKey = data.thumbnail
        ? `media/${data.conversationId}/${id}/thumbnail`
        : null;
      const expiresAt = new Date(Date.now() + cfg.MEDIA_RETENTION_DAYS * 86400000);
      await db.query(
        `INSERT INTO media (id,conversation_id,owner_user_id,object_key,content_type,byte_size,width,height,duration_seconds,thumbnail_object_key,expires_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [
          id,
          data.conversationId,
          userId,
          objectKey,
          data.contentType,
          data.byteSize,
          data.width,
          data.height,
          data.durationSeconds ?? null,
          thumbnailObjectKey,
          expiresAt,
        ],
      );
      const uploadUrl = await mediaStorage.presignUpload(
        objectKey,
        data.contentType,
        cfg.MEDIA_URL_TTL_SECONDS,
      );
      const downloadUrl = await mediaStorage.presignDownload(objectKey, cfg.MEDIA_URL_TTL_SECONDS);
      return reply.code(201).send({
        mediaId: id,
        objectKey,
        thumbnailObjectKey,
        uploadUrl,
        downloadUrl,
        expiresAt: expiresAt.toISOString(),
      });
    },
  );
  app.get('/media/:mediaId/download', { preHandler: app.authenticate }, async (request, reply) => {
    const params = mediaID.safeParse(request.params);
    if (!params.success) return bad(reply, 'Média invalide');
    const { userId } = await auth(request);
    const found = await db.query(
      `SELECT m.object_key FROM media m
       WHERE m.id=$1 AND m.expires_at>now()
       AND (
         m.owner_user_id=$2
         OR EXISTS (
           SELECT 1 FROM conversation_members cm
           WHERE cm.conversation_id=m.conversation_id AND cm.user_id=$2
         )
         OR EXISTS (
           SELECT 1 FROM mailbox mb
           WHERE mb.conversation_id=m.conversation_id AND (mb.recipient_user_id=$2 OR mb.sender_user_id=$2)
         )
       )`,
      [params.data.mediaId, userId],
    );
    if (!found.rowCount) return reply.code(404).send({ error: 'Média introuvable' });
    return {
      downloadUrl: await mediaStorage.presignDownload(
        found.rows[0].object_key,
        cfg.MEDIA_URL_TTL_SECONDS,
      ),
    };
  });

  const groupBody = z.object({
    name: z.string().trim().min(1).max(80),
    photoUrl: z.string().url().max(500).nullable().optional(),
    memberUserIds: z.array(z.string().uuid()).min(1).max(100),
  });
  const groupId = z.object({ conversationId: z.string().uuid() });
  const memberBody = z.object({ userId: z.string().uuid() });
  const groupError = (reply: FastifyReply, error: unknown): FastifyReply | undefined => {
    if (error instanceof GroupPermissionError)
      return reply.code(403).send({ error: error.message });
    return undefined;
  };
  app.post('/groups', { preHandler: app.authenticate }, async (request, reply) => {
    const parsed = groupBody.safeParse(request.body);
    if (!parsed.success) return bad(reply, 'Groupe invalide');
    const { userId } = await auth(request);
    const id = randomUUID();
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        'INSERT INTO conversations (id,name,photo_url,created_by) VALUES ($1,$2,$3,$4)',
        [id, parsed.data.name, parsed.data.photoUrl ?? null, userId],
      );
      const members = [...new Set([userId, ...parsed.data.memberUserIds])];
      await client.query(
        `INSERT INTO conversation_members (conversation_id,user_id,role)
         SELECT $1, id, CASE WHEN id=$2 THEN 'admin' ELSE 'member' END
         FROM users WHERE id = ANY($3::uuid[])`,
        [id, userId, members],
      );
      await client.query('COMMIT');
      await broadcastSystemEvent(db, groupMailbox, groupRouter, id, userId, 'Le groupe a été créé');
      return reply
        .code(201)
        .send({ id, name: parsed.data.name, photoUrl: parsed.data.photoUrl ?? null });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  });
  app.get('/groups/:conversationId', { preHandler: app.authenticate }, async (request, reply) => {
    const params = groupId.safeParse(request.params);
    if (!params.success) return bad(reply, 'Groupe invalide');
    const { userId } = await auth(request);
    if (!(await groupRole(db, params.data.conversationId, userId)))
      return reply.code(403).send({ error: 'Accès refusé' });
    const result = await db.query(
      `SELECT c.id,c.name,c.photo_url AS "photoUrl",
              json_agg(json_build_object('userId',m.user_id,'role',m.role)) AS members
       FROM conversations c JOIN conversation_members m ON m.conversation_id=c.id
       WHERE c.id=$1 GROUP BY c.id`,
      [params.data.conversationId],
    );
    if (!result.rowCount) return reply.code(404).send({ error: 'Groupe introuvable' });
    return result.rows[0];
  });
  app.patch('/groups/:conversationId', { preHandler: app.authenticate }, async (request, reply) => {
    const params = groupId.safeParse(request.params);
    const parsed = z
      .object({
        name: z.string().trim().min(1).max(80),
        photoUrl: z.string().url().max(500).nullable().optional(),
      })
      .safeParse(request.body);
    if (!params.success || !parsed.success) return bad(reply, 'Groupe invalide');
    const { userId } = await auth(request);
    try {
      requireAdmin(await groupRole(db, params.data.conversationId, userId));
    } catch (error) {
      return groupError(reply, error);
    }
    const result = await db.query(
      'UPDATE conversations SET name=$1,photo_url=$2,updated_at=now() WHERE id=$3 RETURNING id,name,photo_url AS "photoUrl"',
      [parsed.data.name, parsed.data.photoUrl ?? null, params.data.conversationId],
    );
    await broadcastSystemEvent(
      db,
      groupMailbox,
      groupRouter,
      params.data.conversationId,
      userId,
      `Le nom du groupe est maintenant « ${parsed.data.name} »`,
    );
    return result.rowCount ? result.rows[0] : reply.code(404).send({ error: 'Groupe introuvable' });
  });
  app.post(
    '/groups/:conversationId/members',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const params = groupId.safeParse(request.params);
      const parsed = memberBody.safeParse(request.body);
      if (!params.success || !parsed.success) return bad(reply, 'Membre invalide');
      const { userId } = await auth(request);
      try {
        requireAdmin(await groupRole(db, params.data.conversationId, userId));
      } catch (error) {
        return groupError(reply, error);
      }
      const existing = await groupRole(db, params.data.conversationId, parsed.data.userId);
      if (existing) return reply.code(409).send({ error: 'Ce membre fait déjà partie du groupe' });

      const userExists = await db.query('SELECT 1 FROM users WHERE id=$1', [parsed.data.userId]);
      if (!userExists.rowCount) return reply.code(404).send({ error: 'Utilisateur introuvable' });

      await db.query(
        "INSERT INTO conversation_members (conversation_id,user_id,role) VALUES ($1,$2,'member') ON CONFLICT DO NOTHING",
        [params.data.conversationId, parsed.data.userId],
      );
      await broadcastSystemEvent(
        db,
        groupMailbox,
        groupRouter,
        params.data.conversationId,
        userId,
        'Un membre a été ajouté',
      );
      return reply.code(204).send();
    },
  );
  app.delete(
    '/groups/:conversationId/members/:userId',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const params = z
        .object({ conversationId: z.string().uuid(), userId: z.string().uuid() })
        .safeParse(request.params);
      if (!params.success) return bad(reply, 'Membre invalide');
      const { userId } = await auth(request);
      try {
        requireAdmin(await groupRole(db, params.data.conversationId, userId));
      } catch (error) {
        return groupError(reply, error);
      }
      const targetRole = await groupRole(db, params.data.conversationId, params.data.userId);
      if (!targetRole) return reply.code(404).send({ error: 'Membre introuvable' });
      if (targetRole === 'admin')
        return reply.code(403).send({ error: 'Impossible de retirer un administrateur' });

      await db.query(
        'DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2 AND role<>$3',
        [params.data.conversationId, params.data.userId, 'admin'],
      );
      await groupMailbox.purgeConversation(params.data.userId, params.data.conversationId);
      await broadcastSystemEvent(
        db,
        groupMailbox,
        groupRouter,
        params.data.conversationId,
        userId,
        'Un membre a été retiré',
      );
      return reply.code(204).send();
    },
  );
  app.post(
    '/groups/:conversationId/leave',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const params = groupId.safeParse(request.params);
      if (!params.success) return bad(reply, 'Groupe invalide');
      const { userId } = await auth(request);
      const role = await groupRole(db, params.data.conversationId, userId);
      if (!role) return reply.code(403).send({ error: 'Vous ne faites pas partie de ce groupe' });

      const client = await db.connect();
      try {
        await client.query('BEGIN');
        await client.query('DELETE FROM conversation_members WHERE conversation_id=$1 AND user_id=$2', [
          params.data.conversationId,
          userId,
        ]);
        await groupMailbox.purgeConversation(userId, params.data.conversationId);

        const remaining = await client.query<{ id: string; role: string }>(
          'SELECT user_id AS id, role FROM conversation_members WHERE conversation_id=$1 ORDER BY joined_at ASC',
          [params.data.conversationId],
        );
        if (remaining.rowCount === 0) {
          await client.query('DELETE FROM conversations WHERE id=$1', [params.data.conversationId]);
        } else if (role === 'admin' && !remaining.rows.some((r) => r.role === 'admin')) {
          await client.query(
            "UPDATE conversation_members SET role='admin' WHERE conversation_id=$1 AND user_id=$2",
            [params.data.conversationId, remaining.rows[0].id],
          );
        }
        await client.query('COMMIT');

        await broadcastSystemEvent(
          db,
          groupMailbox,
          groupRouter,
          params.data.conversationId,
          userId,
          'Un membre a quitté le groupe',
        );
        return reply.code(204).send();
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    },
  );
  app.post(
    '/groups/:conversationId/admins',
    { preHandler: app.authenticate },
    async (request, reply) => {
      const params = groupId.safeParse(request.params);
      const parsed = memberBody.safeParse(request.body);
      if (!params.success || !parsed.success) return bad(reply, 'Membre invalide');
      const { userId } = await auth(request);
      try {
        requireAdmin(await groupRole(db, params.data.conversationId, userId));
      } catch (error) {
        return groupError(reply, error);
      }
      const targetRole = await groupRole(db, params.data.conversationId, parsed.data.userId);
      if (!targetRole) return reply.code(404).send({ error: 'Membre introuvable dans le groupe' });
      if (targetRole === 'admin') return reply.code(204).send();

      await db.query(
        "UPDATE conversation_members SET role='admin' WHERE conversation_id=$1 AND user_id=$2",
        [params.data.conversationId, parsed.data.userId],
      );
      await broadcastSystemEvent(
        db,
        groupMailbox,
        groupRouter,
        params.data.conversationId,
        userId,
        'Un membre est devenu administrateur',
      );
      return reply.code(204).send();
    },
  );
  return app;
}
