import { Router } from 'express';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { isValidCnpj, isValidCpf, onlyDigits } from '../../utils/cnpj';

/** Clientes e fornecedores (núcleo — disponível em todos os planos) */
export const partnersRouter = Router();
partnersRouter.use(requireAuth);

export const mapPartner = (p: any) => ({
  id: p.id,
  kind: p.kind,
  doc: p.doc,
  name: p.name,
  tradeName: p.trade_name,
  ie: p.ie,
  phone: p.phone,
  email: p.email,
  zip: p.zip,
  street: p.street,
  number: p.number,
  district: p.district,
  city: p.city,
  state: p.state,
  creditLimit: Number(p.credit_limit),
  notes: p.notes,
  isActive: p.is_active,
  openReceivable: p.open_receivable != null ? Number(p.open_receivable) : undefined,
});

/** GET /partners?q=&kind=CLIENTE|FORNECEDOR&all=1 */
partnersRouter.get('/', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const kind = String(req.query.kind ?? '');
  const all = req.query.all === '1';
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT p.*,
                (SELECT coalesce(sum(f.amount - f.paid_amount), 0) FROM app.financial_entries f
                  WHERE f.partner_id = p.id AND f.kind = 'RECEBER' AND f.status IN ('ABERTO','PARCIAL')) AS open_receivable
           FROM app.partners p
          WHERE ($3 OR p.is_active)
            AND ($2 = '' OR p.kind::text = $2 OR p.kind = 'AMBOS')
            AND ($1 = '' OR p.name ILIKE '%' || $1 || '%' OR p.trade_name ILIKE '%' || $1 || '%'
                 OR p.doc LIKE regexp_replace($1, '\\D', '', 'g') || '%' AND regexp_replace($1, '\\D', '', 'g') <> '')
          ORDER BY p.is_active DESC, p.name LIMIT 300`,
        [q, kind, all],
      )
    ).rows,
  );
  res.json(rows.map(mapPartner));
});

const schema = z.object({
  kind: z.enum(['CLIENTE', 'FORNECEDOR', 'AMBOS']),
  doc: z
    .string()
    .transform(onlyDigits)
    .refine((d) => d === '' || isValidCpf(d) || isValidCnpj(d), 'CPF ou CNPJ inválido')
    .optional()
    .nullable(),
  name: z.string().trim().min(2).max(150),
  tradeName: z.string().trim().max(150).optional().nullable(),
  ie: z.string().trim().max(20).optional().nullable(),
  phone: z.string().trim().max(30).optional().nullable(),
  email: z.string().trim().email().optional().nullable().or(z.literal('')),
  zip: z.string().transform(onlyDigits).optional().nullable(),
  street: z.string().trim().max(150).optional().nullable(),
  number: z.string().trim().max(20).optional().nullable(),
  district: z.string().trim().max(80).optional().nullable(),
  city: z.string().trim().max(80).optional().nullable(),
  state: z.string().trim().length(2).toUpperCase().optional().nullable().or(z.literal('')),
  creditLimit: z.number().min(0).default(0),
  notes: z.string().max(1000).optional().nullable(),
  isActive: z.boolean().default(true),
});

const values = (b: z.infer<typeof schema>) => [
  b.kind, b.doc || null, b.name, b.tradeName || null, b.ie || null, b.phone || null, b.email || null, b.zip || null,
  b.street || null, b.number || null, b.district || null, b.city || null, b.state || null, b.creditLimit, b.notes || null,
  b.isActive,
];

/** POST /partners — caixa também pode cadastrar cliente rápido no PDV */
partnersRouter.post('/', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = schema.parse(req.body);
  const p = await db(req, async (c) =>
    (
      await c.query(
        `INSERT INTO app.partners (kind, doc, name, trade_name, ie, phone, email, zip, street, number, district, city, state,
                                   credit_limit, notes, is_active)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) RETURNING *`,
        values(b),
      )
    ).rows[0],
  );
  res.status(201).json(mapPartner(p));
});

/** PUT /partners/:id */
partnersRouter.put('/:id', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  const b = schema.parse(req.body);
  const p = await db(req, async (c) =>
    (
      await c.query(
        `UPDATE app.partners SET kind=$2, doc=$3, name=$4, trade_name=$5, ie=$6, phone=$7, email=$8, zip=$9, street=$10,
                number=$11, district=$12, city=$13, state=$14, credit_limit=$15, notes=$16, is_active=$17
          WHERE id = $1 RETURNING *`,
        [req.params.id, ...values(b)],
      )
    ).rows[0],
  );
  if (!p) throw new HttpError(404, 'NAO_ENCONTRADO', 'Cadastro não encontrado');
  res.json(mapPartner(p));
});
