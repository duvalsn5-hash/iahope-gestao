import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { DbContext, publicQuery, withTenant } from '../db/pool';
import { HttpError } from './errors';
import { PoolClient } from 'pg';

export type Role = 'SUPER_ADMIN' | 'ADMIN' | 'GERENTE' | 'OPERADOR' | 'CAIXA' | 'MECANICO';

export interface JwtPayload {
  sub: string;   // user id
  tid: string;   // tenant id
  cnpj: string;
  role: Role;
  tv?: number;   // versão do token (trocar senha / "sair de todos" invalida os antigos)
}

/** Token de autorização do gerente (desconto acima do limite, cancelamento pelo caixa). */
export interface SupervisorPayload {
  sub: string;
  tid: string;
  purpose: 'sup';
  act: SupervisorAction;
  name: string;
}
export type SupervisorAction = 'DESCONTO' | 'CANCELAR_VENDA' | 'TROCA';

/** Módulos contratáveis (o Master liga/desliga por empresa). */
export type Module = 'PDV' | 'PRODUTIVIDADE' | 'FINANCEIRO' | 'COMPRAS' | 'BALANCA' | 'OFICINA' | 'MODA' | 'ESTAMPARIA';
export const ALL_MODULES: Module[] = ['PDV', 'PRODUTIVIDADE', 'FINANCEIRO', 'COMPRAS', 'BALANCA', 'OFICINA', 'MODA', 'ESTAMPARIA'];

declare global {
  namespace Express {
    interface Request {
      auth?: JwtPayload & { modules: string[]; mustChangePassword: boolean };
    }
  }
}

export function signToken(p: JwtPayload) {
  return jwt.sign(p, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN as jwt.SignOptions['expiresIn'], algorithm: 'HS256' });
}

/** Ticket curto entre a senha e o código de 2 etapas (5 min). */
export const signTotpTicket = (userId: string, tid: string) =>
  jwt.sign({ sub: userId, tid, purpose: 'totp' }, env.JWT_SECRET, { expiresIn: '5m', algorithm: 'HS256' });

export function readTotpTicket(t: string): { sub: string; tid: string } {
  try {
    const p = jwt.verify(t, env.JWT_SECRET, { algorithms: ['HS256'] }) as any;
    if (p.purpose !== 'totp') throw new Error();
    return { sub: p.sub, tid: p.tid };
  } catch {
    throw new HttpError(401, 'TICKET_INVALIDO', 'Tempo esgotado — entre com a senha de novo');
  }
}

export const signSupervisor = (p: Omit<SupervisorPayload, 'purpose'>) =>
  jwt.sign({ ...p, purpose: 'sup' }, env.JWT_SECRET, { expiresIn: '3m', algorithm: 'HS256' });

/**
 * Autorização do gerente enviada no cabeçalho X-Supervisor-Token.
 * Vale só para a mesma empresa e para a ação pedida; dura 3 minutos.
 */
export function supervisorFrom(req: Request, action: SupervisorAction): SupervisorPayload | null {
  const t = req.headers['x-supervisor-token'];
  if (typeof t !== 'string' || !t) return null;
  try {
    const p = jwt.verify(t, env.JWT_SECRET, { algorithms: ['HS256'] }) as SupervisorPayload;
    if (p.purpose !== 'sup' || p.tid !== req.auth?.tid || p.act !== action) return null;
    return p;
  } catch {
    return null;
  }
}

/** Rotas liberadas enquanto o usuário ainda precisa trocar a senha inicial. */
const PASSWORD_CHANGE_ALLOWED = ['/auth/me', '/users/me/password', '/auth/logout-all'];

const REASONS: Record<string, string> = {
  EMPRESA_BLOQUEADA: 'Acesso da empresa bloqueado pelo Administrador Master',
  LICENCA_EXPIRADA: 'Licença da empresa expirada',
  USUARIO_INATIVO: 'Usuário desativado',
  USUARIO_INEXISTENTE: 'Sessão inválida',
};

/**
 * Valida o JWT e, A CADA REQUISIÇÃO, confere no banco se a empresa continua
 * ativa e com licença válida. Bloqueio feito pelo ADM Master derruba a sessão
 * imediatamente, sem esperar o token expirar.
 */
export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return next(new HttpError(401, 'NAO_AUTENTICADO', 'Token ausente'));

  let payload: JwtPayload;
  try {
    payload = jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] }) as JwtPayload;
    if ((payload as any).purpose) throw new Error('token de outro tipo');
  } catch {
    return next(new HttpError(401, 'TOKEN_INVALIDO', 'Sessão expirada, faça login novamente'));
  }

  const { rows } = await publicQuery(
    'SELECT ok, reason, modules, token_version, must_change_password FROM app.session_check($1, $2)',
    [payload.sub, payload.tid],
  );
  const check = rows[0];
  if (!check?.ok) {
    const reason = check?.reason ?? 'USUARIO_INEXISTENTE';
    return next(new HttpError(403, reason, REASONS[reason] ?? 'Acesso negado'));
  }
  if (payload.tv !== check.token_version) {
    return next(new HttpError(401, 'SESSAO_ENCERRADA', 'Sua sessão foi encerrada (senha trocada ou saída de todos os aparelhos). Entre de novo.'));
  }
  req.auth = { ...payload, modules: check.modules ?? [], mustChangePassword: !!check.must_change_password };
  if (req.auth.mustChangePassword && !PASSWORD_CHANGE_ALLOWED.includes(req.originalUrl.split('?')[0])) {
    return next(new HttpError(403, 'TROCAR_SENHA', 'Troque a senha inicial para continuar'));
  }
  next();
}

export function requireRole(...roles: Role[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.auth || !roles.includes(req.auth.role)) {
      return next(new HttpError(403, 'SEM_PERMISSAO', 'Seu perfil não tem acesso a esta função'));
    }
    next();
  };
}

/**
 * Bloqueia rotas de módulos que a empresa não contratou.
 * O Master (SUPER_ADMIN) passa sempre, para dar suporte.
 */
export function requireModule(module: Module) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (req.auth?.role === 'SUPER_ADMIN' || req.auth?.modules.includes(module)) return next();
    next(new HttpError(403, 'MODULO_INATIVO', `O módulo ${module} não está ativo para esta empresa`));
  };
}

export function ctxOf(req: Request): DbContext {
  return { tenantId: req.auth!.tid, userId: req.auth!.sub, role: req.auth!.role };
}

/** Atalho: roda a consulta no contexto RLS do usuário logado. */
export function db<T>(req: Request, fn: (c: PoolClient) => Promise<T>) {
  return withTenant(ctxOf(req), fn);
}
