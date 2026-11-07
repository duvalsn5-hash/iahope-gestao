import { Router } from 'express';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { absoluteUrl } from '../auth/auth.routes';
import { mapPartner } from '../partners/partners.routes';

/**
 * Módulo MODA (loja de roupas e calçados): grade de tamanho × cor,
 * códigos de barras internos, trocas com vale-troca e condicional.
 */
export const fashionRouter = Router();
fashionRouter.use(requireAuth, requireModule('MODA'));

const MANAGE = ['ADMIN', 'GERENTE'] as const;
const COUNTER = ['ADMIN', 'GERENTE', 'CAIXA'] as const;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Ordem natural dos tamanhos (PP, P, M, G, GG… e números) */
const SIZE_ORDER = ['RN', 'PP', 'P', 'M', 'G', 'GG', 'XG', 'XGG', 'EG', 'EGG', 'G1', 'G2', 'G3', 'G4', 'U', 'ÚNICO'];
const sizeRank = (s: string | null) => {
  if (!s) return 999;
  const i = SIZE_ORDER.indexOf(s.toUpperCase());
  if (i >= 0) return i;
  const n = Number(s.replace(',', '.'));
  return Number.isFinite(n) ? 100 + n : 500;
};

/** "Azul Marinho" → "AZM", "M" → "M" (pedaço do SKU) */
const skuPart = (v: string) => {
  const clean = v.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z0-9 ]/g, '').trim();
  const words = clean.split(/\s+/).filter(Boolean);
  if (words.length > 1) return (words[0].slice(0, 2) + words.slice(1).map((w) => w[0]).join('')).slice(0, 4);
  return clean.slice(0, 4);
};

const mapVariant = (p: any) => ({
  id: p.id,
  sku: p.sku,
  barcode: p.barcode,
  name: p.name,
  size: p.size,
  color: p.color,
  price: Number(p.price),
  cost: Number(p.cost),
  stockQty: Number(p.stock_qty),
  minStock: Number(p.min_stock),
  unit: p.unit,
  category: p.category,
  imageUrl: absoluteUrl(p.image_url),
  isActive: p.is_active,
});

