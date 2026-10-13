import { Redis } from 'ioredis';

export class RedisPresenceStore {
  public constructor(
    private readonly redis: Redis,
    private readonly ttlSeconds = 45,
  ) {}

  public async setOnline(deviceId: string): Promise<void> {
    await this.redis.set(`telegraphe:presence:${deviceId}`, '1', 'EX', this.ttlSeconds);
  }
  public async setOffline(deviceId: string): Promise<void> {
    await this.redis.del(`telegraphe:presence:${deviceId}`);
  }
  public async setTyping(conversationId: string, deviceId: string, typing: boolean): Promise<void> {
    const key = `telegraphe:typing:${conversationId}:${deviceId}`;
    if (typing) await this.redis.set(key, '1', 'EX', 8);
    else await this.redis.del(key);
  }
}

export class MemoryPresenceStore {
  public async setOnline(_deviceId: string): Promise<void> {}
  public async setOffline(_deviceId: string): Promise<void> {}
  public async setTyping(
    _conversationId: string,
    _deviceId: string,
    _typing: boolean,
  ): Promise<void> {}
}
