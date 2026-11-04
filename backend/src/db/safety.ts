import { env } from '../config/env';
import { pool } from './pool';

/**
 * Impede a API de subir conectada com um usuário que ignora o RLS
 * (dono das tabelas, superusuário ou BYPASSRLS). Nesse caso o isolamento
 * por CNPJ deixaria de existir — erro de configuração comum ao copiar a
 * connection string "padrão" do provedor em vez da do app_api.
 */
export async function assertSafeDbRole() {
  const { rows } = await pool.query(`
    SELECT current_user AS who,
           (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname = current_user) AS bypass,
           EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'app' AND tableowner = current_user) AS owner,
           to_regclass('app.tenants') IS NOT NULL AS has_schema`);
  const r = rows[0];
  if (!r.has_schema) throw new Error('Schema "app" não encontrado. Rode database/00_roles.sql, 01_schema.sql e 02_seed.sql.');
  if ((r.bypass || r.owner) && !env.ALLOW_UNSAFE_DB_ROLE) {
    throw new Error(
      `INSEGURO: a API está conectada como "${r.who}", que ${r.owner ? 'é dono das tabelas' : 'tem BYPASSRLS/superuser'} ` +
        'e ignora o isolamento por CNPJ. Use no DATABASE_URL o usuário app_api.',
    );
  }
}
