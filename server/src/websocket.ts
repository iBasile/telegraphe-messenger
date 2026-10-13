import type { FastifyInstance } from 'fastify';
import type { Pool } from 'pg';
import type { WebSocket } from '@fastify/websocket';
import type { RawData } from 'ws';
import { z } from 'zod';
import {
  EnvelopeCodec,
  EnvelopeType,
  ErrorCodec,
  HandshakeAckCodec,
  HandshakeCodec,
  PresenceCodec,
  ReceiptCodec,
  ServerAckCodec,
  TextMessageCodec,
  TypingCodec,
  type Envelope,
} from './generated/telegraphe.js';
import type { MailboxStore } from './mailbox.js';
import type { MessageRouter } from './router.js';
import type { MemoryPresenceStore, RedisPresenceStore } from './presence.js';
import { groupMemberDevices, groupRole } from './groups.js';
import { Metrics } from './metrics.js';
import type { NotificationQueue } from './notifications.js';

export const PROTOCOL_VERSION = 1;
const textMessage = z.object({
  recipientUserId: z.string().uuid(),
  recipientDeviceId: z.string().uuid(),
  text: z.string().trim().min(1).max(4000),
});

type PresenceStore = RedisPresenceStore | MemoryPresenceStore;

export interface WebSocketOptions {
  db: Pool;
  mailbox: MailboxStore;
  router: MessageRouter;
  presence: PresenceStore;
  protocolVersion?: number;
  notificationQueue?: NotificationQueue;
  metrics?: Metrics;
  messageRateMax?: number;
}

const bytes = (value: Uint8Array): Buffer => Buffer.from(value);
const envelope = (value: Envelope): Uint8Array => EnvelopeCodec.encode(value).finish();

const errorEnvelope = (code: string, message: string): Uint8Array =>
  envelope({
    type: EnvelopeType.ERROR,
    timestampMs: Date.now(),
    encryptionVersion: 0,
    payload: ErrorCodec.encode({ code, message }).finish(),
  });

export async function registerWebSocket(
  app: FastifyInstance,
  options: WebSocketOptions,
): Promise<void> {
  await app.register(import('@fastify/websocket'));
  app.get('/ws', { websocket: true }, (socket: WebSocket, request) => {
    void handleConnection(app, socket, request.headers.authorization, options);
  });
}

