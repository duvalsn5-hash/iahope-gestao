import { PoolClient } from 'pg';

/** Grava na auditoria da empresa do contexto atual (quem, o quê, quando). */
export async function audit(c: PoolClient, action: string, details: Record<string, unknown> = {}) {
  await c.query(
    `INSERT INTO app.audit_log (tenant_id, user_id, action, details)
     VALUES (app.current_tenant_id(), app.current_user_id(), $1, $2)`,
    [action, details],
  );
}
