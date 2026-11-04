import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { isValidCnpj, onlyDigits } from '../../utils/cnpj';
import { absoluteUrl } from '../auth/auth.routes';

/**
 * Módulo Administração Master — exclusivo do perfil SUPER_ADMIN.
 * O contexto RLS com role=SUPER_ADMIN libera acesso global no banco;
 * o requireRole aqui é a segunda camada (defesa em profundidade).
 */
export const adminRouter = Router();
adminRouter.use(requireAuth, requireRole('SUPER_ADMIN'));

const mapTenant = (t: any) => ({
  id: t.id,
  cnpj: t.cnpj,
  razaoSocial: t.razao_social,
  nomeFantasia: t.nome_fantasia,
  logoUrl: absoluteUrl(t.logo_url),
  status: t.status,
  blockedReason: t.blocked_reason,
  licenseExpiresAt: t.license_expires_at,
  maxUsers: t.max_users,
  usersCount: Number(t.users_count ?? 0),
  isPlatform: t.is_platform,
  createdAt: t.created_at,
});

/** GET /admin/tenants?q=&status= — lista todas as empresas */
adminRouter.get('/tenants', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const status = String(req.query.status ?? '');
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT t.*, (SELECT count(*) FROM app.users u WHERE u.tenant_id = t.id) AS users_count
           FROM app.tenants t
          WHERE ($1 = '' OR t.cnpj LIKE '%' || regexp_replace($1, '\\D', '', 'g') || '%'
                 OR t.razao_social ILIKE '%' || $1 || '%' OR t.nome_fantasia ILIKE '%' || $1 || '%')
            AND ($2 = '' OR t.status::text = $2)
          ORDER BY t.is_platform DESC, t.razao_social`,
        [q, status],
      )
    ).rows,
  );
  res.json(rows.map(mapTenant));
});

/** GET /admin/stats — números do painel */
adminRouter.get('/stats', async (req, res) => {
  const r = await db(req, async (c) =>
    (
      await c.query(`SELECT
         count(*) FILTER (WHERE NOT is_platform)                                  AS total,
         count(*) FILTER (WHERE status = 'ATIVO' AND NOT is_platform)             AS ativos,
         count(*) FILTER (WHERE status = 'BLOQUEADO')                             AS bloqueados,
         count(*) FILTER (WHERE license_expires_at < current_date AND NOT is_platform) AS vencidos,
         count(*) FILTER (WHERE license_expires_at BETWEEN current_date AND current_date + 7
                            AND NOT is_platform)                                  AS vencendo_7d
       FROM app.tenants`)
    ).rows[0],
  );
  res.json(Object.fromEntries(Object.entries(r).map(([k, v]) => [k, Number(v)])));
});

const createSchema = z.object({
  cnpj: z.string().transform(onlyDigits).refine(isValidCnpj, 'CNPJ inválido'),
  razaoSocial: z.string().trim().min(3),
  nomeFantasia: z.string().trim().optional(),
  licenseExpiresAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  maxUsers: z.number().int().positive().default(10),
  admin: z.object({
    username: z.string().trim().min(3),
    fullName: z.string().trim().min(3),
    password: z.string().min(8, 'Senha com no mínimo 8 caracteres'),
  }),
});

/** POST /admin/tenants — cria cliente + usuário ADMIN inicial */
adminRouter.post('/tenants', async (req, res) => {
  const b = createSchema.parse(req.body);
  const hash = await bcrypt.hash(b.admin.password, 10);
  const tenant = await db(req, async (c) => {
    const t = (
      await c.query(
        `INSERT INTO app.tenants (cnpj, razao_social, nome_fantasia, license_expires_at, max_users)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [b.cnpj, b.razaoSocial, b.nomeFantasia ?? null, b.licenseExpiresAt, b.maxUsers],
      )
    ).rows[0];
    await c.query(
      `INSERT INTO app.users (tenant_id, username, full_name, password_hash, role)
       VALUES ($1, $2, $3, $4, 'ADMIN')`,
      [t.id, b.admin.username, b.admin.fullName, hash],
    );
    await c.query(`INSERT INTO app.audit_log (tenant_id, user_id, action, details) VALUES ($1, $2, 'TENANT_CRIADO', $3)`, [
      t.id, req.auth!.sub, { cnpj: b.cnpj },
    ]);
    return t;
  });
  res.status(201).json(mapTenant({ ...tenant, users_count: 1 }));
});

const statusSchema = z.object({
  status: z.enum(['ATIVO', 'BLOQUEADO']),
  reason: z.string().trim().max(300).optional(),
});

/** PATCH /admin/tenants/:id/status — ativar / bloquear acesso de um CNPJ */
adminRouter.patch('/tenants/:id/status', async (req, res) => {
  const b = statusSchema.parse(req.body);
  const t = await db(req, async (c) => {
    const r = await c.query(
      `UPDATE app.tenants SET status = $2::app.tenant_status,
              blocked_reason = CASE WHEN $2::text = 'BLOQUEADO' THEN $3::text END
        WHERE id = $1 AND NOT is_platform RETURNING *`,
      [req.params.id, b.status, b.reason ?? null],
    );
    if (!r.rows[0]) throw new HttpError(404, 'NAO_ENCONTRADO', 'Empresa não encontrada');
    await c.query(`INSERT INTO app.audit_log (tenant_id, user_id, action, details) VALUES ($1, $2, $3, $4)`, [
      req.params.id, req.auth!.sub, b.status === 'ATIVO' ? 'TENANT_ATIVADO' : 'TENANT_BLOQUEADO', { reason: b.reason },
    ]);
    return r.rows[0];
  });
  res.json(mapTenant(t));
});

const updateSchema = z.object({
  razaoSocial: z.string().trim().min(3).optional(),
  nomeFantasia: z.string().trim().optional(),
  licenseExpiresAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  maxUsers: z.number().int().positive().optional(),
});

/** PATCH /admin/tenants/:id — renovar licença, editar dados */
adminRouter.patch('/tenants/:id', async (req, res) => {
  const b = updateSchema.parse(req.body);
  const t = await db(req, async (c) => {
    const r = await c.query(
      `UPDATE app.tenants SET
          razao_social       = coalesce($2, razao_social),
          nome_fantasia      = coalesce($3, nome_fantasia),
          license_expires_at = coalesce($4::date, license_expires_at),
          max_users          = coalesce($5, max_users)
        WHERE id = $1 RETURNING *`,
      [req.params.id, b.razaoSocial ?? null, b.nomeFantasia ?? null, b.licenseExpiresAt ?? null, b.maxUsers ?? null],
    );
    if (!r.rows[0]) throw new HttpError(404, 'NAO_ENCONTRADO', 'Empresa não encontrada');
    await c.query(`INSERT INTO app.audit_log (tenant_id, user_id, action, details) VALUES ($1, $2, 'TENANT_ATUALIZADO', $3)`, [
      req.params.id, req.auth!.sub, b,
    ]);
    return r.rows[0];
  });
  res.json(mapTenant(t));
});

/** GET /admin/audit — últimas ações */
adminRouter.get('/audit', async (req, res) => {
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT a.*, t.cnpj, t.razao_social FROM app.audit_log a
           LEFT JOIN app.tenants t ON t.id = a.tenant_id
          ORDER BY a.created_at DESC LIMIT 200`,
      )
    ).rows,
  );
  res.json(rows);
});