async function handleConnection(
  app: FastifyInstance,
  socket: WebSocket,
  authorization: string | undefined,
  options: WebSocketOptions,
): Promise<void> {
  const token = authorization?.startsWith('Bearer ') ? authorization.slice(7) : undefined;
  if (!token) {
    socket.close(4001, 'Authentification requise');
    return;
  }

  let auth: { sub: string; deviceId: string };
  try {
    auth = app.jwt.verify<{ sub: string; deviceId: string }>(token);
  } catch {
    socket.close(4001, 'Jeton invalide');
    return;
  }

  const protocolVersion = options.protocolVersion ?? PROTOCOL_VERSION;
  let handshaken = false;
  let closed = false;
  let messageWindowStarted = Date.now();
  let messageCount = 0;
  const send = (message: Uint8Array): void => {
    if (socket.readyState === socket.OPEN) socket.send(bytes(message));
  };

  const disconnect = async (): Promise<void> => {
    if (closed) return;
    closed = true;
    await options.router.unregister(auth.deviceId);
    await options.presence.setOffline(auth.deviceId);
    if (options.metrics) options.metrics.activeConnections -= 1;
  };

  await options.router.register(auth.deviceId, send);
  if (options.metrics) options.metrics.activeConnections += 1;
  await options.presence.setOnline(auth.deviceId);
  const handshakeTimeout = setTimeout(() => {
    if (!handshaken) socket.close(4002, 'Poignée de main requise');
  }, 5000);

  socket.on('close', () => {
    clearTimeout(handshakeTimeout);
    void disconnect();
  });
  socket.on('error', () => {
    void disconnect();
  });
  socket.on('message', (raw: RawData) => {
    void processMessage(new Uint8Array(raw as Buffer));
  });

  async function processMessage(raw: Uint8Array): Promise<void> {
    if (Date.now() - messageWindowStarted >= 60_000) {
      messageWindowStarted = Date.now();
      messageCount = 0;
    }
    messageCount += 1;
    if (messageCount > (options.messageRateMax ?? 60)) {
      send(errorEnvelope('RATE_LIMITED', 'Trop de messages envoyés'));
      return;
    }
    let incoming: Envelope;
    try {
      incoming = EnvelopeCodec.decode(raw);
    } catch {
      send(errorEnvelope('INVALID_PROTOBUF', 'Message binaire invalide'));
      return;
    }

    if (!handshaken) {
      if (incoming.type !== EnvelopeType.HANDSHAKE) {
        socket.close(4002, 'Poignée de main requise');
        return;
      }
      const hello = HandshakeCodec.decode(incoming.payload ?? new Uint8Array());
      if (hello.protocolVersion !== protocolVersion || hello.deviceId !== auth.deviceId) {
        send(errorEnvelope('UNSUPPORTED_PROTOCOL', 'Version de protocole incompatible'));
        socket.close(4003, 'Version de protocole incompatible');
        return;
      }
      handshaken = true;
      clearTimeout(handshakeTimeout);
      send(
        envelope({
          type: EnvelopeType.HANDSHAKE_ACK,
          timestampMs: Date.now(),
          senderDeviceId: auth.deviceId,
          encryptionVersion: 0,
          payload: HandshakeAckCodec.encode({ protocolVersion }).finish(),
        }),
      );
      for (const item of await options.mailbox.pending(auth.deviceId)) send(item.envelope);
      return;
    }

    if (incoming.encryptionVersion !== 0 || incoming.senderDeviceId !== auth.deviceId) {
      send(errorEnvelope('INVALID_ENVELOPE', 'Enveloppe non valide'));
      return;
    }

    if (incoming.type === EnvelopeType.SEND_TEXT) {
      await handleText(incoming);
    } else if (incoming.type === EnvelopeType.DELIVERED || incoming.type === EnvelopeType.READ) {
      await handleReceipt(incoming);
    } else if (incoming.type === EnvelopeType.TYPING) {
      const typing = TypingCodec.decode(incoming.payload ?? new Uint8Array());
      await options.presence.setTyping(
        incoming.conversationId ?? '',
        auth.deviceId,
        !!typing.isTyping,
      );
      if (typing.targetDeviceId)
        await options.router.route(typing.targetDeviceId, envelope(incoming));
    } else if (incoming.type === EnvelopeType.PRESENCE) {
      const presence = PresenceCodec.decode(incoming.payload ?? new Uint8Array());
      if (presence.targetDeviceId)
        await options.router.route(presence.targetDeviceId, envelope(incoming));
    } else {
      send(errorEnvelope('UNSUPPORTED_TYPE', 'Type de message non pris en charge'));
    }
  }

  async function handleText(incoming: Envelope): Promise<void> {
    const parsed = textMessage.safeParse(
      TextMessageCodec.decode(incoming.payload ?? new Uint8Array()),
    );
    if (!parsed.success || !incoming.clientId || !incoming.conversationId) {
      send(errorEnvelope('INVALID_TEXT', 'Message texte invalide'));
      return;
    }
    const isGroup = Boolean(await groupRole(options.db, incoming.conversationId, auth.sub));
    if (isGroup) {
      const members = await groupMemberDevices(options.db, incoming.conversationId, auth.sub);
      for (const member of members) {
        const stored = await options.mailbox.store({
          recipientUserId: member.userId,
          recipientDeviceId: member.deviceId,
          senderUserId: auth.sub,
          conversationId: incoming.conversationId,
          clientId: incoming.clientId,
          envelope: envelope(incoming),
        });
        if (!stored.duplicate) {
          const live = await options.router.route(member.deviceId, envelope(incoming));
          if (!live)
            await options.notificationQueue?.enqueue({
              deviceId: member.deviceId,
              clientId: incoming.clientId,
            });
          options.metrics &&
            ((options.metrics.deliveryLatencySeconds +=
              Math.max(0, Date.now() - Number(incoming.timestampMs ?? Date.now())) / 1000),
            (options.metrics.deliveredMessages += 1));
        }
      }
      send(
        envelope({
          type: EnvelopeType.SERVER_ACK,
          clientId: incoming.clientId,
          timestampMs: Date.now(),
          conversationId: incoming.conversationId,
          senderDeviceId: auth.deviceId,
          encryptionVersion: 0,
          payload: ServerAckCodec.encode({
            messageClientId: incoming.clientId,
            accepted: true,
            duplicate: false,
          }).finish(),
        }),
      );
      return;
    }
    const recipient = await options.db.query<{ user_id: string }>(
      'SELECT user_id FROM devices WHERE id=$1',
      [parsed.data.recipientDeviceId],
    );
    if (!recipient.rowCount || recipient.rows[0].user_id !== parsed.data.recipientUserId) {
      send(errorEnvelope('RECIPIENT_NOT_FOUND', 'Destinataire introuvable'));
      return;
    }
    const stored = await options.mailbox.store({
      recipientUserId: parsed.data.recipientUserId,
      recipientDeviceId: parsed.data.recipientDeviceId,
      senderUserId: auth.sub,
      conversationId: incoming.conversationId,
      clientId: incoming.clientId,
      envelope: envelope(incoming),
    });
    if (!stored.duplicate) {
      const live = await options.router.route(parsed.data.recipientDeviceId, envelope(incoming));
      if (!live)
        await options.notificationQueue?.enqueue({
          deviceId: parsed.data.recipientDeviceId,
          clientId: incoming.clientId,
        });
      options.metrics &&
        ((options.metrics.deliveryLatencySeconds +=
          Math.max(0, Date.now() - Number(incoming.timestampMs ?? Date.now())) / 1000),
        (options.metrics.deliveredMessages += 1));
    }
    send(
      envelope({
        type: EnvelopeType.SERVER_ACK,
        clientId: incoming.clientId,
        timestampMs: Date.now(),
        conversationId: incoming.conversationId,
        senderDeviceId: auth.deviceId,
        encryptionVersion: 0,
        payload: ServerAckCodec.encode({
          messageClientId: incoming.clientId,
          accepted: true,
          duplicate: stored.duplicate,
          mailboxId: stored.id,
        }).finish(),
      }),
    );
  }

  async function handleReceipt(incoming: Envelope): Promise<void> {
    const receipt = ReceiptCodec.decode(incoming.payload ?? new Uint8Array());
    if (!receipt.messageClientId) return;
    const item =
      incoming.type === EnvelopeType.DELIVERED
        ? await options.mailbox.acknowledge(auth.deviceId, receipt.messageClientId)
        : undefined;
    const targetDeviceId =
      receipt.targetDeviceId ?? (item ? EnvelopeCodec.decode(item.envelope).senderDeviceId : '');
    if (!targetDeviceId) return;
    await options.router.route(
      targetDeviceId,
      envelope({
        ...incoming,
        timestampMs: Date.now(),
        clientId: receipt.messageClientId,
      }),
    );
  }
}
