import { Router } from 'express';
import { z } from 'zod';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';

/** Contas a pagar e a receber */
export const financeRouter = Router();
financeRouter.use(requireAuth, requireModule('FINANCEIRO'), requireRole('ADMIN', 'GERENTE'));

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const dateOrNull = (v: unknown) => (DATE.test(String(v)) ? String(v) : null);

const mapEntry = (e: any) => ({
  id: e.id,
  kind: e.kind,
  partnerId: e.partner_id,
  partnerName: e.partner_name,
  description: e.description,
  category: e.category,
  document: e.document,
  issueDate: e.issue_date,
  dueDate: e.due_date,
  amount: Number(e.amount),
  paidAmount: Number(e.paid_amount),
  balance: Number(e.amount) - Number(e.paid_amount),
  paidAt: e.paid_at,
  // VENCIDO é calculado: aberto/parcial com vencimento passado
  status: ['ABERTO', 'PARCIAL'].includes(e.status) && e.overdue ? 'VENCIDO' : e.status,
  origin: e.origin,
  paymentMethod: e.payment_method,
});

/**
 * GET /finance/entries?kind=PAGAR|RECEBER&status=ABERTOS|VENCIDOS|PAGOS|TODOS&from=&to=&q=
 * Datas filtram pelo vencimento.
 */
financeRouter.get('/entries', async (req, res) => {
  const kind = String(req.query.kind ?? 'RECEBER') === 'PAGAR' ? 'PAGAR' : 'RECEBER';
  const status = String(req.query.status ?? 'ABERTOS');
  const q = String(req.query.q ?? '').trim();
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT f.*, p.name AS partner_name, (f.due_date < current_date) AS overdue
           FROM app.financial_entries f LEFT JOIN app.partners p ON p.id = f.partner_id
          WHERE f.kind = $1
            AND CASE $2
                  WHEN 'ABERTOS'  THEN f.status IN ('ABERTO','PARCIAL')
                  WHEN 'VENCIDOS' THEN f.status IN ('ABERTO','PARCIAL') AND f.due_date < current_date
                  WHEN 'PAGOS'    THEN f.status = 'PAGO'
                  ELSE f.status <> 'CANCELADO' END
            AND ($3::date IS NULL OR f.due_date >= $3::date)
            AND ($4::date IS NULL OR f.due_date <= $4::date)
            AND ($5 = '' OR f.description ILIKE '%' || $5 || '%' OR p.name ILIKE '%' || $5 || '%' OR f.document = $5)
          ORDER BY CASE WHEN f.status IN ('ABERTO','PARCIAL') THEN 0 ELSE 1 END, f.due_date, f.created_at
          LIMIT 500`,
        [kind, status, dateOrNull(req.query.from), dateOrNull(req.query.to), q],
      )
    ).rows,
  );
  res.json(rows.map(mapEntry));
});

/** GET /finance/summary — totais em aberto para o painel */
financeRouter.get('/summary', async (req, res) => {
  const r = await db(req, async (c) =>
    (
      await c.query(`
        SELECT kind,
               coalesce(sum(amount - paid_amount), 0) AS open_total,
               coalesce(sum(amount - paid_amount) FILTER (WHERE due_date < current_date), 0) AS overdue,
               coalesce(sum(amount - paid_amount) FILTER (WHERE due_date = current_date), 0) AS due_today,
               coalesce(sum(amount - paid_amount) FILTER (WHERE due_date > current_date AND due_date <= current_date + 7), 0) AS next7
          FROM app.financial_entries
         WHERE status IN ('ABERTO','PARCIAL')
         GROUP BY kind`)
    ).rows,
  );
  const pick = (k: string) => {
    const x = r.find((y: any) => y.kind === k);
    return {
      open: Number(x?.open_total ?? 0),
      overdue: Number(x?.overdue ?? 0),
      dueToday: Number(x?.due_today ?? 0),
      next7: Number(x?.next7 ?? 0),
    };
  };
  res.json({ receivable: pick('RECEBER'), payable: pick('PAGAR') });
});

const createSchema = z.object({
  kind: z.enum(['PAGAR', 'RECEBER']),
  partnerId: z.string().uuid().optional().nullable(),
  description: z.string().trim().min(2).max(200),
  category: z.string().trim().max(60).optional().nullable(),
  document: z.string().trim().max(40).optional().nullable(),
  dueDate: z.string().regex(DATE),
  amount: z.number().positive(),
  // parcelamento: gera N lançamentos mensais com o valor dividido
  installments: z.number().int().min(1).max(60).default(1),
});

/** POST /finance/entries — lançamento manual (com parcelamento opcional) */
financeRouter.post('/entries', async (req, res) => {
  const b = createSchema.parse(req.body);
  const rows = await db(req, async (c) => {
    const n = b.installments;
    const base = Math.floor((b.amount / n) * 100) / 100;
    const out = [];
    for (let i = 0; i < n; i++) {
      const value = i === n - 1 ? Math.round((b.amount - base * (n - 1)) * 100) / 100 : base;
      const r = await c.query(
        `INSERT INTO app.financial_entries (kind, partner_id, description, category, document, due_date, amount, created_by)
         VALUES ($1, $2, $3, $4, $5, ($6::date + make_interval(months => $7))::date, $8, app.current_user_id())
         RETURNING *, (due_date < current_date) AS overdue`,
        [b.kind, b.partnerId ?? null, n > 1 ? `${b.description} (${i + 1}/${n})` : b.description, b.category ?? null,
          b.document ?? null, b.dueDate, i, value],
      );
      out.push(r.rows[0]);
    }
    return out;
  });
  res.status(201).json(rows.map(mapEntry));
});

/** POST /finance/entries/:id/settle { amount, method, fromCash } — baixa total ou parcial */
financeRouter.post('/entries/:id/settle', async (req, res) => {
  const b = z
    .object({
      amount: z.number().positive(),
      method: z.enum(['DINHEIRO', 'PIX', 'DEBITO', 'CREDITO', 'BOLETO', 'TRANSFERENCIA', 'OUTROS']),
      fromCash: z.boolean().default(false),
    })
    .parse(req.body);
  if (b.fromCash && b.method !== 'DINHEIRO') throw new HttpError(400, 'VALIDACAO', 'Só dinheiro passa pela gaveta do caixa');
  await db(req, (c) => c.query('SELECT app.settle_entry($1, $2, $3, $4)', [req.params.id, b.amount, b.method, b.fromCash]));
  res.json({ ok: true });
});

/** POST /finance/entries/:id/cancel */
financeRouter.post('/entries/:id/cancel', async (req, res) => {
  const r = await db(req, (c) =>
    c.query(`UPDATE app.financial_entries SET status = 'CANCELADO' WHERE id = $1 AND paid_amount = 0 AND status <> 'CANCELADO'`, [
      req.params.id,
    ]),
  );
  if (!r.rowCount) throw new HttpError(422, 'NAO_CANCELAVEL', 'Lançamento não encontrado ou já tem pagamento registrado');
  res.json({ ok: true });
});
