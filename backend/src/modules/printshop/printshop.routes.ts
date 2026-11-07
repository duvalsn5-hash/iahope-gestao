import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { sniffImage } from '../../utils/image';
import { absoluteUrl } from '../auth/auth.routes';
import { loadReceipt } from '../pos/pos.routes';

/**
 * Módulo ESTAMPARIA (personalizados): pedidos sob encomenda com técnica,
 * grade de tamanhos por item, arte, sinal, prazo e fila de produção.
 */
export const printshopRouter = Router();
printshopRouter.use(requireAuth, requireModule('ESTAMPARIA'));

const STAFF = ['ADMIN', 'GERENTE', 'CAIXA', 'OPERADOR'] as const;
const MANAGE = ['ADMIN', 'GERENTE'] as const;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const OPEN = ['ORCAMENTO', 'APROVADO', 'PRODUCAO', 'PRONTO'];
const TECHNIQUES = ['SERIGRAFIA', 'SUBLIMACAO', 'DTF', 'BORDADO', 'VINIL', 'LASER', 'OUTRO'] as const;

const mapOrder = (o: any) => ({
  id: o.id,
  number: Number(o.number),
  customerId: o.customer_id,
  customerName: o.customer_name,
  customerPhone: o.customer_phone,
  title: o.title,
  technique: o.technique,
  status: o.status,
  dueDate: o.due_date,
  artNotes: o.art_notes,
  notes: o.notes,
  discount: Number(o.discount),
  deposit: Number(o.deposit),
  saleId: o.sale_id,
  createdAt: o.created_at,
  approvedAt: o.approved_at,
  readyAt: o.ready_at,
  deliveredAt: o.delivered_at,
  pieces: o.pieces != null ? Number(o.pieces) : undefined,
  total: o.items_total != null ? Number(o.items_total) - Number(o.discount) : undefined,
  artUrl: o.art_id ? absoluteUrl(`/public/arts/${o.art_id}`) : null,
});

const LIST_SQL = `
  SELECT o.*, p.name AS customer_name, p.phone AS customer_phone,
         (SELECT sum(qty) FROM app.custom_order_items i WHERE i.order_id = o.id) AS pieces,
         (SELECT coalesce(sum(total), 0) FROM app.custom_order_items i WHERE i.order_id = o.id) AS items_total,
         (SELECT a.id FROM app.custom_order_arts a WHERE a.order_id = o.id ORDER BY a.created_at LIMIT 1) AS art_id
    FROM app.custom_orders o JOIN app.partners p ON p.id = o.customer_id`;

/** GET /printshop/orders?status=ABERTOS|ENTREGUES|CANCELADOS|TODOS|<status>&q= */
printshopRouter.get('/orders', requireRole(...STAFF), async (req, res) => {
  const status = String(req.query.status ?? 'ABERTOS');
  const q = String(req.query.q ?? '').trim();
  const filter =
    status === 'ABERTOS' ? OPEN : status === 'ENTREGUES' ? ['ENTREGUE'] : status === 'CANCELADOS' ? ['CANCELADO']
      : status === 'TODOS' ? [...OPEN, 'ENTREGUE', 'CANCELADO'] : [status];
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `${LIST_SQL}
          WHERE o.status = ANY($1::text[])
            AND ($2 = '' OR o.title ILIKE '%' || $2 || '%' OR p.name ILIKE '%' || $2 || '%' OR o.number::text = $2)
          ORDER BY o.due_date NULLS LAST, o.number DESC LIMIT 300`,
        [filter, q],
      )
    ).rows,
  );
  res.json(rows.map(mapOrder));
});

/** GET /printshop/summary — números do quadro de produção */
printshopRouter.get('/summary', requireRole(...STAFF), async (req, res) => {
  const r = await db(req, async (c) =>
    (
      await c.query(`SELECT
          count(*) FILTER (WHERE status = 'ORCAMENTO') AS orcamento,
          count(*) FILTER (WHERE status = 'APROVADO')  AS aprovado,
          count(*) FILTER (WHERE status = 'PRODUCAO')  AS producao,
          count(*) FILTER (WHERE status = 'PRONTO')    AS pronto,
          count(*) FILTER (WHERE status IN ('APROVADO','PRODUCAO') AND due_date < current_date) AS atrasados,
          count(*) FILTER (WHERE status IN ('APROVADO','PRODUCAO') AND due_date BETWEEN current_date AND current_date + 2) AS vencendo,
          coalesce(sum(deposit) FILTER (WHERE status IN ('ORCAMENTO','APROVADO','PRODUCAO','PRONTO')), 0) AS sinais
        FROM app.custom_orders`)
    ).rows[0],
  );
  res.json(Object.fromEntries(Object.entries(r).map(([k, v]) => [k, Number(v)])));
});

