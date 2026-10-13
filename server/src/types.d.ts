import type { Config } from './config.js';
declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}
declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: { sub: string; deviceId: string };
    user: { sub: string; deviceId: string };
  }
}
