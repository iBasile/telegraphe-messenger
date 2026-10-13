import type pg from 'pg';
import crypto from 'node:crypto';
import { EnvelopeCodec, TextMessageCodec, type Envelope } from './generated/telegraphe.js';
import type { MailboxStore } from './mailbox.js';
import type { MessageRouter } from './router.js';

export type GroupRole = 'admin' | 'member';

export const requireAdmin = (role: GroupRole | undefined): void => {
  if (role !== 'admin') throw new GroupPermissionError();
};

export class GroupPermissionError extends Error {
  public constructor() {
    super('Droits administrateur requis');
    this.name = 'GroupPermissionError';
  }
}

export async function groupRole(
  db: pg.Pool,
  conversationId: string,
  userId: string,
): Promise<GroupRole | undefined> {
  const result = await db.query<{ role: GroupRole }>(
    'SELECT role FROM conversation_members WHERE conversation_id=$1 AND user_id=$2',
    [conversationId, userId],
  );
  return result.rows[0]?.role;
}

export async function groupMemberDevices(
  db: pg.Pool,
  conversationId: string,
  senderUserId: string,
): Promise<Array<{ userId: string; deviceId: string }>> {
  const result = await db.query<{ user_id: string; device_id: string }>(
    `SELECT m.user_id, d.id AS device_id
     FROM conversation_members m
     JOIN devices d ON d.user_id=m.user_id
     WHERE m.conversation_id=$1 AND m.user_id<>$2`,
    [conversationId, senderUserId],
  );
  return result.rows.map((row) => ({ userId: row.user_id, deviceId: row.device_id }));
}

export async function broadcastSystemEvent(
  db: pg.Pool,
  mailbox: MailboxStore,
  router: MessageRouter,
  conversationId: string,
  actorUserId: string,
  text: string,
): Promise<void> {
  const members = await groupMemberDevices(db, conversationId, '');
  const message: Envelope = {
    type: 10 as Envelope['type'],
    clientId: crypto.randomUUID(),
    timestampMs: Date.now(),
    conversationId,
    encryptionVersion: 0,
    payload: TextMessageCodec.encode({
      recipientUserId: '',
      recipientDeviceId: '',
      text: `[system:${actorUserId}] ${text}`,
    }).finish(),
  };
  const encoded = EnvelopeCodec.encode(message).finish();
  for (const member of members) {
    const stored = await mailbox.store({
      recipientUserId: member.userId,
      recipientDeviceId: member.deviceId,
      senderUserId: actorUserId,
      conversationId,
      clientId: message.clientId ?? '',
      envelope: encoded,
    });
    if (!stored.duplicate) await router.route(member.deviceId, encoded);
  }
}
