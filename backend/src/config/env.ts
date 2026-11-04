import 'dotenv/config';
import { z } from 'zod';

const bool = z
  .string()
  .optional()
  .transform((v) => v === 'true' || v === '1');

const schema = z
  .object({
    PORT: z.coerce.number().default(3000),
    DATABASE_URL: z.string().min(1),
    /** Conexões no pool. Neon gratuito: mantenha baixo (5). VPS: 10–20. */
    DB_POOL_MAX: z.coerce.number().int().positive().default(5),
    JWT_SECRET: z.string().min(32, 'JWT_SECRET precisa ter ao menos 32 caracteres'),
    JWT_EXPIRES_IN: z.string().default('8h'),
    /** URL pública da API. No Render é preenchida sozinha via RENDER_EXTERNAL_URL. */
    PUBLIC_BASE_URL: z.string().optional(),
    RENDER_EXTERNAL_URL: z.string().optional(),
    CORS_ORIGIN: z.string().default('*'),

    /**
     * Onde guardar as logos:
     *  db    → no próprio PostgreSQL (padrão; ideal para hospedagem gratuita)
     *  local → pasta UPLOAD_DIR no disco (VPS com disco persistente)
     *  s3    → qualquer S3 compatível: Cloudflare R2, Supabase Storage, MinIO, AWS
     */
    STORAGE_DRIVER: z.enum(['db', 'local', 's3']).default('db'),
    UPLOAD_DIR: z.string().default('uploads'),
    S3_ENDPOINT: z.string().optional(),
    S3_REGION: z.string().default('auto'),
    S3_BUCKET: z.string().optional(),
    S3_ACCESS_KEY_ID: z.string().optional(),
    S3_SECRET_ACCESS_KEY: z.string().optional(),
    /** URL pública do bucket (ex.: https://pub-xxxx.r2.dev ou domínio próprio) */
    S3_PUBLIC_URL: z.string().optional(),

    /** Só para diagnóstico: permite subir mesmo conectado como dono do banco. NÃO use em produção. */
    ALLOW_UNSAFE_DB_ROLE: bool,
  })
  .superRefine((e, ctx) => {
    if (e.STORAGE_DRIVER === 's3') {
      for (const k of ['S3_ENDPOINT', 'S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY', 'S3_PUBLIC_URL'] as const) {
        if (!e[k]) ctx.addIssue({ code: 'custom', path: [k], message: `${k} é obrigatório com STORAGE_DRIVER=s3` });
      }
    }
  });

const parsed = schema.parse(process.env);

export const env = {
  ...parsed,
  PUBLIC_BASE_URL: (parsed.PUBLIC_BASE_URL || parsed.RENDER_EXTERNAL_URL || `http://localhost:${parsed.PORT}`).replace(/\/$/, ''),
};

export const CREDITS = 'Desenvolvido por Edivaldo.Nascimento - IaHope-Technology';
