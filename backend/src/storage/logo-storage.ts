/**
 * Armazenamento da logo das empresas (White-Label), com 3 drivers trocáveis
 * só por variável de ambiente — o resto da API não muda:
 *
 *   STORAGE_DRIVER=db     PostgreSQL (tabela app.tenant_assets) — grátis, sem serviço extra
 *   STORAGE_DRIVER=local  pasta no disco — VPS/hosting com disco persistente
 *   STORAGE_DRIVER=s3     Cloudflare R2 / Supabase Storage / MinIO / AWS S3
 *
 * Em todos os casos o banco guarda em tenants.logo_url o caminho/URL final.
 */
import fs from 'node:fs';
import path from 'node:path';
import { PoolClient } from 'pg';
import { env } from '../config/env';

export type LogoExt = '.png' | '.jpg' | '.webp';
const MIME: Record<LogoExt, string> = { '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp' };

export interface LogoStorage {
  /** Grava a logo e devolve o valor para tenants.logo_url (relativo ou absoluto). */
  save(db: PoolClient, tenantId: string, data: Buffer, ext: LogoExt): Promise<string>;
  remove(db: PoolClient, tenantId: string): Promise<void>;
}

// ---------------------------------------------------------------- db
class DbStorage implements LogoStorage {
  async save(db: PoolClient, tenantId: string, data: Buffer, ext: LogoExt) {
    await db.query(
      `INSERT INTO app.tenant_assets (tenant_id, kind, content_type, data, updated_at)
       VALUES ($1, 'logo', $2, $3, now())
       ON CONFLICT (tenant_id, kind) DO UPDATE
         SET content_type = EXCLUDED.content_type, data = EXCLUDED.data, updated_at = now()`,
      [tenantId, MIME[ext], data],
    );
    // ?v= muda a cada envio → apps e navegadores não usam a logo antiga do cache
    return `/public/logos/${tenantId}?v=${Date.now()}`;
  }
  async remove(db: PoolClient, tenantId: string) {
    await db.query(`DELETE FROM app.tenant_assets WHERE tenant_id = $1 AND kind = 'logo'`, [tenantId]);
  }
}

// ---------------------------------------------------------------- local
class LocalStorage implements LogoStorage {
  private dir(tenantId: string) {
    return path.resolve(env.UPLOAD_DIR, tenantId);
  }
  async save(_db: PoolClient, tenantId: string, data: Buffer, ext: LogoExt) {
    const dir = this.dir(tenantId);
    await fs.promises.mkdir(dir, { recursive: true });
    await this.clear(dir);
    const name = `logo-${Date.now()}${ext}`;
    await fs.promises.writeFile(path.join(dir, name), data);
    return `/uploads/${tenantId}/${name}`;
  }
  async remove(_db: PoolClient, tenantId: string) {
    await this.clear(this.dir(tenantId));
  }
  private async clear(dir: string) {
    if (!fs.existsSync(dir)) return;
    for (const f of await fs.promises.readdir(dir)) if (f.startsWith('logo-')) await fs.promises.unlink(path.join(dir, f));
  }
}

// ---------------------------------------------------------------- s3 (R2, Supabase, MinIO, AWS)
class S3Storage implements LogoStorage {
  private client: any;
  private async s3() {
    if (!this.client) {
      const { S3Client } = await import('@aws-sdk/client-s3');
      this.client = new S3Client({
        region: env.S3_REGION,
        endpoint: env.S3_ENDPOINT,
        forcePathStyle: true, // exigido por MinIO/Supabase; aceito pelo R2
        credentials: { accessKeyId: env.S3_ACCESS_KEY_ID!, secretAccessKey: env.S3_SECRET_ACCESS_KEY! },
      });
    }
    return this.client;
  }
  async save(_db: PoolClient, tenantId: string, data: Buffer, ext: LogoExt) {
    const { PutObjectCommand } = await import('@aws-sdk/client-s3');
    await this.remove(_db, tenantId);
    const key = `logos/${tenantId}/logo-${Date.now()}${ext}`;
    await (await this.s3()).send(
      new PutObjectCommand({
        Bucket: env.S3_BUCKET,
        Key: key,
        Body: data,
        ContentType: MIME[ext],
        CacheControl: 'public, max-age=31536000, immutable',
      }),
    );
    return `${env.S3_PUBLIC_URL!.replace(/\/$/, '')}/${key}`;
  }
  async remove(_db: PoolClient, tenantId: string) {
    const { ListObjectsV2Command, DeleteObjectsCommand } = await import('@aws-sdk/client-s3');
    const s3 = await this.s3();
    const list = await s3.send(new ListObjectsV2Command({ Bucket: env.S3_BUCKET, Prefix: `logos/${tenantId}/` }));
    const keys = (list.Contents ?? []).map((o: any) => ({ Key: o.Key }));
    if (keys.length) await s3.send(new DeleteObjectsCommand({ Bucket: env.S3_BUCKET, Delete: { Objects: keys } }));
  }
}

export const logoStorage: LogoStorage =
  env.STORAGE_DRIVER === 's3' ? new S3Storage() : env.STORAGE_DRIVER === 'local' ? new LocalStorage() : new DbStorage();