// ================================================================= GRADE
/** GET /fashion/grades?q= — modelos com a grade (tamanho × cor) e estoque de cada combinação */
fashionRouter.get('/grades', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT * FROM app.products
          WHERE grade_id IS NOT NULL
            AND grade_id IN (SELECT grade_id FROM app.products
                              WHERE grade_id IS NOT NULL
                                AND ($1 = '' OR grade_model ILIKE '%' || $1 || '%' OR barcode = $1 OR sku ILIKE $1 || '%'
                                     OR category ILIKE '%' || $1 || '%'))
          ORDER BY grade_model, color, size`,
        [q],
      )
    ).rows,
  );
  const groups = new Map<string, any>();
  for (const p of rows) {
    let g = groups.get(p.grade_id);
    if (!g) {
      g = { gradeId: p.grade_id, model: p.grade_model, category: p.category, price: Number(p.price), cost: Number(p.cost),
            imageUrl: absoluteUrl(p.image_url), variants: [] as any[] };
      groups.set(p.grade_id, g);
    }
    if (!g.imageUrl && p.image_url) g.imageUrl = absoluteUrl(p.image_url);
    g.variants.push(mapVariant(p));
  }
  const out = [...groups.values()].map((g) => {
    const sizes = [...new Set<string>(g.variants.map((v: any) => v.size).filter(Boolean))].sort((a, b) => sizeRank(a) - sizeRank(b));
    const colors = [...new Set<string>(g.variants.map((v: any) => v.color).filter(Boolean))].sort();
    const totalStock = g.variants.reduce((a: number, v: any) => a + v.stockQty, 0);
    return { ...g, sizes, colors, totalStock };
  });
  res.json(out);
});

const gradeSchema = z.object({
  gradeId: z.string().uuid().optional(), // informado = acrescenta combinações num modelo existente
  model: z.string().trim().min(2).max(80),
  skuBase: z.string().trim().max(20).optional(),
  category: z.string().trim().max(40).optional().nullable(),
  unit: z.string().trim().min(1).max(6).default('UN'),
  price: z.number().min(0),
  cost: z.number().min(0).default(0),
  minStock: z.number().min(0).default(0),
  sizes: z.array(z.string().trim().min(1).max(10)).min(1).max(20),
  colors: z.array(z.string().trim().min(1).max(30)).min(1).max(20),
  /** estoque inicial por combinação: {"Preta|M": 3} */
  stock: z.record(z.string(), z.number().min(0)).default({}),
});

/**
 * POST /fashion/grade — cria o modelo com todas as combinações tamanho × cor.
 * Cada combinação vira um produto com SKU e código de barras (EAN-13 interno) próprios.
 */
fashionRouter.post('/grade', requireRole(...MANAGE), async (req, res) => {
  const b = gradeSchema.parse(req.body);
  const sizes = [...new Set(b.sizes.map((s) => s.toUpperCase()))];
  const colors = [...new Set(b.colors.map((c) => c.charAt(0).toUpperCase() + c.slice(1)))];
  const base = (b.skuBase && b.skuBase.length ? b.skuBase : skuPart(b.model) + String(Date.now()).slice(-4)).toUpperCase();
  const created = await db(req, async (c) => {
    let gradeId = b.gradeId ?? randomUUID();
    if (b.gradeId) {
      const g = (await c.query('SELECT 1 FROM app.products WHERE grade_id = $1 LIMIT 1', [b.gradeId])).rows[0];
      if (!g) throw new HttpError(404, 'NAO_ENCONTRADO', 'Modelo não encontrado');
    }
    const existing = new Set(
      (await c.query('SELECT color, size FROM app.products WHERE grade_id = $1', [gradeId])).rows.map((r: any) => `${r.color}|${r.size}`),
    );
    const out: any[] = [];
    for (const color of colors) {
      for (const size of sizes) {
        if (existing.has(`${color}|${size}`)) continue;
        const qty = b.stock[`${color}|${size}`] ?? 0;
        const ean = (await c.query('SELECT app.next_internal_ean() AS e')).rows[0].e;
        const r = await c.query(
          `INSERT INTO app.products (sku, barcode, name, unit, price, cost, stock_qty, min_stock, category,
                                     grade_id, grade_model, size, color)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING *`,
          [`${base}-${skuPart(color)}-${size}`.slice(0, 40), ean, `${b.model} ${color} ${size}`.slice(0, 120),
           b.unit.toUpperCase(), b.price, b.cost, qty, b.minStock, b.category || null, gradeId, b.model, size, color],
        );
        if (qty > 0) {
          await c.query(
            `INSERT INTO app.stock_movements (product_id, qty, reason, user_id) VALUES ($1, $2, 'ENTRADA', app.current_user_id())`,
            [r.rows[0].id, qty],
          );
        }
        out.push(mapVariant(r.rows[0]));
      }
    }
    return { gradeId, variants: out };
  });
  res.status(201).json(created);
});

/** PUT /fashion/grade/:gradeId — muda nome, categoria e preço de todas as combinações */
fashionRouter.put('/grade/:gradeId', requireRole(...MANAGE), async (req, res) => {
  const b = z
    .object({
      model: z.string().trim().min(2).max(80),
      category: z.string().trim().max(40).optional().nullable(),
      price: z.number().min(0),
      cost: z.number().min(0).default(0),
    })
    .parse(req.body);
  const n = await db(req, async (c) =>
    (
      await c.query(
        `UPDATE app.products SET grade_model = $2, category = $3, price = $4, cost = $5,
                name = left($2 || coalesce(' ' || color, '') || coalesce(' ' || size, ''), 120)
          WHERE grade_id = $1`,
        [req.params.gradeId, b.model, b.category || null, b.price, b.cost],
      )
    ).rowCount,
  );
  if (!n) throw new HttpError(404, 'NAO_ENCONTRADO', 'Modelo não encontrado');
  res.json({ updated: n });
});

/** POST /fashion/barcodes {productIds} — gera código de barras interno para quem não tem */
fashionRouter.post('/barcodes', requireRole(...MANAGE), async (req, res) => {
  const b = z.object({ productIds: z.array(z.string().uuid()).min(1).max(500) }).parse(req.body);
  const rows = await db(req, async (c) => {
    for (const id of b.productIds) {
      await c.query(
        `UPDATE app.products SET barcode = app.next_internal_ean() WHERE id = $1 AND (barcode IS NULL OR barcode = '')`,
        [id],
      );
    }
    return (await c.query('SELECT * FROM app.products WHERE id = ANY($1::uuid[])', [b.productIds])).rows;
  });
  res.json(rows.map(mapVariant));
});

// ================================================================= TROCAS
/** GET /fashion/sales/:number — venda pelo número do cupom, com o que ainda pode voltar */
fashionRouter.get('/sales/:number', requireRole(...COUNTER), async (req, res) => {
  const n = Number(req.params.number);
  if (!Number.isInteger(n) || n <= 0) throw new HttpError(400, 'NUMERO_INVALIDO', 'Informe o número do cupom');
  const data = await db(req, async (c) => {
    const s = (
      await c.query(
        `SELECT s.*, p.name AS customer_name FROM app.sales s LEFT JOIN app.partners p ON p.id = s.customer_id
          WHERE s.sale_number = $1`,
        [n],
      )
    ).rows[0];
    if (!s) return null;
    const items = (
      await c.query(
        `SELECT i.*, pr.size, pr.color, pr.barcode FROM app.sale_items i LEFT JOIN app.products pr ON pr.id = i.product_id
          WHERE i.sale_id = $1 ORDER BY i.id`,
        [s.id],
      )
    ).rows;
    const returns = (await c.query('SELECT * FROM app.sale_returns WHERE sale_id = $1 ORDER BY created_at', [s.id])).rows;
    return { s, items, returns };
  });
  if (!data) throw new HttpError(404, 'NAO_ENCONTRADO', `Venda nº ${n} não encontrada`);
  const { s, items, returns } = data;
  const factor = Number(s.subtotal) > 0 ? Number(s.total) / Number(s.subtotal) : 1;
  res.json({
    id: s.id,
    number: Number(s.sale_number),
    status: s.status,
    createdAt: s.created_at,
    customerId: s.customer_id,
    customerName: s.customer_name,
    subtotal: Number(s.subtotal),
    discount: Number(s.discount),
    total: Number(s.total),
    items: items.map((i: any) => ({
      id: Number(i.id),
      productId: i.product_id,
      description: i.description,
      barcode: i.barcode,
      qty: Number(i.qty),
      returnedQty: Number(i.returned_qty),
      unitPrice: Number(i.unit_price),
      // valor efetivamente pago por unidade (desconto rateado)
      paidUnit: Math.round(Number(i.unit_price) * factor * 100) / 100,
    })),
    returns: returns.map((r: any) => ({ amount: Number(r.amount), mode: r.mode, createdAt: r.created_at, reason: r.reason })),
  });
});

const returnSchema = z.object({
  saleId: z.string().uuid(),
  items: z.array(z.object({ saleItemId: z.number().int().positive(), qty: z.number().positive() })).min(1),
  mode: z.enum(['VALE', 'DINHEIRO']),
  customerId: z.string().uuid().optional().nullable(),
  reason: z.string().trim().max(200).optional(),
  validDays: z.number().int().min(0).max(730).default(90),
});

/** POST /fashion/returns — troca/devolução: estoque volta; gera vale-troca ou devolve em dinheiro */
fashionRouter.post('/returns', requireRole(...COUNTER), async (req, res) => {
  const b = returnSchema.parse(req.body);
  const r = await db(req, async (c) =>
    (
      await c.query('SELECT app.return_sale_items($1, $2::jsonb, $3, $4, $5, $6) AS r', [
        b.saleId,
        JSON.stringify(b.items.map((i) => ({ sale_item_id: i.saleItemId, qty: i.qty }))),
        b.mode,
        b.customerId ?? null,
        b.reason ?? null,
        b.validDays,
      ])
    ).rows[0].r,
  );
  res.status(201).json({ ...r, amount: Number(r.amount) });
});

const mapVoucher = (v: any) => ({
  id: v.id,
  code: v.code,
  amount: Number(v.amount),
  balance: Number(v.balance),
  expiresAt: v.expires_at,
  customerName: v.customer_name,
  originSale: v.origin_number != null ? Number(v.origin_number) : null,
  createdAt: v.created_at,
});

/** GET /fashion/vouchers?q=&open=1 — vales-troca emitidos */
fashionRouter.get('/vouchers', requireRole(...COUNTER), async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const open = req.query.open === '1';
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT s.*, p.name AS customer_name, sa.sale_number AS origin_number
           FROM app.store_credits s
           LEFT JOIN app.partners p ON p.id = s.customer_id
           LEFT JOIN app.sales sa ON sa.id = s.origin_sale_id
          WHERE ($1 = '' OR s.code ILIKE '%' || $1 || '%' OR p.name ILIKE '%' || $1 || '%')
            AND (NOT $2 OR s.balance > 0)
          ORDER BY s.created_at DESC LIMIT 200`,
        [q, open],
      )
    ).rows,
  );
  res.json(rows.map(mapVoucher));
});

