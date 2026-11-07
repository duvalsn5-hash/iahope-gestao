import { Router } from 'express';
import bcrypt from 'bcryptjs';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { CREDITS, env } from '../../config/env';
import { publicQuery } from '../../db/pool';
import { HttpError } from '../../middleware/errors';
import { db, readTotpTicket, requireAuth, signSupervisor, signToken, signTotpTicket } from '../../middleware/auth';
import { audit } from '../../security/audit';
import { newTotpSecret, otpauthUrl, verifyTotp } from '../../security/totp';
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
 * 1) localiza usuário dentro do CNPJ  2) bloqueio por tentativas  3) confere senha (bcrypt)
 * 4) empresa BLOQUEADA / licença vencida  5) se tiver 2 etapas, devolve um ticket e pede o código
 */
authRouter.post('/login', loginLimiter, async (req, res) => {
  const body = loginSchema.parse(req.body);
  const { rows } = await publicQuery('SELECT * FROM app.auth_lookup($1, $2)', [body.cnpj, body.username]);
  const u = rows[0];

  if (u?.locked_until && new Date(u.locked_until) > new Date()) {
    const min = Math.ceil((new Date(u.locked_until).getTime() - Date.now()) / 60000);
    throw new HttpError(423, 'USUARIO_BLOQUEADO', `Muitas tentativas erradas. Tente de novo em ${min} min ou peça ao administrador.`);
  }

  // Mesma mensagem para usuário inexistente e senha errada (não vaza quem existe).
  // Usuário inexistente também passa pelo bcrypt (tempo de resposta igual).
  const ok = await bcrypt.compare(body.password, u?.password_hash ?? DUMMY_HASH);
  if (!u || !ok) {
    if (u) {
      const r = (await publicQuery('SELECT * FROM app.login_attempt($1, false, $2)', [u.user_id, req.ip])).rows[0];
      const left = 5 - Number(r?.fails ?? 0);
      if (left <= 0) throw new HttpError(423, 'USUARIO_BLOQUEADO', 'Muitas tentativas erradas. Usuário bloqueado por 15 minutos.');
      if (left <= 2) throw new HttpError(401, 'CREDENCIAIS_INVALIDAS', `CNPJ, usuário ou senha incorretos. Restam ${left} tentativa(s).`);
    }
    throw new HttpError(401, 'CREDENCIAIS_INVALIDAS', 'CNPJ, usuário ou senha incorretos');
  }
  assertCanEnter(u);

  if (u.totp_enabled) {
    return res.json({ needsTotp: true, ticket: signTotpTicket(u.user_id, u.tenant_id), credits: CREDITS });
  }
  await publicQuery('SELECT * FROM app.login_attempt($1, true, $2)', [u.user_id, req.ip]);
  res.json(sessionPayload(u));
});

/** POST /auth/login/totp { ticket, code } — 2º passo: código do aplicativo autenticador */
authRouter.post('/login/totp', loginLimiter, async (req, res) => {
  const b = z.object({ ticket: z.string().min(10), code: z.string().trim().min(6).max(8) }).parse(req.body);
  const t = readTotpTicket(b.ticket);
  const sec = (await publicQuery('SELECT * FROM app.totp_secret_for($1)', [t.sub])).rows[0];
  if (!sec?.secret) throw new HttpError(401, 'TICKET_INVALIDO', 'Entre com a senha de novo');
  const step = verifyTotp(sec.secret, b.code, sec.last_step != null ? Number(sec.last_step) : null);
  if (step == null || !(await publicQuery('SELECT app.totp_mark_step($1, $2) AS ok', [t.sub, step])).rows[0]?.ok) {
    await publicQuery('SELECT * FROM app.login_attempt($1, false, $2)', [t.sub, req.ip]);
    throw new HttpError(401, 'CODIGO_INVALIDO', 'Código incorreto ou já usado. Confira o horário do celular.');
  }
  const u = (await publicQuery('SELECT * FROM app.auth_lookup_id($1)', [t.sub])).rows[0];
  if (!u) throw new HttpError(401, 'TICKET_INVALIDO', 'Entre com a senha de novo');
  assertCanEnter(u);
  await publicQuery('SELECT * FROM app.login_attempt($1, true, $2)', [u.user_id, req.ip]);
  res.json(sessionPayload(u));
});

