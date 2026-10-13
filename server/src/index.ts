import { config } from './config.js';
import { buildApp } from './app.js';
import { Redis } from 'ioredis';
import { RedisMessageRouter } from './router.js';
import { RedisPresenceStore } from './presence.js';
import { PostgresMailboxStore } from './mailbox.js';
import { pool } from './db.js';
import { RedisNotificationQueue } from './notifications.js';
import { Metrics } from './metrics.js';
const redis = new Redis(config.REDIS_URL);
const router = new RedisMessageRouter(redis);
const appWithMessaging = await buildApp({
  mailbox: new PostgresMailboxStore(pool),
  router,
  presence: new RedisPresenceStore(redis),
  notificationQueue: new RedisNotificationQueue(redis),
  metrics: new Metrics(),
});
await appWithMessaging.listen({ port: config.PORT, host: '0.0.0.0' });