async function loadOrder(c: any, id: string) {
  const o = (await c.query(`${LIST_SQL} WHERE o.id = $1`, [id])).rows[0];
  if (!o) throw new HttpError(404, 'NAO_ENCONTRADO', 'Pedido não encontrado');
  const items = (
    await c.query(
      `SELECT i.*, p.name AS product_name, p.stock_qty, p.image_url
         FROM app.custom_order_items i LEFT JOIN app.products p ON p.id = i.product_id
        WHERE i.order_id = $1 ORDER BY i.id`,
      [id],
    )
  ).rows;
  const payments = (await c.query('SELECT * FROM app.custom_order_payments WHERE order_id = $1 ORDER BY created_at', [id])).rows;
  const events = (
    await c.query(
      `SELECT e.*, u.full_name FROM app.custom_order_events e LEFT JOIN app.users u ON u.id = e.user_id
        WHERE e.order_id = $1 ORDER BY e.created_at`,
      [id],
    )
  ).rows;
  const arts = (await c.query('SELECT id, name, created_at FROM app.custom_order_arts WHERE order_id = $1 ORDER BY created_at', [id]))
    .rows;
  const itemsTotal = items.reduce((a: number, i: any) => a + Number(i.total), 0);
  const total = Math.round((itemsTotal - Number(o.discount)) * 100) / 100;
  return {
    ...mapOrder(o),
    items: items.map((i: any) => ({
      id: Number(i.id),
      productId: i.product_id,
      productName: i.product_name,
      stockQty: i.stock_qty != null ? Number(i.stock_qty) : null,
      imageUrl: absoluteUrl(i.image_url),
      description: i.description,
      color: i.color,
      sizes: i.sizes ?? {},
      qty: Number(i.qty),
      unitPrice: Number(i.unit_price),
      total: Number(i.total),
    })),
    payments: payments.map((p: any) => ({ method: p.method, amount: Number(p.amount), createdAt: p.created_at })),
    events: events.map((e: any) => ({ status: e.status, note: e.note, user: e.full_name, at: e.created_at })),
    arts: arts.map((a: any) => ({ id: a.id, name: a.name, url: absoluteUrl(`/public/arts/${a.id}`) })),
    itemsTotal,
    total,
    balance: Math.round((total - Number(o.deposit)) * 100) / 100,
  };
}

printshopRouter.get('/orders/:id', requireRole(...STAFF), async (req, res) => {
  res.json(await db(req, (c) => loadOrder(c, String(req.params.id))));
});

const itemSchema = z.object({
  productId: z.string().uuid().optional().nullable(),
  description: z.string().trim().min(1).max(120),
  color: z.string().trim().max(30).optional().nullable(),
  sizes: z.record(z.string().trim().min(1).max(10), z.number().min(0)).default({}),
  qty: z.number().positive().optional(),
  unitPrice: z.number().min(0),
});

const orderSchema = z.object({
  customerId: z.string().uuid(),
  title: z.string().trim().min(2).max(120),
  technique: z.enum(TECHNIQUES).default('DTF'),
  dueDate: z.string().regex(DATE).optional().nullable(),
  artNotes: z.string().trim().max(1000).optional().nullable(),
  notes: z.string().trim().max(1000).optional().nullable(),
  discount: z.number().min(0).default(0),
  items: z.array(itemSchema).default([]),
});

/** Quantidade do item = soma da grade (P/M/G…) quando informada */
function normItem(i: z.infer<typeof itemSchema>) {
  const sizes = Object.fromEntries(Object.entries(i.sizes).filter(([, v]) => v > 0));
  const fromSizes = Object.values(sizes).reduce((a, v) => a + v, 0);
  const qty = fromSizes > 0 ? fromSizes : i.qty ?? 0;
  if (qty <= 0) throw new HttpError(400, 'QTD', `Informe a quantidade de "${i.description}"`);
  return { ...i, sizes, qty, total: Math.round(qty * i.unitPrice * 100) / 100 };
}

