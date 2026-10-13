import { createHash, createHmac } from 'node:crypto';
import type { Config } from './config.js';

export type MediaKind = 'photo' | 'video';

export interface MediaDescriptor {
  id: string;
  conversationId: string;
  contentType: string;
  byteSize: number;
  width: number;
  height: number;
  durationSeconds: number | null;
  thumbnailObjectKey: string | null;
}

export interface MediaUrls {
  uploadUrl: string;
  downloadUrl: string;
  expiresAt: string;
}

export interface MediaStorage {
  presignUpload(objectKey: string, contentType: string, expiresIn: number): Promise<string>;
  presignDownload(objectKey: string, expiresIn: number): Promise<string>;
}

export class MinioMediaStorage implements MediaStorage {
  public constructor(private readonly cfg: Config) {}

  public presignUpload(objectKey: string, contentType: string, expiresIn: number): Promise<string> {
    return Promise.resolve(this.presign('PUT', objectKey, expiresIn, contentType));
  }

  public presignDownload(objectKey: string, expiresIn: number): Promise<string> {
    return Promise.resolve(this.presign('GET', objectKey, expiresIn));
  }

  private presign(
    method: 'GET' | 'PUT',
    objectKey: string,
    expiresIn: number,
    contentType?: string,
  ): string {
    const endpoint = new URL(this.cfg.MINIO_ENDPOINT);
    const now = new Date();
    const date = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
    const shortDate = date.slice(0, 8);
    const credential = `${this.cfg.MINIO_ACCESS_KEY}/${shortDate}/${this.cfg.MINIO_REGION}/s3/aws4_request`;
    const path = `/${this.cfg.MINIO_BUCKET}/${objectKey.split('/').map(encodeURIComponent).join('/')}`;
    const headers = contentType
      ? `&X-Amz-SignedHeaders=content-type%3Bhost`
      : '&X-Amz-SignedHeaders=host';
    const query = `X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=${encodeURIComponent(credential)}&X-Amz-Date=${date}&X-Amz-Expires=${expiresIn}${headers.slice(1)}`;
    const canonicalHeaders = contentType
      ? `content-type:${contentType}\nhost:${endpoint.host}\n`
      : `host:${endpoint.host}\n`;
    const canonicalRequest = [
      method,
      path,
      query.split('&').sort().join('&'),
      canonicalHeaders,
      contentType ? 'content-type;host' : 'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');
    const scope = `${shortDate}/${this.cfg.MINIO_REGION}/s3/aws4_request`;
    const stringToSign = `AWS4-HMAC-SHA256\n${date}\n${scope}\n${hash(canonicalRequest)}`;
    const signature = hmac(
      hmac(hmac(hmac(`AWS4${this.cfg.MINIO_SECRET_KEY}`, shortDate), this.cfg.MINIO_REGION), 's3'),
      'aws4_request',
    );
    const signed = hmac(signature, stringToSign);
    return `${endpoint.origin}${path}?${query}&X-Amz-Signature=${signed}`;
  }
}

const hmac = (key: string | Buffer, value: string): Buffer =>
  createHmac('sha256', key).update(value).digest();
const hash = (value: string): string => createHash('sha256').update(value).digest('hex');
