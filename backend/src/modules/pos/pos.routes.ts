import { Router } from 'express';
import { z } from 'zod';
import { CREDITS } from '../../config/env';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { absoluteUrl } from '../auth/auth.routes';

/** Ponto de Venda */
export const posRouter = Router();
posRouter.use(requireAuth, requireModule('PDV'));

const closeSchema = z.object({
  items: z.array(z.object({ productId: z.string().uuid(), qty: z.number().positive() })).min(1),
  payments: z.array(z.object({
    method: z.enum(['DINHEIRO', 'PIX', 'DEBITO', 'CREDITO', 'OUTROS', 'PRAZO']),
    amount: z.number().positive(),
  })).min(1),
  discount: z.number().min(0).default(0),
  customerDoc: z.string().optional(),
  customerId: z.string().uuid().optional(),
  dueDays: z.number().int().min(0).max(365).default(30), // vencimento da venda a prazo
});

async function loadReceipt(c: any, saleId: string) {
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
posRouter.post('/sales/:id/cancel', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  await db(req, (c) => c.query('SELECT app.cancel_sale($1)', [req.params.id]));
  res.json({ ok: true });
});

/** GET /pos/summary — resumo do dia para o caixa */
posRouter.get('/summary', async (req, res) => {
  const r = await db(req, async (c) =>
    (
      await c.query(
        `SELECT count(*)::int AS sales, coalesce(sum(total), 0)::float AS total
           FROM app.sales WHERE status = 'FINALIZADA' AND created_at >= date_trunc('day', now() AT TIME ZONE 'America/Fortaleza') AT TIME ZONE 'America/Fortaleza'`,
      )
    ).rows[0],
  );
  res.json(r);
});
