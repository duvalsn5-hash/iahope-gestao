import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { db, requireAuth, requireRole, signToken } from '../../middleware/auth';
import { audit } from '../../security/audit';
import { assertStrongPassword } from '../../security/password';
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
  mustChangePassword: !!u.must_change_password,
  totpEnabled: !!u.totp_enabled,
  locked: u.locked_until != null && new Date(u.locked_until) > new Date(),
});
const COLS = `id, username::text, full_name, email::text, role, is_active, commission_pct, last_login_at,
              must_change_password, totp_enabled, locked_until`;

/** GET /users — gestão (ADMIN/GERENTE). ?role=MECANICO para listas de seleção */
usersRouter.get('/', requireRole('ADMIN', 'GERENTE', 'CAIXA', 'MECANICO'), async (req, res) => {
  const role = String(req.query.role ?? '');
  const r = await db(req, async (c) => {
    const users = (
      await c.query(
        `SELECT ${COLS}
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
  assertStrongPassword(b.password, b.username);
  const hash = await bcrypt.hash(b.password, 10);
  const u = await db(req, async (c) => {
    await assertSeat(c, req.auth!.tid);
    // senha criada pelo administrador é provisória: a pessoa troca no 1º acesso
    const nu = (
      await c.query(
        `INSERT INTO app.users (username, full_name, email, role, password_hash, commission_pct, must_change_password)
         VALUES ($1, $2, $3, $4, $5, $6, true)
         RETURNING ${COLS}`,
        [b.username, b.fullName, b.email || null, b.role, hash, b.commissionPct],
      )
    ).rows[0];
    await audit(c, 'USUARIO_CRIADO', { usuario: b.username, perfil: b.role });
    return nu;
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
  unlock: z.boolean().default(false),     // libera usuário bloqueado por senha errada
  resetTotp: z.boolean().default(false),  // perdeu o celular: zera as 2 etapas
});

/** PUT /users/:id — editar, desativar, trocar senha */
usersRouter.put('/:id', requireRole('ADMIN'), async (req, res) => {
  const b = updateSchema.parse(req.body);
  if (req.params.id === req.auth!.sub && (!b.isActive || b.role !== 'ADMIN')) {
    throw new HttpError(422, 'PROPRIO_USUARIO', 'Você não pode desativar nem tirar o perfil de administrador de si mesmo');
  }
  if (b.newPassword) assertStrongPassword(b.newPassword);
  const hash = b.newPassword ? await bcrypt.hash(b.newPassword, 10) : null;
  const u = await db(req, async (c) => {
    const cur = (await c.query(`SELECT is_active, role FROM app.users WHERE id = $1 AND role <> 'SUPER_ADMIN'`, [req.params.id])).rows[0];
    if (!cur) throw new HttpError(404, 'NAO_ENCONTRADO', 'Usuário não encontrado');
    if (!cur.is_active && b.isActive) await assertSeat(c, req.auth!.tid);
    const nu = (
      await c.query(
        `UPDATE app.users SET full_name = $2, email = $3, role = $4, is_active = $5, commission_pct = $6,
                password_hash = coalesce($7, password_hash),
                must_change_password = CASE WHEN $7 IS NOT NULL THEN id <> app.current_user_id() ELSE must_change_password END,
                failed_logins = CASE WHEN $8 THEN 0 ELSE failed_logins END,
                locked_until = CASE WHEN $8 THEN NULL ELSE locked_until END,
                totp_enabled = CASE WHEN $9 THEN false ELSE totp_enabled END,
                totp_secret = CASE WHEN $9 THEN NULL ELSE totp_secret END
          WHERE id = $1
          RETURNING ${COLS}`,
        [req.params.id, b.fullName, b.email || null, b.role, b.isActive, b.commissionPct, hash, b.unlock, b.resetTotp],
      )
    ).rows[0];
    await audit(c, 'USUARIO_ALTERADO', {
      usuario: nu.username, perfil: b.role, ativo: b.isActive, senha_redefinida: !!hash, desbloqueado: b.unlock, '2fa_zerada': b.resetTotp,
    });
    return nu;
  });
  res.json(map(u));
});

/** PUT /users/me/password — qualquer usuário troca a própria senha */
usersRouter.put('/me/password', async (req, res) => {
  const b = z.object({ current: z.string().min(1), next: z.string().min(8, 'Senha com no mínimo 8 caracteres') }).parse(req.body);
  const tv = await db(req, async (c) => {
    const u = (await c.query('SELECT username::text, password_hash FROM app.users WHERE id = $1', [req.auth!.sub])).rows[0];
    if (!u || !(await bcrypt.compare(b.current, u.password_hash))) {
      throw new HttpError(422, 'SENHA_ATUAL', 'Senha atual incorreta');
    }
    if (b.current === b.next) throw new HttpError(422, 'SENHA_IGUAL', 'A nova senha precisa ser diferente da atual');
    assertStrongPassword(b.next, u.username);
    const r = (
      await c.query('UPDATE app.users SET password_hash = $2, must_change_password = false WHERE id = $1 RETURNING token_version', [
        req.auth!.sub, await bcrypt.hash(b.next, 10),
      ])
    ).rows[0];
    await audit(c, 'SENHA_ALTERADA');
    return r.token_version as number;
  });
  // trocar a senha derruba as outras sessões; este aparelho recebe um token novo
  const { sub, tid, cnpj, role } = req.auth!;
  res.json({ ok: true, token: signToken({ sub, tid, cnpj, role, tv }) });
});