function assertCanEnter(u: any) {
  if (!u.user_active) throw new HttpError(403, 'USUARIO_INATIVO', 'Usuário desativado');
  if (u.role !== 'SUPER_ADMIN') {
    if (u.tenant_status === 'BLOQUEADO')
      throw new HttpError(403, 'EMPRESA_BLOQUEADA', 'Acesso da empresa bloqueado. Contate o suporte IaHope-Technology.');
    if (String(u.license_expires_at) < today())
      throw new HttpError(403, 'LICENCA_EXPIRADA', 'Licença expirada. Contate o suporte IaHope-Technology.');
  }
}

function sessionPayload(u: any) {
  const token = signToken({ sub: u.user_id, tid: u.tenant_id, cnpj: u.cnpj, role: u.role, tv: u.token_version });
  return {
    token,
    user: {
      id: u.user_id, username: u.username, fullName: u.full_name, role: u.role,
      mustChangePassword: !!u.must_change_password, totpEnabled: !!u.totp_enabled,
    },
    tenant: {
      id: u.tenant_id,
      cnpj: u.cnpj,
      nomeFantasia: u.nome_fantasia ?? u.razao_social,
      razaoSocial: u.razao_social,
      logoUrl: absoluteUrl(u.logo_url),
      primaryColor: u.primary_color,
      licenseExpiresAt: u.license_expires_at,
      modules: u.modules ?? [],
      businessCategory: u.business_category ?? 'OUTRO',
      maxDiscountPct: Number(u.max_discount_pct ?? 10),
    },
    credits: CREDITS,
  };
}

// hash fixo só para gastar o mesmo tempo quando o usuário não existe
const DUMMY_HASH = '$2b$10$QYUKU9UAFCsNOFgXjbBoaeLXhD1WcUdEZAiM/CmtyZLxCebQOsP/C';

/** GET /auth/me — recarrega a sessão (ex.: após trocar a logo) */
authRouter.get('/me', requireAuth, async (req, res) => {
  const data = await db(req, async (c) => {
    const t = await c.query('SELECT * FROM app.tenants WHERE id = $1', [req.auth!.tid]);
    const u = await c.query(
      'SELECT id, username::text, full_name, role, must_change_password, totp_enabled FROM app.users WHERE id = $1',
      [req.auth!.sub],
    );
    return { t: t.rows[0], u: u.rows[0] };
  });
  res.json({
    user: {
      id: data.u.id, username: data.u.username, fullName: data.u.full_name, role: data.u.role,
      mustChangePassword: !!data.u.must_change_password, totpEnabled: !!data.u.totp_enabled,
    },
    tenant: {
      id: data.t.id,
      cnpj: data.t.cnpj,
      nomeFantasia: data.t.nome_fantasia ?? data.t.razao_social,
      razaoSocial: data.t.razao_social,
      logoUrl: absoluteUrl(data.t.logo_url),
      primaryColor: data.t.primary_color,
      licenseExpiresAt: data.t.license_expires_at,
      modules: data.t.modules ?? [],
      businessCategory: data.t.business_category ?? 'OUTRO',
      scaleConfig: data.t.scale_config,
      maxDiscountPct: Number(data.t.max_discount_pct ?? 10),
    },
    credits: CREDITS,
  });
});

const strictLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: true });

/** POST /auth/logout-all — encerra a sessão em todos os aparelhos (inclusive este) */
authRouter.post('/logout-all', requireAuth, async (req, res) => {
  await db(req, async (c) => {
    await c.query('UPDATE app.users SET token_version = token_version + 1 WHERE id = $1', [req.auth!.sub]);
    await audit(c, 'SAIR_DE_TODOS');
  });
  res.json({ ok: true });
});

/** POST /auth/totp/setup — gera um segredo novo (ainda desligado) e o link para o aplicativo */
authRouter.post('/totp/setup', requireAuth, strictLimiter, async (req, res) => {
  const secret = newTotpSecret();
  const r = await db(req, async (c) => {
    const u = (await c.query('SELECT username::text, totp_enabled FROM app.users WHERE id = $1', [req.auth!.sub])).rows[0];
    if (u.totp_enabled) throw new HttpError(409, 'JA_ATIVO', 'A verificação em duas etapas já está ligada');
    await c.query('UPDATE app.users SET totp_secret = $2 WHERE id = $1', [req.auth!.sub, secret]);
    return u;
  });
  res.json({ secret, otpauthUrl: otpauthUrl(secret, `${r.username}@${req.auth!.cnpj}`) });
});

