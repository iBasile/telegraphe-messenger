import { Redis } from 'ioredis';

export type BinaryMessage = Uint8Array;
export type LocalDelivery = (message: BinaryMessage) => void;

export interface MessageRouter {
  register(deviceId: string, delivery: LocalDelivery): Promise<void>;
  unregister(deviceId: string): Promise<void>;
  route(deviceId: string, message: BinaryMessage): Promise<boolean>;
  close(): Promise<void>;
}

export class RedisMessageRouter implements MessageRouter {
  private readonly subscriber: Redis;
  private readonly deliveries = new Map<string, LocalDelivery>();

  public constructor(private readonly publisher: Redis) {
    this.subscriber = publisher.duplicate();
    this.subscriber.on('messageBuffer', (channel: Buffer, message: Buffer) => {
      const deviceId = channel.toString().replace('telegraphe:device:', '');
      this.deliveries.get(deviceId)?.(new Uint8Array(message));
    });
  }

  public async register(deviceId: string, delivery: LocalDelivery): Promise<void> {
    this.deliveries.set(deviceId, delivery);
    await this.subscriber.subscribe(`telegraphe:device:${deviceId}`);
  }

  public async unregister(deviceId: string): Promise<void> {
    this.deliveries.delete(deviceId);
    await this.subscriber.unsubscribe(`telegraphe:device:${deviceId}`);
  }

  public async route(deviceId: string, message: BinaryMessage): Promise<boolean> {
    const subscribers = await this.publisher.publish(
      `telegraphe:device:${deviceId}`,
      Buffer.from(message),
    );
    return subscribers > 0;
  }

  public async close(): Promise<void> {
    await Promise.all([this.publisher.quit(), this.subscriber.quit()]);
  }
}

export class MemoryMessageRouter implements MessageRouter {
  private readonly deliveries = new Map<string, LocalDelivery>();

  public async register(deviceId: string, delivery: LocalDelivery): Promise<void> {
    this.deliveries.set(deviceId, delivery);
  }
  public async unregister(deviceId: string): Promise<void> {
    this.deliveries.delete(deviceId);
  }
  public async route(deviceId: string, message: BinaryMessage): Promise<boolean> {
    const delivery = this.deliveries.get(deviceId);
    if (!delivery) return false;
    delivery(message);
    return true;
  }
  public async close(): Promise<void> {}
}
