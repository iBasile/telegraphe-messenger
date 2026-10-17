import 'dotenv/config';
import { z } from 'zod';

const optionalEnvironmentString = z.preprocess(
  (value) => (value === '' ? undefined : value),
  z.string().optional(),
);

const optionalEnvironmentEmail = z.preprocess(
  (value) => (value === '' ? undefined : value),
  z.string().email().optional(),
);

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().url().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(32),
  JWT_ISSUER: z.string().default('telegraphe'),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  EMAIL_MODE: z.enum(['console', 'smtp']).default('console'),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.coerce.number().default(587),
  SMTP_USER: z.string().optional(),
  SMTP_PASSWORD: z.string().optional(),
  EMAIL_FROM: z.string().email().default('no-reply@example.com'),
  PUBLIC_APP_URL: z.string().url().default('http://localhost:3000'),
  PROTOCOL_VERSION: z.coerce.number().int().positive().default(1),
  MINIO_ENDPOINT: z.string().url().default('http://localhost:9000'),
  MINIO_REGION: z.string().default('us-east-1'),
  MINIO_ACCESS_KEY: z.string().min(1).default('minioadmin'),
  MINIO_SECRET_KEY: z.string().min(1).default('minioadmin'),
  MINIO_BUCKET: z.string().min(1).default('telegraphe-media'),
  MEDIA_URL_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  MEDIA_RETENTION_DAYS: z.coerce.number().int().positive().default(30),
  MEDIA_PHOTO_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(10 * 1024 * 1024),
  MEDIA_VIDEO_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(50 * 1024 * 1024),
  MEDIA_VIDEO_MAX_SECONDS: z.coerce.number().int().positive().default(60),
  MEDIA_UPLOAD_RATE_MAX: z.coerce.number().int().positive().default(20),
  MESSAGE_RATE_MAX: z.coerce.number().int().positive().default(60),
  FCM_PROJECT_ID: optionalEnvironmentString,
  FCM_CLIENT_EMAIL: optionalEnvironmentEmail,
  FCM_PRIVATE_KEY: optionalEnvironmentString,
});
export type Config = z.infer<typeof schema>;
const environment = { ...process.env };
if (environment.NODE_ENV === 'test') {
  environment.DATABASE_URL ??= 'postgres://test:test@localhost:5432/test';
  environment.JWT_SECRET ??= 'test-only-secret-that-is-at-least-32-chars';
} else if (environment.NODE_ENV === 'production') {
  if (
    environment.JWT_SECRET === 'test-only-secret-that-is-at-least-32-chars' ||
    environment.JWT_SECRET === 'replace-with-a-strong-secret-key-at-least-32-chars'
  ) {
    throw new Error('JWT_SECRET ne peut pas être un secret par défaut en production');
  }
}
export const config = schema.parse(environment);
