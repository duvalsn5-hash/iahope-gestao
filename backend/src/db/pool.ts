import { Pool, PoolClient, types } from 'pg';

// DATE (oid 1082) volta como 'YYYY-MM-DD' — evita deslocamento de fuso em datas de licença
types.setTypeParser(1082, (v) => v);
import { env } from '../config/env';

// Funciona com conexão direta ou com pooler (Neon "-pooler", PgBouncer em modo
// transação), pois o contexto RLS é definido com set_config(..., true) por transação.
export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: env.DB_POOL_MAX,
  idleTimeoutMillis: 30_000, // libera conexões → o Neon pode suspender e poupar horas
  connectionTimeoutMillis: 15_000, // tempo para o Neon "acordar"
});

/** Contexto de segurança aplicado em cada transação (lido pelas políticas RLS). */
export interface DbContext {
  tenantId: string | null;
  userId: string | null;
  role: string | null;
}

/**
 * Executa `fn` dentro de uma transação com o contexto RLS definido via
 * set_config(..., true) — o valor vale SÓ para esta transação, então é seguro
 * reutilizar conexões do pool entre empresas diferentes.
 */
export async function withTenant<T>(ctx: DbContext, fn: (db: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT set_config('app.tenant_id', $1, true),
              set_config('app.user_id',   $2, true),
              set_config('app.role',      $3, true)`,
      [ctx.tenantId ?? '', ctx.userId ?? '', ctx.role ?? ''],
    );
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
}

/** Consultas sem contexto (somente funções SECURITY DEFINER do fluxo pré-login). */
export function publicQuery<T extends Record<string, any> = any>(sql: string, params: unknown[] = []) {
  return pool.query<T>(sql, params);
}
