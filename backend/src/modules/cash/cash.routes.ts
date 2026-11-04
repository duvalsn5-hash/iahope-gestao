import { Router } from 'express';
import { z } from 'zod';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';

/**
 * Caixa do PDV: abertura, sangria, suprimento, fechamento e histórico.
 * Cada operador tem o próprio caixa; vender exige caixa aberto.
 */
export const cashRouter = Router();
cashRouter.use(requireAuth, requireModule('PDV'));

const num = (v: any) => (v == null ? null : Number(v));
const mapSummary = (s: any) =>
  s && {
    ...s,
    opening: num(s.opening),
    salesTotal: num(s.salesTotal),
    change: num(s.change),
    supply: num(s.supply),
    withdrawal: num(s.withdrawal),
    received: num(s.received),
    paidOut: num(s.paidOut),
    expectedCash: num(s.expectedCash),
    counted: num(s.counted),
    difference: num(s.difference),
    byMethod: Object.fromEntries(Object.entries(s.byMethod ?? {}).map(([k, v]) => [k, Number(v)])),
  };

/** GET /cash/current — caixa aberto do operador (ou { open: false }) */
cashRouter.get('/current', async (req, res) => {
  const r = await db(req, async (c) => {
    const id = (await c.query('SELECT app.current_cash_session() AS id')).rows[0].id;
    if (!id) return { open: false };
    const s = (await c.query('SELECT app.cash_summary($1) AS s', [id])).rows[0].s;
    const moves = (
      await c.query(
        'SELECT kind, amount, reason, created_at FROM app.cash_movements WHERE session_id = $1 ORDER BY created_at DESC',
        [id],
      )
    ).rows;
    return {
      open: true,
      summary: mapSummary(s),
      movements: moves.map((m: any) => ({ kind: m.kind, amount: Number(m.amount), reason: m.reason, createdAt: m.created_at })),
    };
  });
  res.json(r);
});

/** POST /cash/open { openingAmount } */
cashRouter.post('/open', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = z.object({ openingAmount: z.number().min(0) }).parse(req.body);
  const s = await db(req, async (c) => {
    const id = (await c.query('SELECT app.open_cash_session($1) AS id', [b.openingAmount])).rows[0].id;
    return (await c.query('SELECT app.cash_summary($1) AS s', [id])).rows[0].s;
  });
  res.status(201).json({ open: true, summary: mapSummary(s), movements: [] });
});

/** POST /cash/movements { kind: SANGRIA|SUPRIMENTO, amount, reason } */
cashRouter.post('/movements', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = z
    .object({ kind: z.enum(['SANGRIA', 'SUPRIMENTO']), amount: z.number().positive(), reason: z.string().max(200).optional() })
    .parse(req.body);
  await db(req, (c) => c.query('SELECT app.cash_movement($1, $2, $3)', [b.kind, b.amount, b.reason ?? null]));
  res.status(201).json({ ok: true });
});

/** POST /cash/close { countedAmount, notes } → resumo final com diferença */
cashRouter.post('/close', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = z.object({ countedAmount: z.number().min(0), notes: z.string().max(500).optional() }).parse(req.body);
  const s = await db(req, async (c) => (await c.query('SELECT app.close_cash_session($1, $2) AS s', [b.countedAmount, b.notes ?? null])).rows[0].s);
  res.json(mapSummary(s));
});

/** GET /cash/sessions?from=&to= — histórico de caixas (gestão) */
cashRouter.get('/sessions', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  const from = /^\d{4}-\d{2}-\d{2}$/.test(String(req.query.from)) ? String(req.query.from) : null;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(String(req.query.to)) ? String(req.query.to) : null;
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT s.id, s.status, s.opened_at, s.closed_at, s.opening_amount, s.expected_cash, s.closing_counted, s.difference,
                u.full_name AS operator,
                (SELECT coalesce(sum(total), 0) FROM app.sales WHERE cash_session_id = s.id AND status = 'FINALIZADA') AS sales_total,
                (SELECT count(*) FROM app.sales WHERE cash_session_id = s.id AND status = 'FINALIZADA') AS sales_count
           FROM app.cash_sessions s JOIN app.users u ON u.id = s.user_id
          WHERE ($1::date IS NULL OR s.opened_at >= $1::date)
            AND ($2::date IS NULL OR s.opened_at < $2::date + 1)
          ORDER BY s.opened_at DESC LIMIT 200`,
        [from, to],
      )
    ).rows,
  );
  res.json(
    rows.map((r: any) => ({
      id: r.id,
      status: r.status,
      operator: r.operator,
      openedAt: r.opened_at,
      closedAt: r.closed_at,
      opening: Number(r.opening_amount),
      expectedCash: num(r.expected_cash),
      counted: num(r.closing_counted),
      difference: num(r.difference),
      salesTotal: Number(r.sales_total),
      salesCount: Number(r.sales_count),
    })),
  );
});