// ================================================================= CONDICIONAL
const mapConsignment = (c: any) => ({
  id: c.id,
  number: Number(c.number),
  customerId: c.customer_id,
  customerName: c.customer_name,
  customerPhone: c.customer_phone,
  status: c.status,
  dueDate: c.due_date,
  notes: c.notes,
  createdAt: c.created_at,
  closedAt: c.closed_at,
  pieces: c.pieces != null ? Number(c.pieces) : undefined,
  total: c.total != null ? Number(c.total) : undefined,
});

/** GET /fashion/consignments?status=ABERTA|FECHADA|TODAS */
fashionRouter.get('/consignments', requireRole(...COUNTER), async (req, res) => {
  const status = String(req.query.status ?? 'ABERTA');
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT c.*, p.name AS customer_name, p.phone AS customer_phone,
                (SELECT sum(qty) FROM app.consignment_items i WHERE i.consignment_id = c.id) AS pieces,
                (SELECT sum(qty * unit_price) FROM app.consignment_items i WHERE i.consignment_id = c.id) AS total
           FROM app.consignments c JOIN app.partners p ON p.id = c.customer_id
          WHERE ($1 = 'TODAS' OR c.status = $1)
          ORDER BY c.status = 'ABERTA' DESC, c.due_date NULLS LAST, c.created_at DESC LIMIT 300`,
        [status],
      )
    ).rows,
  );
  res.json(rows.map(mapConsignment));
});

async function loadConsignment(c: any, id: string) {
  const h = (
    await c.query(
      `SELECT c.*, p.name AS customer_name, p.phone AS customer_phone
         FROM app.consignments c JOIN app.partners p ON p.id = c.customer_id WHERE c.id = $1`,
      [id],
    )
  ).rows[0];
  if (!h) throw new HttpError(404, 'NAO_ENCONTRADO', 'Condicional não encontrada');
  const items = (
    await c.query(
      `SELECT i.*, p.barcode, p.image_url, p.size, p.color FROM app.consignment_items i
         JOIN app.products p ON p.id = i.product_id WHERE i.consignment_id = $1 ORDER BY i.id`,
      [id],
    )
  ).rows;
  return {
    ...mapConsignment(h),
    items: items.map((i: any) => ({
      id: Number(i.id),
      productId: i.product_id,
      description: i.description,
      barcode: i.barcode,
      imageUrl: absoluteUrl(i.image_url),
      qty: Number(i.qty),
      unitPrice: Number(i.unit_price),
      returnedQty: i.returned_qty != null ? Number(i.returned_qty) : null,
      keptQty: i.kept_qty != null ? Number(i.kept_qty) : null,
    })),
  };
}

fashionRouter.get('/consignments/:id', requireRole(...COUNTER), async (req, res) => {
  res.json(await db(req, (c) => loadConsignment(c, String(req.params.id))));
});

/** POST /fashion/consignments — separa as peças para o cliente levar */
fashionRouter.post('/consignments', requireRole(...COUNTER), async (req, res) => {
  const b = z
    .object({
      customerId: z.string().uuid(),
      items: z.array(z.object({ productId: z.string().uuid(), qty: z.number().positive() })).min(1),
      dueDate: z.string().regex(DATE).optional().nullable(),
      notes: z.string().trim().max(300).optional().nullable(),
    })
    .parse(req.body);
  const out = await db(req, async (c) => {
    const id = (
      await c.query('SELECT app.open_consignment($1, $2::jsonb, $3, $4) AS id', [
        b.customerId,
        JSON.stringify(b.items.map((i) => ({ product_id: i.productId, qty: i.qty }))),
        b.dueDate ?? null,
        b.notes ?? null,
      ])
    ).rows[0].id;
    return loadConsignment(c, id);
  });
  res.status(201).json(out);
});

/**
 * POST /fashion/consignments/:id/close {returns:[{itemId, returned}]}
 * Acerto: tudo volta ao estoque e a resposta traz o que o cliente ficou,
 * já com os dados do produto, para o app colocar no PDV.
 */
fashionRouter.post('/consignments/:id/close', requireRole(...COUNTER), async (req, res) => {
  const b = z
    .object({ returns: z.array(z.object({ itemId: z.number().int().positive(), returned: z.number().min(0) })).default([]) })
    .parse(req.body);
  const out = await db(req, async (c) => {
    const r = (
      await c.query('SELECT app.close_consignment($1, $2::jsonb, false) AS r', [
        req.params.id,
        JSON.stringify(b.returns.map((x) => ({ item_id: x.itemId, returned: x.returned }))),
      ])
    ).rows[0].r;
    const kept = r.kept as { product_id: string; qty: number }[];
    const products = kept.length
      ? (await c.query('SELECT * FROM app.products WHERE id = ANY($1::uuid[])', [kept.map((k) => k.product_id)])).rows
      : [];
    const customer = (await c.query('SELECT * FROM app.partners WHERE id = $1', [r.customerId])).rows[0];
    return {
      consignment: await loadConsignment(c, String(req.params.id)),
      customer: customer ? mapPartner(customer) : null,
      kept: kept.map((k) => ({ product: mapVariant(products.find((p: any) => p.id === k.product_id)), qty: Number(k.qty) })),
    };
  });
  res.json(out);
});

/** POST /fashion/consignments/:id/cancel — cliente devolveu tudo */
fashionRouter.post('/consignments/:id/cancel', requireRole(...COUNTER), async (req, res) => {
  const out = await db(req, async (c) => {
    await c.query("SELECT app.close_consignment($1, '[]'::jsonb, true)", [req.params.id]);
    return loadConsignment(c, String(req.params.id));
  });
  res.json(out);
});
