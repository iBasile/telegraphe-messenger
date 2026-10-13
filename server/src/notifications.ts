import { Redis } from 'ioredis';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import type { Config } from './config.js';

export interface NotificationJob {
  deviceId: string;
  clientId: string;
}

export interface NotificationQueue {
  enqueue(job: NotificationJob): Promise<void>;
}

export class RedisNotificationQueue implements NotificationQueue {
  public constructor(private readonly redis: Redis) {}

  public async enqueue(job: NotificationJob): Promise<void> {
    await this.redis.rpush('telegraphe:notifications', JSON.stringify(job));
  }
}

export interface PushSender {
  send(token: string, job: NotificationJob): Promise<void>;
}

export class FcmPushSender implements PushSender {
  public constructor(cfg: Config) {
    if (!cfg.FCM_PROJECT_ID || !cfg.FCM_CLIENT_EMAIL || !cfg.FCM_PRIVATE_KEY) {
      throw new Error(
        'FCM_PROJECT_ID, FCM_CLIENT_EMAIL et FCM_PRIVATE_KEY sont requis pour le worker',
      );
    }
    if (!getApps().length) {
      initializeApp({
        credential: cert({
          projectId: cfg.FCM_PROJECT_ID,
          clientEmail: cfg.FCM_CLIENT_EMAIL,
          privateKey: cfg.FCM_PRIVATE_KEY.replace(/\\n/g, '\n'),
        }),
      });
    }
  }

  public async send(token: string, job: NotificationJob): Promise<void> {
    await getMessaging().send({
      token,
      data: { type: 'wake', client_id: job.clientId },
      android: { priority: 'high' },
    });
  }
}
