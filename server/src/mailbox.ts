import type pg from 'pg';

export interface MailboxItem {
  id: number;
  clientId: string;
  envelope: Uint8Array;
}

export interface MailboxStore {
  store(input: {
    recipientUserId: string;
    recipientDeviceId: string;
    senderUserId: string;
    conversationId: string;
    clientId: string;
    envelope: Uint8Array;
  }): Promise<{ id: number; duplicate: boolean }>;
  pending(deviceId: string): Promise<MailboxItem[]>;
  acknowledge(deviceId: string, clientId: string): Promise<MailboxItem | undefined>;
  purgeConversation(recipientUserId: string, conversationId: string): Promise<void>;
}

export class PostgresMailboxStore implements MailboxStore {
  public constructor(private readonly db: pg.Pool) {}

  public async store(input: Parameters<MailboxStore['store']>[0]): Promise<{
    id: number;
    duplicate: boolean;
  }> {
    const result = await this.db.query<{ id: string; duplicate: boolean }>(
      `INSERT INTO mailbox
       (recipient_user_id, recipient_device_id, sender_user_id, conversation_id, client_id, envelope)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (recipient_device_id, client_id)
       DO UPDATE SET client_id=EXCLUDED.client_id
       RETURNING id, (xmax <> 0) AS duplicate`,
      [
        input.recipientUserId,
        input.recipientDeviceId,
        input.senderUserId,
        input.conversationId,
        input.clientId,
        Buffer.from(input.envelope),
      ],
    );
    return { id: Number(result.rows[0].id), duplicate: result.rows[0].duplicate };
  }

  public async pending(deviceId: string): Promise<MailboxItem[]> {
    const result = await this.db.query<{ id: string; client_id: string; envelope: Buffer }>(
      `SELECT m.id, m.client_id, m.envelope
       FROM mailbox m
       LEFT JOIN mailbox_cursors c ON c.device_id=$1
       WHERE m.recipient_device_id=$1 AND m.id > COALESCE(c.acknowledged_id, 0)
       ORDER BY m.id ASC`,
      [deviceId],
    );
    return result.rows.map((row) => ({
      id: Number(row.id),
      clientId: row.client_id,
      envelope: new Uint8Array(row.envelope),
    }));
  }

  public async acknowledge(deviceId: string, clientId: string): Promise<MailboxItem | undefined> {
    const client = await this.db.connect();
    await client.query('BEGIN');
    try {
      const result = await client.query<{ id: string; envelope: Buffer }>(
        'SELECT id, envelope FROM mailbox WHERE recipient_device_id=$1 AND client_id=$2',
        [deviceId, clientId],
      );
      if (result.rowCount) {
        const id = Number(result.rows[0].id);
        await client.query(
          `INSERT INTO mailbox_cursors (device_id, acknowledged_id)
           VALUES ($1,$2)
           ON CONFLICT (device_id) DO UPDATE
           SET acknowledged_id=GREATEST(mailbox_cursors.acknowledged_id, EXCLUDED.acknowledged_id),
               updated_at=now()`,
          [deviceId, id],
        );
        await client.query('DELETE FROM mailbox WHERE recipient_device_id=$1 AND id <= $2', [
          deviceId,
          id,
        ]);
      }

      await client.query('COMMIT');
      return result.rowCount
        ? {
            id: Number(result.rows[0].id),
            clientId,
            envelope: new Uint8Array(result.rows[0].envelope),
          }
        : undefined;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  public async purgeConversation(recipientUserId: string, conversationId: string): Promise<void> {
    await this.db.query('DELETE FROM mailbox WHERE recipient_user_id=$1 AND conversation_id=$2', [
      recipientUserId,
      conversationId,
    ]);
  }
}

export class MemoryMailboxStore implements MailboxStore {
  private nextId = 1;
  private readonly items = new Map<string, MailboxItem[]>();

  public async store(input: Parameters<MailboxStore['store']>[0]): Promise<{
    id: number;
    duplicate: boolean;
  }> {
    const items = this.items.get(input.recipientDeviceId) ?? [];
    const existing = items.find((item) => item.clientId === input.clientId);
    if (existing) return { id: existing.id, duplicate: true };
    const item = { id: this.nextId++, clientId: input.clientId, envelope: input.envelope };
    items.push(item);
    this.items.set(input.recipientDeviceId, items);
    return { id: item.id, duplicate: false };
  }

  public async pending(deviceId: string): Promise<MailboxItem[]> {
    return [...(this.items.get(deviceId) ?? [])];
  }

  public async acknowledge(deviceId: string, clientId: string): Promise<MailboxItem | undefined> {
    const item = (this.items.get(deviceId) ?? []).find(
      (candidate) => candidate.clientId === clientId,
    );
    this.items.set(
      deviceId,
      (this.items.get(deviceId) ?? []).filter((item) => item.clientId !== clientId),
    );
    return item;
  }

  public async purgeConversation(recipientUserId: string, conversationId: string): Promise<void> {
    void conversationId;
    this.items.delete(recipientUserId);
  }
}
