import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';

/**
 * Usuários da própria empresa (o ADMIN cadastra caixas, mecânicos, gerentes…).
 * Respeita o limite de usuários contratado (tenants.max_users).
 */
export const usersRouter = Router();
usersRouter.use(requireAuth);

const ROLES = ['ADMIN', 'GERENTE', 'OPERADOR', 'CAIXA', 'MECANICO'] as const;

const map = (u: any) => ({
  id: u.id,
  username: u.username,
  fullName: u.full_name,
  email: u.email,
  role: u.role,
  isActive: u.is_active,
  commissionPct: Number(u.commission_pct ?? 0),
  lastLoginAt: u.last_login_at,
});

/** GET /users — gestão (ADMIN/GERENTE). ?role=MECANICO para listas de seleção */
usersRouter.get('/', requireRole('ADMIN', 'GERENTE', 'CAIXA', 'MECANICO'), async (req, res) => {
  const role = String(req.query.role ?? '');
  const r = await db(req, async (c) => {
    const users = (
      await c.query(
        `SELECT id, username::text, full_name, email::text, role, is_active, commission_pct, last_login_at
           FROM app.users
          WHERE tenant_id = $1 AND role <> 'SUPER_ADMIN' AND ($2 = '' OR role::text = $2)
          ORDER BY is_active DESC, full_name`,
        [req.auth!.tid, role],
      )
    ).rows;
    const t = (await c.query('SELECT max_users FROM app.tenants WHERE id = $1', [req.auth!.tid])).rows[0];
    return { users, maxUsers: t?.max_users ?? 0 };
  });
  // quem não é gestor só vê nome e id (para escolher mecânico na OS)
  const manager = ['ADMIN', 'GERENTE', 'SUPER_ADMIN'].includes(req.auth!.role);
  res.json({
    maxUsers: r.maxUsers,
    activeCount: r.users.filter((u: any) => u.is_active).length,
    users: manager ? r.users.map(map) : r.users.filter((u: any) => u.is_active).map((u: any) => ({ id: u.id, fullName: u.full_name, role: u.role })),
  });
});

const createSchema = z.object({
  username: z.string().trim().min(3).max(40).regex(/^[a-zA-Z0-9._-]+$/, 'Use letras, números, ponto, hífen ou _'),
  fullName: z.string().trim().min(3).max(120),
  email: z.string().trim().email().optional().nullable().or(z.literal('')),
  role: z.enum(ROLES),
  password: z.string().min(8, 'Senha com no mínimo 8 caracteres'),
  commissionPct: z.number().min(0).max(100).default(0),
});

async function assertSeat(c: any, tenantId: string) {
  const r = (
    await c.query(
      `SELECT t.max_users, (SELECT count(*) FROM app.users u WHERE u.tenant_id = t.id AND u.is_active AND u.role <> 'SUPER_ADMIN') AS used
         FROM app.tenants t WHERE t.id = $1`,
      [tenantId],
    )
  ).rows[0];
  if (Number(r.used) >= Number(r.max_users)) {
    throw new HttpError(422, 'LIMITE_USUARIOS', `Limite de ${r.max_users} usuários do plano atingido. Fale com o suporte para ampliar.`);
  }
}

/** POST /users */
usersRouter.post('/', requireRole('ADMIN'), async (req, res) => {
  const b = createSchema.parse(req.body);
  const hash = await bcrypt.hash(b.password, 10);
  const u = await db(req, async (c) => {
    await assertSeat(c, req.auth!.tid);
    return (
      await c.query(
        `INSERT INTO app.users (username, full_name, email, role, password_hash, commission_pct)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, username::text, full_name, email::text, role, is_active, commission_pct, last_login_at`,
        [b.username, b.fullName, b.email || null, b.role, hash, b.commissionPct],
      )
    ).rows[0];
  });
  res.status(201).json(map(u));
});

const updateSchema = z.object({
  fullName: z.string().trim().min(3).max(120),
  email: z.string().trim().email().optional().nullable().or(z.literal('')),
  role: z.enum(ROLES),
  isActive: z.boolean(),
  commissionPct: z.number().min(0).max(100).default(0),
  newPassword: z.string().min(8, 'Senha com no mínimo 8 caracteres').optional().nullable().or(z.literal('')),
});

/** PUT /users/:id — editar, desativar, trocar senha */
usersRouter.put('/:id', requireRole('ADMIN'), async (req, res) => {
  const b = updateSchema.parse(req.body);
  if (req.params.id === req.auth!.sub && (!b.isActive || b.role !== 'ADMIN')) {
    throw new HttpError(422, 'PROPRIO_USUARIO', 'Você não pode desativar nem tirar o perfil de administrador de si mesmo');
  }
  const hash = b.newPassword ? await bcrypt.hash(b.newPassword, 10) : null;
  const u = await db(req, async (c) => {
    const cur = (await c.query(`SELECT is_active, role FROM app.users WHERE id = $1 AND role <> 'SUPER_ADMIN'`, [req.params.id])).rows[0];
    if (!cur) throw new HttpError(404, 'NAO_ENCONTRADO', 'Usuário não encontrado');
    if (!cur.is_active && b.isActive) await assertSeat(c, req.auth!.tid);
    return (
      await c.query(
        `UPDATE app.users SET full_name = $2, email = $3, role = $4, is_active = $5, commission_pct = $6,
                password_hash = coalesce($7, password_hash)
          WHERE id = $1
          RETURNING id, username::text, full_name, email::text, role, is_active, commission_pct, last_login_at`,
        [req.params.id, b.fullName, b.email || null, b.role, b.isActive, b.commissionPct, hash],
      )
    ).rows[0];
  });
  res.json(map(u));
});

/** PUT /users/me/password — qualquer usuário troca a própria senha */
usersRouter.put('/me/password', async (req, res) => {
  const b = z.object({ current: z.string().min(1), next: z.string().min(8, 'Senha com no mínimo 8 caracteres') }).parse(req.body);
  await db(req, async (c) => {
    const u = (await c.query('SELECT password_hash FROM app.users WHERE id = $1', [req.auth!.sub])).rows[0];
    if (!u || !(await bcrypt.compare(b.current, u.password_hash))) {
      throw new HttpError(422, 'SENHA_ATUAL', 'Senha atual incorreta');
    }
    await c.query('UPDATE app.users SET password_hash = $2 WHERE id = $1', [req.auth!.sub, await bcrypt.hash(b.next, 10)]);
  });
  res.json({ ok: true });
});
