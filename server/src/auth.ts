import argon2 from 'argon2';
import crypto from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Config } from './config.js';
export const hashPassword = (password: string): Promise<string> =>
  argon2.hash(password, { type: argon2.argon2id });
export const verifyPassword = (hash: string, password: string): Promise<boolean> =>
  argon2.verify(hash, password);
export const randomToken = (): string => crypto.randomBytes(32).toString('base64url');
export const hashToken = (token: string): string =>
  crypto.createHash('sha256').update(token).digest('hex');
export const accessToken = async (
  app: FastifyInstance,
  userId: string,
  deviceId: string,
): Promise<string> =>
  app.jwt.sign({ sub: userId, deviceId }, { expiresIn: app.config.ACCESS_TOKEN_TTL });
export const refreshExpiry = (cfg: Config): Date =>
  new Date(Date.now() + cfg.REFRESH_TOKEN_TTL_DAYS * 86400000);
