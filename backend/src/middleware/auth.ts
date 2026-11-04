import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { DbContext, publicQuery, withTenant } from '../db/pool';
import { HttpError } from './errors';
import { PoolClient } from 'pg';

export type Role = 'SUPER_ADMIN' | 'ADMIN' | 'GERENTE' | 'OPERADOR' | 'CAIXA';

export interface JwtPayload {
  sub: string;   // user id
  tid: string;   // tenant id
  cnpj: string;
  role: Role;
}

declare global {
  namespace Express {
    interface Request {
      auth?: JwtPayload;
    }
  }
}

export function signToken(p: JwtPayload) {
  return jwt.sign(p, env.JWT_SECRET, { expiresIn: env.JWT_EXPIRES_IN as jwt.SignOptions['expiresIn'] });
}

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
    payload = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
  } catch {
    return next(new HttpError(401, 'TOKEN_INVALIDO', 'Sessão expirada, faça login novamente'));
  }

  const { rows } = await publicQuery('SELECT ok, reason FROM app.session_check($1, $2)', [payload.sub, payload.tid]);
  const check = rows[0];
  if (!check?.ok) {
    const reason = check?.reason ?? 'USUARIO_INEXISTENTE';
    return next(new HttpError(403, reason, REASONS[reason] ?? 'Acesso negado'));
  }
  req.auth = payload;
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

export function ctxOf(req: Request): DbContext {
  return { tenantId: req.auth!.tid, userId: req.auth!.sub, role: req.auth!.role };
}

/** Atalho: roda a consulta no contexto RLS do usuário logado. */
export function db<T>(req: Request, fn: (c: PoolClient) => Promise<T>) {
  return withTenant(ctxOf(req), fn);
}
