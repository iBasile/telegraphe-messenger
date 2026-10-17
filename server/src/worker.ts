import { Redis } from 'ioredis';
import { pool } from './db.js';
import { config } from './config.js';
import { FcmPushSender, type NotificationJob } from './notifications.js';

const redis = new Redis(config.REDIS_URL);
const sender = new FcmPushSender(config);

for (;;) {
  try {
    const result = await redis.blpop('telegraphe:notifications', 0);
    if (!result) continue;
    let job: NotificationJob;
    try {
      job = JSON.parse(result[1]) as NotificationJob;
      if (!job || typeof job.deviceId !== 'string' || typeof job.clientId !== 'string') {
        continue;
      }
    } catch {
      continue;
    }
    const tokens = await pool.query<{ token: string }>(
      'SELECT token FROM push_tokens WHERE device_id=$1 AND platform=$2',
      [job.deviceId, 'android'],
    );
    for (const row of tokens.rows) {
      try {
        await sender.send(row.token, job);
      } catch (error) {
        console.error(
          JSON.stringify({ event: 'push_delivery_failed', deviceId: job.deviceId, error }),
        );
      }
    }
  } catch (error) {
    console.error(JSON.stringify({ event: 'push_worker_loop_error', error }));
  }
}
