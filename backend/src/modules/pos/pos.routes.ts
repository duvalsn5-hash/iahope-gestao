import { Router } from 'express';
import { z } from 'zod';
import { CREDITS } from '../../config/env';
import { db, requireAuth, requireModule, requireRole, supervisorFrom } from '../../middleware/auth';
import { audit } from '../../security/audit';
import { HttpError } from '../../middleware/errors';
import { absoluteUrl } from '../auth/auth.routes';

/** Ponto de Venda */
export const posRouter = Router();
posRouter.use(requireAuth, requireModule('PDV'));

const closeSchema = z.object({
  items: z.array(z.object({ productId: z.string().uuid(), qty: z.number().positive() })).min(1),
  payments: z.array(z.object({
    method: z.enum(['DINHEIRO', 'PIX', 'DEBITO', 'CREDITO', 'OUTROS', 'PRAZO', 'VALE']),
    amount: z.number().positive(),
    voucher: z.string().trim().max(20).optional(), // código do vale-troca (method VALE)
  })).min(1),
  discount: z.number().min(0).default(0),
  customerDoc: z.string().optional(),
  customerId: z.string().uuid().optional(),
  dueDays: z.number().int().min(0).max(365).default(30), // vencimento da venda a prazo
});

export async function loadReceipt(c: any, saleId: string) {
  const sale = (
    await c.query(
      `SELECT s.*, u.full_name AS cashier_name, t.razao_social, t.nome_fantasia, t.cnpj, t.logo_url,
              cu.name AS customer_name
         FROM app.sales s
         JOIN app.tenants t ON t.id = s.tenant_id
         LEFT JOIN app.users u ON u.id = s.cashier_id
         LEFT JOIN app.partners cu ON cu.id = s.customer_id
        WHERE s.id = $1`,
      [saleId],
    )
  ).rows[0];
  if (!sale) throw new HttpError(404, 'NAO_ENCONTRADO', 'Venda não encontrada');
  const items = (await c.query('SELECT description, qty, unit_price, total FROM app.sale_items WHERE sale_id = $1 ORDER BY id', [saleId])).rows;
  const payments = (await c.query('SELECT method, amount FROM app.sale_payments WHERE sale_id = $1 ORDER BY id', [saleId])).rows;
  return {
    id: sale.id,
    number: Number(sale.sale_number),
    status: sale.status,
    createdAt: sale.created_at,
    cashier: sale.cashier_name,
    customer: sale.customer_name ? { name: sale.customer_name, doc: sale.customer_doc } : null,
    company: {
      name: sale.nome_fantasia ?? sale.razao_social,
      razaoSocial: sale.razao_social,
      cnpj: sale.cnpj,
      logoUrl: absoluteUrl(sale.logo_url), // logo impressa no cupom
    },
    items: items.map((i: any) => ({ description: i.description, qty: Number(i.qty), unitPrice: Number(i.unit_price), total: Number(i.total) })),
    payments: payments.map((p: any) => ({ method: p.method, amount: Number(p.amount) })),
    subtotal: Number(sale.subtotal),
    discount: Number(sale.discount),
    total: Number(sale.total),
    paid: Number(sale.paid),
    change: Number(sale.change_due),
    footer: CREDITS,
  };
}

/**
 * POST /pos/sales — fecha a venda.
 * Tudo numa transação no banco (app.close_sale): trava os produtos, valida
 * estoque, grava itens/pagamentos, baixa estoque e calcula troco.
 */
