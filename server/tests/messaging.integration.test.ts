import pg from 'pg';
import WebSocket from 'ws';
import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config.js';
import { MemoryMailboxStore } from '../src/mailbox.js';
import { MemoryMessageRouter } from '../src/router.js';
import { MemoryPresenceStore } from '../src/presence.js';
import {
  EnvelopeCodec,
  EnvelopeType,
  HandshakeCodec,
  ReceiptCodec,
  ServerAckCodec,
  TextMessageCodec,
  type Envelope,
} from '../src/generated/telegraphe.js';

const enabled = Boolean(process.env.DATABASE_URL);
const waitFor = <T>(promise: Promise<T>, timeout = 5000): Promise<T> =>
  Promise.race([
    promise,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error('timeout')), timeout)),
  ]);

describe.skipIf(!enabled)('WebSocket messaging integration', () => {
  it('delivers live and mailbox messages without duplicates and propagates receipts', async () => {
    const db = new pg.Pool({ connectionString: process.env.DATABASE_URL });
    const senderUser = randomUUID();
    const recipientUser = randomUUID();
    const senderDevice = randomUUID();
    const recipientDevice = randomUUID();
    await db.query(
      `INSERT INTO users (id,email,password_hash,display_name,email_verified_at)
       VALUES ($1,$2,'test','Sender',now()),($3,$4,'test','Recipient',now())`,
      [senderUser, `${senderUser}@example.com`, recipientUser, `${recipientUser}@example.com`],
    );
    await db.query(`INSERT INTO devices (id,user_id) VALUES ($1,$2),($3,$4)`, [
      senderDevice,
      senderUser,
      recipientDevice,
      recipientUser,
    ]);

    const app = await buildApp({
      db,
      cfg: { ...config, DATABASE_URL: process.env.DATABASE_URL! },
      mailbox: new MemoryMailboxStore(),
      router: new MemoryMessageRouter(),
      presence: new MemoryPresenceStore(),
    });
    const senderToken = app.jwt.sign({ sub: senderUser, deviceId: senderDevice });
    const recipientToken = app.jwt.sign({ sub: recipientUser, deviceId: recipientDevice });
    const address = await app.listen({ port: 0, host: '127.0.0.1' });
    const wsUrl = address.replace('http', 'ws') + '/ws';
    const sender = new WebSocket(wsUrl, { headers: { authorization: `Bearer ${senderToken}` } });
    const recipient = new WebSocket(wsUrl, {
      headers: { authorization: `Bearer ${recipientToken}` },
    });
    await Promise.all([waitForOpen(sender), waitForOpen(recipient)]);
    sendHandshake(sender, senderDevice);
    sendHandshake(recipient, recipientDevice);
    await Promise.all([
      waitForType(sender, EnvelopeType.HANDSHAKE_ACK),
      waitForType(recipient, EnvelopeType.HANDSHAKE_ACK),
    ]);

    const conversationId = randomUUID();
    const live = makeText(senderDevice, conversationId, 'live', recipientUser, recipientDevice);
    const recipientMessages: Envelope[] = [];
    recipient.on('message', (data) => {
      const message = EnvelopeCodec.decode(new Uint8Array(data as Buffer));
      if (message.type === EnvelopeType.SEND_TEXT) recipientMessages.push(message);
    });
    sender.send(Buffer.from(EnvelopeCodec.encode(live).finish()));
    const liveReceived = waitForType(recipient, EnvelopeType.SEND_TEXT);
    await waitForType(sender, EnvelopeType.SERVER_ACK);
    await liveReceived;
    const delivered = receipt(
      conversationId,
      live.clientId!,
      EnvelopeType.DELIVERED,
      recipientDevice,
      senderDevice,
    );
    recipient.send(Buffer.from(EnvelopeCodec.encode(delivered).finish()));
    const read = receipt(
      conversationId,
      live.clientId!,
      EnvelopeType.READ,
      recipientDevice,
      senderDevice,
    );
    recipient.send(Buffer.from(EnvelopeCodec.encode(read).finish()));
    await waitForType(sender, EnvelopeType.DELIVERED);
    await waitForType(sender, EnvelopeType.READ);

    recipient.close();
    await waitForClose(recipient);
    const offline = makeText(
      senderDevice,
      conversationId,
      'offline',
      recipientUser,
      recipientDevice,
    );
    sender.send(Buffer.from(EnvelopeCodec.encode(offline).finish()));
    const ack = await waitForType(sender, EnvelopeType.SERVER_ACK);
    expect(ServerAckCodec.decode(ack.payload!)).toMatchObject({ accepted: true, duplicate: false });

    const recipientAgain = new WebSocket(wsUrl, {
      headers: { authorization: `Bearer ${recipientToken}` },
    });
    await waitForOpen(recipientAgain);
    sendHandshake(recipientAgain, recipientDevice);
    const recovered = await waitForType(recipientAgain, EnvelopeType.SEND_TEXT);
    expect(recovered.clientId).toBe(offline.clientId);
    let duplicateDeliveries = 0;
    recipientAgain.on('message', (data) => {
      if (EnvelopeCodec.decode(new Uint8Array(data as Buffer)).type === EnvelopeType.SEND_TEXT) {
        duplicateDeliveries += 1;
      }
    });
    sender.send(Buffer.from(EnvelopeCodec.encode(offline).finish()));
    expect(
      ServerAckCodec.decode((await waitForType(sender, EnvelopeType.SERVER_ACK)).payload!),
    ).toMatchObject({
      duplicate: true,
    });
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(duplicateDeliveries).toBe(0);

    recipientAgain.close();
    sender.close();
    await Promise.all([waitForClose(sender), waitForClose(recipientAgain)]);
    await app.close();
    await db.query('DELETE FROM users WHERE id IN ($1,$2)', [senderUser, recipientUser]);
    await db.end();
  });
});