async function writeItems(c: any, orderId: string, items: z.infer<typeof itemSchema>[]) {
  await c.query('DELETE FROM app.custom_order_items WHERE order_id = $1', [orderId]);
  for (const raw of items) {
    const i = normItem(raw);
    await c.query(
      `INSERT INTO app.custom_order_items (order_id, product_id, description, color, sizes, qty, unit_price, total)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [orderId, i.productId ?? null, i.description, i.color || null, JSON.stringify(i.sizes), i.qty, i.unitPrice, i.total],
    );
  }
}

/** POST /printshop/orders — novo pedido (começa como ORÇAMENTO) */
printshopRouter.post('/orders', requireRole(...STAFF), async (req, res) => {
  const b = orderSchema.parse(req.body);
  const out = await db(req, async (c) => {
    const o = (
      await c.query(
        `INSERT INTO app.custom_orders (number, customer_id, title, technique, due_date, art_notes, notes, discount, created_by)
         VALUES (app.next_counter('pedido'), $1, $2, $3, $4, $5, $6, $7, app.current_user_id()) RETURNING id`,
        [b.customerId, b.title, b.technique, b.dueDate ?? null, b.artNotes ?? null, b.notes ?? null, b.discount],
      )
    ).rows[0];
    await writeItems(c, o.id, b.items);
    await c.query(
      `INSERT INTO app.custom_order_events (order_id, status, note, user_id) VALUES ($1, 'ORCAMENTO', 'Pedido criado', app.current_user_id())`,
      [o.id],
    );
    return loadOrder(c, o.id);
  });
  res.status(201).json(out);
});

/** PUT /printshop/orders/:id — edita cabeçalho e itens (até ficar pronto) */
printshopRouter.put('/orders/:id', requireRole(...STAFF), async (req, res) => {
  const b = orderSchema.parse(req.body);
  const out = await db(req, async (c) => {
    const cur = (await c.query('SELECT status, deposit FROM app.custom_orders WHERE id = $1 FOR UPDATE', [req.params.id])).rows[0];
    if (!cur) throw new HttpError(404, 'NAO_ENCONTRADO', 'Pedido não encontrado');
    if (['ENTREGUE', 'CANCELADO'].includes(cur.status)) throw new HttpError(409, 'FINALIZADO', `Pedido já está ${cur.status.toLowerCase()}`);
    await c.query(
      `UPDATE app.custom_orders SET customer_id = $2, title = $3, technique = $4, due_date = $5, art_notes = $6, notes = $7, discount = $8
        WHERE id = $1`,
      [req.params.id, b.customerId, b.title, b.technique, b.dueDate ?? null, b.artNotes ?? null, b.notes ?? null, b.discount],
    );
    await writeItems(c, String(req.params.id), b.items);
    const o = await loadOrder(c, String(req.params.id));
    if (o.total < Number(cur.deposit)) throw new HttpError(409, 'SINAL', 'O total ficou menor que o sinal já recebido');
    return o;
  });
  res.json(out);
});

/** POST /printshop/orders/:id/status {status, note} — andamento (ENTREGUE só pelo caixa) */
printshopRouter.post('/orders/:id/status', requireRole(...STAFF), async (req, res) => {
  const b = z
    .object({ status: z.enum(['ORCAMENTO', 'APROVADO', 'PRODUCAO', 'PRONTO', 'CANCELADO']), note: z.string().trim().max(300).optional() })
    .parse(req.body);
  if (b.status === 'CANCELADO' && !MANAGE.includes(req.auth!.role as any))
    throw new HttpError(403, 'SEM_PERMISSAO', 'Só gerente ou administrador cancela pedido');
  const out = await db(req, async (c) => {
    const cur = (await c.query('SELECT status, deposit FROM app.custom_orders WHERE id = $1 FOR UPDATE', [req.params.id])).rows[0];
    if (!cur) throw new HttpError(404, 'NAO_ENCONTRADO', 'Pedido não encontrado');
    if (['ENTREGUE', 'CANCELADO'].includes(cur.status)) throw new HttpError(409, 'FINALIZADO', `Pedido já está ${cur.status.toLowerCase()}`);
    if (b.status !== 'CANCELADO' && b.status !== 'ORCAMENTO') {
      const n = (await c.query('SELECT count(*)::int AS n FROM app.custom_order_items WHERE order_id = $1', [req.params.id])).rows[0].n;
      if (!n) throw new HttpError(409, 'SEM_ITENS', 'Coloque os itens do pedido antes de aprovar');
    }
    await c.query(
      `UPDATE app.custom_orders SET status = $2,
              approved_at = CASE WHEN $2 = 'APROVADO' THEN coalesce(approved_at, now()) ELSE approved_at END,
              ready_at    = CASE WHEN $2 = 'PRONTO' THEN now() ELSE ready_at END,
              canceled_at = CASE WHEN $2 = 'CANCELADO' THEN now() ELSE canceled_at END
        WHERE id = $1`,
      [req.params.id, b.status],
    );
    const note =
      b.status === 'CANCELADO' && Number(cur.deposit) > 0
        ? `${b.note ? b.note + ' · ' : ''}Atenção: havia sinal de R$ ${Number(cur.deposit).toFixed(2).replace('.', ',')}`
        : b.note ?? null;
    await c.query(
      `INSERT INTO app.custom_order_events (order_id, status, note, user_id) VALUES ($1, $2, $3, app.current_user_id())`,
      [req.params.id, b.status, note],
    );
    return loadOrder(c, String(req.params.id));
  });
  res.json(out);
});

/** POST /printshop/orders/:id/deposit {amount, method} — sinal (dinheiro entra na gaveta) */
printshopRouter.post('/orders/:id/deposit', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = z.object({ amount: z.number().positive(), method: z.enum(['DINHEIRO', 'PIX', 'DEBITO', 'CREDITO']) }).parse(req.body);
  const out = await db(req, async (c) => {
    await c.query('SELECT app.add_order_deposit($1, $2, $3)', [req.params.id, b.amount, b.method]);
    return loadOrder(c, String(req.params.id));
  });
  res.json(out);
});

/** POST /printshop/orders/:id/close {payments, dueDays} — entrega e recebe o restante no caixa */
printshopRouter.post('/orders/:id/close', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = z
    .object({
      payments: z.array(z.object({
        method: z.enum(['DINHEIRO', 'PIX', 'DEBITO', 'CREDITO', 'PRAZO', 'VALE']),
        amount: z.number().positive(),
        voucher: z.string().trim().max(20).optional(),
      })).default([]),
      dueDays: z.number().int().min(0).max(365).default(30),
    })
    .parse(req.body);
  const out = await db(req, async (c) => {
    const saleId = (
      await c.query('SELECT app.close_custom_order($1, $2::jsonb, $3) AS id', [req.params.id, JSON.stringify(b.payments), b.dueDays])
    ).rows[0].id;
    return { saleId, receipt: await loadReceipt(c, saleId), order: await loadOrder(c, String(req.params.id)) };
  });
  res.json(out);
});

// ----------------------------------------------------------------- artes
const artUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 2 * 1024 * 1024 } });

/** POST /printshop/orders/:id/arts (multipart "image", até 2 MB; até 6 por pedido) */
printshopRouter.post('/orders/:id/arts', requireRole(...STAFF), artUpload.single('image'), async (req, res) => {
  if (!req.file) throw new HttpError(400, 'SEM_ARQUIVO', 'Envie a imagem no campo "image"');
  const type = sniffImage(req.file.buffer);
  if (!type) throw new HttpError(415, 'FORMATO', 'Use uma imagem JPG, PNG ou WEBP');
  const file = req.file;
  const out = await db(req, async (c) => {
    const o = (await c.query('SELECT id FROM app.custom_orders WHERE id = $1', [req.params.id])).rows[0];
    if (!o) throw new HttpError(404, 'NAO_ENCONTRADO', 'Pedido não encontrado');
    const n = (await c.query('SELECT count(*)::int AS n FROM app.custom_order_arts WHERE order_id = $1', [o.id])).rows[0].n;
    if (n >= 6) throw new HttpError(409, 'LIMITE', 'Cada pedido guarda até 6 artes');
    await c.query('INSERT INTO app.custom_order_arts (order_id, name, content_type, data) VALUES ($1, $2, $3, $4)', [
      o.id, (file.originalname || 'arte').slice(0, 80), type, file.buffer,
    ]);
    return loadOrder(c, o.id);
  });
  res.status(201).json(out);
});

printshopRouter.delete('/orders/:id/arts/:artId', requireRole(...STAFF), async (req, res) => {
  const out = await db(req, async (c) => {
    await c.query('DELETE FROM app.custom_order_arts WHERE id = $1 AND order_id = $2', [req.params.artId, req.params.id]);
    return loadOrder(c, String(req.params.id));
  });
  res.json(out);
});