posRouter.post('/sales', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = closeSchema.parse(req.body);
  const receipt = await db(req, async (c) => {
    // desconto acima do limite da empresa: caixa precisa da autorização do gerente
    if (b.discount > 0) {
      const lim = (
        await c.query(
          `SELECT t.max_discount_pct,
                  (SELECT coalesce(sum(p.price * x.qty), 0) FROM app.products p
                     JOIN jsonb_to_recordset($2::jsonb) AS x(product_id uuid, qty numeric) ON x.product_id = p.id) AS subtotal
             FROM app.tenants t WHERE t.id = $1`,
          [req.auth!.tid, JSON.stringify(b.items.map((i) => ({ product_id: i.productId, qty: i.qty })))],
        )
      ).rows[0];
      const pct = Number(lim.subtotal) > 0 ? (b.discount / Number(lim.subtotal)) * 100 : 100;
      if (pct > Number(lim.max_discount_pct) + 0.001) {
        const sup = req.auth!.role === 'CAIXA' ? supervisorFrom(req, 'DESCONTO') : { name: 'próprio gestor' };
        if (!sup) {
          throw new HttpError(403, 'PRECISA_GERENTE',
            `Desconto de ${pct.toFixed(1)}% passa do limite de ${Number(lim.max_discount_pct)}% — precisa da autorização do gerente`);
        }
        await audit(c, 'DESCONTO_ACIMA_LIMITE', { desconto: b.discount, percentual: Math.round(pct * 10) / 10, autorizado_por: sup.name });
      }
    }
    const { rows } = await c.query('SELECT app.close_sale($1::jsonb, $2::jsonb, $3, $4, false, $5, $6) AS id', [
      JSON.stringify(b.items.map((i) => ({ product_id: i.productId, qty: i.qty }))),
      JSON.stringify(b.payments),
      b.discount,
      b.customerDoc ?? null,
      b.customerId ?? null,
      b.dueDays,
    ]);
    return loadReceipt(c, rows[0].id);
  });
  res.status(201).json(receipt);
});

/** GET /pos/sales/:id — reimpressão de cupom */
posRouter.get('/sales/:id', async (req, res) => {
  res.json(await db(req, (c) => loadReceipt(c, String(req.params.id))));
});

/** POST /pos/sales/:id/cancel — cancela e devolve estoque */
posRouter.post('/sales/:id/cancel', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const sup = req.auth!.role === 'CAIXA' ? supervisorFrom(req, 'CANCELAR_VENDA') : null;
  if (req.auth!.role === 'CAIXA' && !sup) {
    throw new HttpError(403, 'PRECISA_GERENTE', 'Cancelar venda precisa da autorização do gerente');
  }
  await db(req, async (c) => {
    const s = (await c.query('SELECT sale_number, total FROM app.sales WHERE id = $1', [req.params.id])).rows[0];
    await c.query('SELECT app.cancel_sale($1)', [req.params.id]);
    await audit(c, 'VENDA_CANCELADA', { venda: s?.sale_number, total: Number(s?.total ?? 0), autorizado_por: sup?.name ?? null });
  });
  res.json({ ok: true });
});

/** GET /pos/vouchers/:code — confere saldo do vale-troca antes de usar */
posRouter.get('/vouchers/:code', async (req, res) => {
  const v = await db(req, async (c) =>
    (
      await c.query(
        `SELECT s.code, s.amount, s.balance, s.expires_at, p.name AS customer_name
           FROM app.store_credits s LEFT JOIN app.partners p ON p.id = s.customer_id
          WHERE upper(s.code) = upper($1)`,
        [String(req.params.code).trim()],
      )
    ).rows[0],
  );
  if (!v) throw new HttpError(404, 'VALE_NAO_ENCONTRADO', 'Vale-troca não encontrado');
  res.json({
    code: v.code,
    amount: Number(v.amount),
    balance: Number(v.balance),
    expiresAt: v.expires_at,
    expired: v.expires_at != null && String(v.expires_at) < new Date().toISOString().slice(0, 10),
    customerName: v.customer_name,
  });
});

/** GET /pos/summary — resumo do dia para o caixa */
posRouter.get('/summary', async (req, res) => {
  const r = await db(req, async (c) =>
    (
      await c.query(
        `SELECT count(*)::int AS sales, coalesce(sum(total), 0)::float AS total,
                coalesce((SELECT value FROM app.tenant_counters WHERE name = 'sale'), 0)::int + 1 AS next_number
           FROM app.sales WHERE status = 'FINALIZADA' AND created_at >= date_trunc('day', now() AT TIME ZONE 'America/Fortaleza') AT TIME ZONE 'America/Fortaleza'`,
      )
    ).rows[0],
  );
  res.json({ sales: r.sales, total: r.total, nextNumber: r.next_number });
});
