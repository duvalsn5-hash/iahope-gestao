import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { absoluteUrl } from '../auth/auth.routes';
import { audit } from '../../security/audit';
import { LogoExt, logoStorage } from '../../storage/logo-storage';

/**
 * Configurações da empresa logada (White-Label).
 * Onde a logo fica (banco, disco ou S3/R2) é definido por STORAGE_DRIVER —
 * ver src/storage/logo-storage.ts.
 */
export const companyRouter = Router();
companyRouter.use(requireAuth);

const ALLOWED = new Map([
  ['image/png', '.png'],
  ['image/jpeg', '.jpg'],
  ['image/webp', '.webp'],
]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 }, // 2 MB
  fileFilter: (_req, file, cb) =>
    ALLOWED.has(file.mimetype) ? cb(null, true) : cb(new HttpError(415, 'FORMATO', 'Use PNG, JPG ou WEBP')),
});

// Confere a "assinatura" do arquivo — não confia só no mimetype enviado
function sniff(buf: Buffer): LogoExt | null {
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return '.png';
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return '.jpg';
  if (buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return '.webp';
  return null;
}

/** GET /company — dados da própria empresa */
companyRouter.get('/', async (req, res) => {
  const t = await db(req, async (c) => (await c.query('SELECT * FROM app.tenants WHERE id = $1', [req.auth!.tid])).rows[0]);
  res.json({
    id: t.id,
    cnpj: t.cnpj,
    razaoSocial: t.razao_social,
    nomeFantasia: t.nome_fantasia,
    logoUrl: absoluteUrl(t.logo_url),
    primaryColor: t.primary_color,
    licenseExpiresAt: t.license_expires_at,
    status: t.status,
    modules: t.modules ?? [],
    scaleConfig: t.scale_config,
  });
});

/** POST /company/logo (multipart, campo "logo") — upload e retorno da URL */
companyRouter.post('/logo', requireRole('ADMIN', 'SUPER_ADMIN'), upload.single('logo'), async (req, res) => {
  if (!req.file) throw new HttpError(400, 'SEM_ARQUIVO', 'Envie o arquivo no campo "logo"');
  const ext = sniff(req.file.buffer);
  if (!ext) throw new HttpError(415, 'FORMATO', 'Arquivo não é uma imagem válida');

  const file = req.file;
  const url = await db(req, async (c) => {
    const u = await logoStorage.save(c, req.auth!.tid, file.buffer, ext);
    await c.query('UPDATE app.tenants SET logo_url = $1 WHERE id = $2', [u, req.auth!.tid]);
    return u;
  });
  res.json({ logoUrl: absoluteUrl(url) });
});

/** DELETE /company/logo */
companyRouter.delete('/logo', requireRole('ADMIN', 'SUPER_ADMIN'), async (req, res) => {
  await db(req, async (c) => {
    await logoStorage.remove(c, req.auth!.tid);
    await c.query('UPDATE app.tenants SET logo_url = NULL WHERE id = $1', [req.auth!.tid]);
  });
  res.json({ logoUrl: null });
});

const brandSchema = z.object({
  nomeFantasia: z.string().trim().min(2).optional(),
  primaryColor: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
});

/**
 * Etiqueta de balança (EAN-13 começando com o prefixo, normalmente "2"):
 *   prefixo(1) + código do produto(codeLength) + … + valor(valueLength) + dígito verificador(1)
 * valueType: PRECO = total em centavos · PESO = gramas
 */
export const scaleSchema = z
  .object({
    prefix: z.string().regex(/^\d$/),
    codeLength: z.number().int().min(4).max(6),
    valueLength: z.number().int().min(5).max(6),
    valueType: z.enum(['PRECO', 'PESO']),
  })
  .refine((c) => 1 + c.codeLength <= 12 - c.valueLength, 'Código e valor não cabem em 13 dígitos');

/** PUT /company/scale — configuração da etiqueta de balança */
companyRouter.put('/scale', requireRole('ADMIN', 'SUPER_ADMIN'), async (req, res) => {
  const cfg = scaleSchema.parse(req.body);
  await db(req, (c) => c.query('UPDATE app.tenants SET scale_config = $2 WHERE id = $1', [req.auth!.tid, cfg]));
  res.json(cfg);
});

/** PATCH /company — nome fantasia e cor da marca */
companyRouter.patch('/', requireRole('ADMIN', 'SUPER_ADMIN'), async (req, res) => {
  const b = brandSchema.parse(req.body);
  const t = await db(req, async (c) =>
    (
      await c.query(
        `UPDATE app.tenants SET nome_fantasia = coalesce($2, nome_fantasia), primary_color = coalesce($3, primary_color)
          WHERE id = $1 RETURNING nome_fantasia, primary_color`,
        [req.auth!.tid, b.nomeFantasia ?? null, b.primaryColor ?? null],
      )
    ).rows[0],
  );
  res.json({ nomeFantasia: t.nome_fantasia, primaryColor: t.primary_color });
});

/** PUT /company/security { maxDiscountPct } — regras de segurança da empresa */
companyRouter.put('/security', requireRole('ADMIN'), async (req, res) => {
  const b = z.object({ maxDiscountPct: z.number().min(0).max(100) }).parse(req.body);
  await db(req, async (c) => {
    await c.query('UPDATE app.tenants SET max_discount_pct = $2 WHERE id = $1', [req.auth!.tid, b.maxDiscountPct]);
    await audit(c, 'LIMITE_DESCONTO', { percentual: b.maxDiscountPct });
  });
  res.json({ maxDiscountPct: b.maxDiscountPct });
});

const ACTIONS: Record<string, string> = {
  LOGIN_OK: 'Entrou no sistema',
  LOGIN_FALHA: 'Senha errada',
  SAIR_DE_TODOS: 'Saiu de todos os aparelhos',
  '2FA_LIGADA': 'Ligou a verificação em 2 etapas',
  '2FA_DESLIGADA': 'Desligou a verificação em 2 etapas',
  SENHA_ALTERADA: 'Trocou a própria senha',
  USUARIO_CRIADO: 'Cadastrou usuário',
  USUARIO_ALTERADO: 'Alterou usuário',
  AUTORIZACAO_GERENTE: 'Gerente autorizou',
  DESCONTO_ACIMA_LIMITE: 'Desconto acima do limite',
  VENDA_CANCELADA: 'Cancelou venda',
  TROCA_VALE: 'Troca com vale',
  DEVOLUCAO_DINHEIRO: 'Devolução em dinheiro',
  CAIXA_FECHADO: 'Fechou o caixa',
  LIMITE_DESCONTO: 'Mudou o limite de desconto',
  TENANT_CRIADO: 'Empresa criada (Master)',
  TENANT_ATIVADO: 'Acesso reativado (Master)',
  TENANT_BLOQUEADO: 'Acesso bloqueado (Master)',
  TENANT_ATUALIZADO: 'Licença alterada (Master)',
  TENANT_MODULOS: 'Módulos alterados (Master)',
  RAMO_ALTERADO: 'Ramo alterado (Master)',
};

/** GET /company/audit?action=&days=30 — quem fez o quê (administrador e gerente) */
companyRouter.get('/audit', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  const action = String(req.query.action ?? '');
  const days = Math.min(Math.max(Number(req.query.days ?? 30) || 30, 1), 365);
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT a.id, a.action, a.details, a.created_at, u.full_name, u.username::text
           FROM app.audit_log a LEFT JOIN app.users u ON u.id = a.user_id
          WHERE a.tenant_id = $1 AND a.created_at >= now() - make_interval(days => $3)
            AND ($2 = '' OR a.action = $2)
          ORDER BY a.created_at DESC LIMIT 500`,
        [req.auth!.tid, action, days],
      )
    ).rows,
  );
  res.json(rows.map((r: any) => ({
    id: Number(r.id),
    action: r.action,
    label: ACTIONS[r.action] ?? r.action,
    details: r.details ?? {},
    user: r.full_name ?? r.username ?? null,
    at: r.created_at,
  })));
});