function waitForOpen(socket: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.once('open', () => resolve());
    socket.once('error', reject);
  });
}

function waitForClose(socket: WebSocket): Promise<void> {
  return new Promise((resolve) => socket.once('close', () => resolve()));
}

function waitForType(socket: WebSocket, type: EnvelopeType): Promise<Envelope> {
  return new Promise((resolve) => {
    const listener = (data: WebSocket.RawData): void => {
      const message = EnvelopeCodec.decode(new Uint8Array(data as Buffer));
      if (message.type === type) {
        socket.off('message', listener);
        resolve(message);
      }
    };
    socket.on('message', listener);
  });
}

function sendHandshake(socket: WebSocket, deviceId: string): void {
  socket.send(
    Buffer.from(
      EnvelopeCodec.encode({
        type: EnvelopeType.HANDSHAKE,
        timestampMs: Date.now(),
        encryptionVersion: 0,
        payload: HandshakeCodec.encode({ protocolVersion: 1, deviceId }).finish(),
      }).finish(),
    ),
  );
}

function makeText(
  senderDeviceId: string,
  conversationId: string,
  clientId: string,
  recipientUserId: string,
  recipientDeviceId: string,
): Envelope {
  return {
    type: EnvelopeType.SEND_TEXT,
    clientId,
    timestampMs: Date.now(),
    conversationId,
    senderDeviceId,
    encryptionVersion: 0,
    payload: TextMessageCodec.encode({
      recipientUserId,
      recipientDeviceId,
      text: clientId,
    }).finish(),
  };
}

function receipt(
  conversationId: string,
  clientId: string,
  type: EnvelopeType,
  recipientDeviceId: string,
  targetDeviceId: string,
): Envelope {
  return {
    type,
    clientId,
    timestampMs: Date.now(),
    conversationId,
    senderDeviceId: recipientDeviceId,
    encryptionVersion: 0,
    payload: ReceiptCodec.encode({ messageClientId: clientId, targetDeviceId }).finish(),
  };
}