/** POST /auth/totp/enable { code } — confirma o primeiro código e liga as 2 etapas */
authRouter.post('/totp/enable', requireAuth, strictLimiter, async (req, res) => {
  const b = z.object({ code: z.string().trim().min(6).max(8) }).parse(req.body);
  const user = await db(req, async (c) => {
    const u = (await c.query('SELECT * FROM app.users WHERE id = $1', [req.auth!.sub])).rows[0];
    if (!u?.totp_secret) throw new HttpError(409, 'SEM_SEGREDO', 'Comece a configuração de novo');
    const step = verifyTotp(u.totp_secret, b.code);
    if (step == null) throw new HttpError(422, 'CODIGO_INVALIDO', 'Código incorreto. Confira o horário do celular e tente de novo.');
    const nu = (
      await c.query('UPDATE app.users SET totp_enabled = true, totp_last_step = $2 WHERE id = $1 RETURNING *', [u.id, step])
    ).rows[0];
    await audit(c, '2FA_LIGADA');
    return nu;
  });
  // ligar as 2 etapas muda a versão do token → devolve um token novo para este aparelho
  res.json({ ok: true, token: signToken({ ...pick(req), tv: user.token_version }) });
});

/** POST /auth/totp/disable { password } — desliga (pede a senha) */
authRouter.post('/totp/disable', requireAuth, strictLimiter, async (req, res) => {
  const b = z.object({ password: z.string().min(1) }).parse(req.body);
  const user = await db(req, async (c) => {
    const u = (await c.query('SELECT * FROM app.users WHERE id = $1', [req.auth!.sub])).rows[0];
    if (!(await bcrypt.compare(b.password, u.password_hash))) throw new HttpError(422, 'SENHA_ATUAL', 'Senha incorreta');
    const nu = (
      await c.query('UPDATE app.users SET totp_enabled = false, totp_secret = NULL, totp_last_step = NULL WHERE id = $1 RETURNING *', [u.id])
    ).rows[0];
    await audit(c, '2FA_DESLIGADA');
    return nu;
  });
  res.json({ ok: true, token: signToken({ ...pick(req), tv: user.token_version }) });
});

const pick = (req: any) => ({ sub: req.auth.sub, tid: req.auth.tid, cnpj: req.auth.cnpj, role: req.auth.role });

/**
 * POST /auth/supervisor { username, password, action }
 * Gerente ou administrador da MESMA empresa autoriza uma ação do caixa
 * (desconto acima do limite, cancelamento de venda, troca). Vale 3 minutos.
 */
authRouter.post('/supervisor', requireAuth, strictLimiter, async (req, res) => {
  const b = z
    .object({
      username: z.string().trim().min(1),
      password: z.string().min(1),
      action: z.enum(['DESCONTO', 'CANCELAR_VENDA', 'TROCA']),
    })
    .parse(req.body);
  const u = (await publicQuery('SELECT * FROM app.auth_lookup($1, $2)', [req.auth!.cnpj, b.username])).rows[0];
  if (u?.locked_until && new Date(u.locked_until) > new Date()) {
    throw new HttpError(423, 'USUARIO_BLOQUEADO', 'Este gerente está bloqueado por tentativas erradas');
  }
  const ok = await bcrypt.compare(b.password, u?.password_hash ?? DUMMY_HASH);
  if (!u || !ok || u.tenant_id !== req.auth!.tid) {
    if (u) await publicQuery('SELECT * FROM app.login_attempt($1, false, $2)', [u.user_id, req.ip]);
    throw new HttpError(401, 'AUTORIZACAO_NEGADA', 'Usuário ou senha do gerente incorretos');
  }
  if (!u.user_active || !['ADMIN', 'GERENTE'].includes(u.role)) {
    throw new HttpError(403, 'AUTORIZACAO_NEGADA', 'Só gerente ou administrador pode autorizar');
  }
  await db(req, (c) => audit(c, 'AUTORIZACAO_GERENTE', { acao: b.action, gerente: u.username }));
  res.json({ token: signSupervisor({ sub: u.user_id, tid: u.tenant_id, act: b.action, name: u.full_name }), name: u.full_name });
});
