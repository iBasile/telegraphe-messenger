/* eslint-disable */
// Generated from ../proto/telegraphe.proto. Do not edit by hand.
// proto-sha256: 052c41754abd65453c55b60366f9aea535864f3e23d4037e3807d9dbe423949b
import { Type, Root } from 'protobufjs';

const root = Root.fromJSON({
  nested: {
    telegraphe: {
      nested: {
        v1: {
          nested: {
            EnvelopeType: {
              values: {
                ENVELOPE_TYPE_UNSPECIFIED: 0,
                HANDSHAKE: 1,
                HANDSHAKE_ACK: 2,
                SEND_TEXT: 3,
                SERVER_ACK: 4,
                DELIVERED: 5,
                READ: 6,
                TYPING: 7,
                PRESENCE: 8,
                ERROR: 9,
                SYSTEM_EVENT: 10,
                SEND_MEDIA: 11,
              },
            },
            Envelope: {
              fields: {
                type: { type: 'EnvelopeType', id: 1 },
                clientId: { type: 'string', id: 2 },
                timestampMs: { type: 'int64', id: 3 },
                conversationId: { type: 'string', id: 4 },
                senderDeviceId: { type: 'string', id: 5 },
                encryptionVersion: { type: 'uint32', id: 6 },
                payload: { type: 'bytes', id: 7 },
              },
            },
            Handshake: {
              fields: {
                protocolVersion: { type: 'uint32', id: 1 },
                deviceId: { type: 'string', id: 2 },
              },
            },
            HandshakeAck: { fields: { protocolVersion: { type: 'uint32', id: 1 } } },
            TextMessage: {
              fields: {
                recipientUserId: { type: 'string', id: 1 },
                recipientDeviceId: { type: 'string', id: 2 },
                text: { type: 'string', id: 3 },
              },
            },
            MediaMessage: {
              fields: {
                mediaId: { type: 'string', id: 1 },
                kind: { type: 'Kind', id: 2 },
                width: { type: 'uint32', id: 3 },
                height: { type: 'uint32', id: 4 },
                durationSeconds: { type: 'uint32', id: 5 },
                thumbnailMediaId: { type: 'string', id: 6 },
              },
              nested: {
                Kind: {
                  values: { KIND_UNSPECIFIED: 0, PHOTO: 1, VIDEO: 2 },
                },
              },
            },
            ServerAck: {
              fields: {
                messageClientId: { type: 'string', id: 1 },
                accepted: { type: 'bool', id: 2 },
                duplicate: { type: 'bool', id: 3 },
                mailboxId: { type: 'int64', id: 4 },
              },
            },
            Receipt: {
              fields: {
                messageClientId: { type: 'string', id: 1 },
                targetDeviceId: { type: 'string', id: 2 },
              },
            },
            Typing: {
              fields: {
                isTyping: { type: 'bool', id: 1 },
                targetDeviceId: { type: 'string', id: 2 },
              },
            },
            Presence: {
              fields: {
                online: { type: 'bool', id: 1 },
                targetDeviceId: { type: 'string', id: 2 },
              },
            },
            Error: {
              fields: {
                code: { type: 'string', id: 1 },
                message: { type: 'string', id: 2 },
              },
            },
          },
        },
      },
    },
  },
});

export enum EnvelopeType {
  ENVELOPE_TYPE_UNSPECIFIED = 0,
  HANDSHAKE = 1,
  HANDSHAKE_ACK = 2,
  SEND_TEXT = 3,
  SERVER_ACK = 4,
  DELIVERED = 5,
  READ = 6,
  TYPING = 7,
  PRESENCE = 8,
  ERROR = 9,
  SYSTEM_EVENT = 10,
  SEND_MEDIA = 11,
}

export interface Envelope {
  type?: EnvelopeType;
  clientId?: string;
  timestampMs?: number;
  conversationId?: string;
  senderDeviceId?: string;
  encryptionVersion?: number;
  payload?: Uint8Array;
}
export interface Handshake {
  protocolVersion?: number;
  deviceId?: string;
}
export interface HandshakeAck {
  protocolVersion?: number;
}
export interface TextMessage {
  recipientUserId?: string;
  recipientDeviceId?: string;
  text?: string;
}
export interface MediaMessage {
  mediaId?: string;
  kind?: MediaMessage_Kind;
  width?: number;
  height?: number;
  durationSeconds?: number;
  thumbnailMediaId?: string;
}
export enum MediaMessage_Kind {
  KIND_UNSPECIFIED = 0,
  PHOTO = 1,
  VIDEO = 2,
}
export interface ServerAck {
  messageClientId?: string;
  accepted?: boolean;
  duplicate?: boolean;
  mailboxId?: number;
}
export interface Receipt {
  messageClientId?: string;
  targetDeviceId?: string;
}
export interface Typing {
  isTyping?: boolean;
  targetDeviceId?: string;
}
export interface Presence {
  online?: boolean;
  targetDeviceId?: string;
}
export interface Error {
  code?: string;
  message?: string;
}

type Codec<T> = {
  encode(value: T): { finish(): Uint8Array };
  decode(value: Uint8Array): T;
};

const codec = <T>(name: string): Codec<T> => {
  const type = root.lookupType(`telegraphe.v1.${name}`) as Type;
  return {
    encode: (value) => type.encode(type.fromObject(value as Parameters<typeof type.fromObject>[0])),
    decode: (value) =>
      type.toObject(type.decode(value), {
        longs: Number,
        enums: Number,
        bytes: Uint8Array,
      }) as T,
  };
};

export const EnvelopeCodec = codec<Envelope>('Envelope');
export const HandshakeCodec = codec<Handshake>('Handshake');
export const HandshakeAckCodec = codec<HandshakeAck>('HandshakeAck');
export const TextMessageCodec = codec<TextMessage>('TextMessage');
export const MediaMessageCodec = codec<MediaMessage>('MediaMessage');
export const ServerAckCodec = codec<ServerAck>('ServerAck');
export const ReceiptCodec = codec<Receipt>('Receipt');
export const TypingCodec = codec<Typing>('Typing');
export const PresenceCodec = codec<Presence>('Presence');
export const ErrorCodec = codec<Error>('Error');
