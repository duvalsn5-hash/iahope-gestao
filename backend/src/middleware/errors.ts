import { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

// Mapeia erros do PostgreSQL para respostas legíveis
const PG_ERRORS: Record<string, [number, string]> = {
  '23505': [409, 'Registro duplicado (SKU, código de barras, CNPJ ou usuário já existe)'],
  '23503': [409, 'Registro vinculado a outro dado'],
  '23514': [422, 'Dado inválido (verifique CNPJ, valores e campos obrigatórios)'],
  '42501': [403, 'Acesso negado para esta empresa'],
  P0001: [422, ''], // RAISE EXCEPTION das funções → mensagem original
};

export function errorHandler(err: any, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.code, message: err.message });
  }
  if (err instanceof ZodError) {
    return res.status(400).json({ error: 'VALIDACAO', message: 'Dados inválidos', issues: err.issues });
  }
  if (err?.code && PG_ERRORS[err.code]) {
    const [status, msg] = PG_ERRORS[err.code];
    return res.status(status).json({ error: 'BANCO', message: msg || err.message });
  }
  console.error(err);
  return res.status(500).json({ error: 'INTERNO', message: 'Erro interno do servidor' });
}
