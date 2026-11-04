import { Router } from 'express';
import bcrypt from 'bcryptjs';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { CREDITS, env } from '../../config/env';
import { publicQuery } from '../../db/pool';
import { HttpError } from '../../middleware/errors';
import { db, requireAuth, signToken } from '../../middleware/auth';
import { isValidCnpj, onlyDigits } from '../../utils/cnpj';

export const authRouter = Router();

/** Data de hoje 'YYYY-MM-DD' no fuso da operação */
const today = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Fortaleza' });

export const absoluteUrl = (path?: string | null) =>
  !path ? null : /^https?:\/\//.test(path) ? path : `${env.PUBLIC_BASE_URL}${path}`;

const loginLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: true });

/**
 * GET /auth/branding/:cnpj
 * Usado pela tela de login: ao terminar de digitar o CNPJ, mostra logo e nome.
 * Não revela se a empresa está bloqueada (só existe / não existe).
 */
authRouter.get('/branding/:cnpj', async (req, res) => {
  const cnpj = onlyDigits(req.params.cnpj);
  if (!isValidCnpj(cnpj)) throw new HttpError(400, 'CNPJ_INVALIDO', 'CNPJ inválido');
  const { rows } = await publicQuery('SELECT * FROM app.public_tenant_branding($1)', [cnpj]);
  if (!rows[0]) throw new HttpError(404, 'EMPRESA_NAO_ENCONTRADA', 'CNPJ não cadastrado');
  const t = rows[0];
  res.json({
    cnpj: t.cnpj,
    nomeFantasia: t.nome_fantasia ?? t.razao_social,
    logoUrl: absoluteUrl(t.logo_url),
    primaryColor: t.primary_color,
    credits: CREDITS,
  });
});

const loginSchema = z.object({
  cnpj: z.string().transform(onlyDigits).refine(isValidCnpj, 'CNPJ inválido'),
  username: z.string().trim().min(1),
  password: z.string().min(1),
});

/**
 * POST /auth/login  { cnpj, username, password }
 * 1) localiza usuário dentro do CNPJ  2) confere senha (bcrypt)
 * 3) bloqueia se empresa BLOQUEADA ou licença vencida (exceto SUPER_ADMIN)
 */
authRouter.post('/login', loginLimiter, async (req, res) => {
  const body = loginSchema.parse(req.body);
  const { rows } = await publicQuery('SELECT * FROM app.auth_lookup($1, $2)', [body.cnpj, body.username]);
  const u = rows[0];

  // Mesma mensagem para usuário inexistente e senha errada (não vaza quem existe)
  const ok = u && (await bcrypt.compare(body.password, u.password_hash));
  if (!ok) throw new HttpError(401, 'CREDENCIAIS_INVALIDAS', 'CNPJ, usuário ou senha incorretos');
  if (!u.user_active) throw new HttpError(403, 'USUARIO_INATIVO', 'Usuário desativado');

  if (u.role !== 'SUPER_ADMIN') {
    if (u.tenant_status === 'BLOQUEADO')
      throw new HttpError(403, 'EMPRESA_BLOQUEADA', 'Acesso da empresa bloqueado. Contate o suporte IaHope-Technology.');
    if (String(u.license_expires_at) < today())
      throw new HttpError(403, 'LICENCA_EXPIRADA', 'Licença expirada. Contate o suporte IaHope-Technology.');
  }

  await publicQuery('SELECT app.touch_last_login($1)', [u.user_id]);
  const token = signToken({ sub: u.user_id, tid: u.tenant_id, cnpj: u.cnpj, role: u.role });

  res.json({
    token,
    user: { id: u.user_id, username: u.username, fullName: u.full_name, role: u.role },
    tenant: {
      id: u.tenant_id,
      cnpj: u.cnpj,
      nomeFantasia: u.nome_fantasia ?? u.razao_social,
      razaoSocial: u.razao_social,
      logoUrl: absoluteUrl(u.logo_url),
      primaryColor: u.primary_color,
      licenseExpiresAt: u.license_expires_at,
      modules: u.modules ?? [],
    },
    credits: CREDITS,
  });
});

/** GET /auth/me — recarrega a sessão (ex.: após trocar a logo) */
authRouter.get('/me', requireAuth, async (req, res) => {
  const data = await db(req, async (c) => {
    const t = await c.query('SELECT * FROM app.tenants WHERE id = $1', [req.auth!.tid]);
    const u = await c.query('SELECT id, username::text, full_name, role FROM app.users WHERE id = $1', [req.auth!.sub]);
    return { t: t.rows[0], u: u.rows[0] };
  });
  res.json({
    user: { id: data.u.id, username: data.u.username, fullName: data.u.full_name, role: data.u.role },
    tenant: {
      id: data.t.id,
      cnpj: data.t.cnpj,
      nomeFantasia: data.t.nome_fantasia ?? data.t.razao_social,
      razaoSocial: data.t.razao_social,
      logoUrl: absoluteUrl(data.t.logo_url),
      primaryColor: data.t.primary_color,
      licenseExpiresAt: data.t.license_expires_at,
      modules: data.t.modules ?? [],
      scaleConfig: data.t.scale_config,
    },
    credits: CREDITS,
  });
});
