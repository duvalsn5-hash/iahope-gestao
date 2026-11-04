import { Router } from 'express';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';

export const productsRouter = Router();
productsRouter.use(requireAuth);

const map = (p: any) => ({
  id: p.id,
  sku: p.sku,
  barcode: p.barcode,
  name: p.name,
  unit: p.unit,
  price: Number(p.price),
  stockQty: Number(p.stock_qty),
  minStock: Number(p.min_stock),
  isActive: p.is_active,
});

/** GET /products?q= — busca por nome, SKU ou código de barras (até 50) */
productsRouter.get('/', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT * FROM app.products
          WHERE is_active AND ($1 = '' OR barcode = $1 OR sku ILIKE $1 || '%' OR name ILIKE '%' || $1 || '%')
          ORDER BY (barcode = $1) DESC NULLS LAST, name LIMIT 50`,
        [q],
      )
    ).rows,
  );
  res.json(rows.map(map));
});

/** GET /products/barcode/:code — leitura do scanner (match exato por EAN ou SKU) */
productsRouter.get('/barcode/:code', async (req, res) => {
  const p = await db(req, async (c) =>
    (await c.query('SELECT * FROM app.products WHERE is_active AND (barcode = $1 OR sku = $1) LIMIT 1', [req.params.code])).rows[0],
  );
  if (!p) throw new HttpError(404, 'PRODUTO_NAO_ENCONTRADO', `Código ${req.params.code} não cadastrado`);
  res.json(map(p));
});

const upsertSchema = z.object({
  sku: z.string().trim().min(1),
  barcode: z.string().trim().optional(),
  name: z.string().trim().min(2),
  unit: z.string().trim().default('UN'),
  price: z.number().min(0),
  cost: z.number().min(0).default(0),
  stockQty: z.number().default(0),
  minStock: z.number().min(0).default(0),
});

/** POST /products */
productsRouter.post('/', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  const b = upsertSchema.parse(req.body);
  const p = await db(req, async (c) =>
    (
      await c.query(
        `INSERT INTO app.products (sku, barcode, name, unit, price, cost, stock_qty, min_stock)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
        [b.sku, b.barcode || null, b.name, b.unit, b.price, b.cost, b.stockQty, b.minStock],
      )
    ).rows[0],
  );
  res.status(201).json(map(p));
});

/** POST /products/:id/stock — entrada/ajuste de estoque */
productsRouter.post('/:id/stock', requireRole('ADMIN', 'GERENTE', 'OPERADOR'), async (req, res) => {
  const b = z.object({ qty: z.number(), reason: z.enum(['ENTRADA', 'AJUSTE']) }).parse(req.body);
  const p = await db(req, async (c) => {
    const r = await c.query('UPDATE app.products SET stock_qty = stock_qty + $2 WHERE id = $1 RETURNING *', [req.params.id, b.qty]);
    if (!r.rows[0]) throw new HttpError(404, 'NAO_ENCONTRADO', 'Produto não encontrado');
    await c.query(
      'INSERT INTO app.stock_movements (product_id, qty, reason, user_id) VALUES ($1, $2, $3, app.current_user_id())',
      [req.params.id, b.qty, b.reason],
    );
    return r.rows[0];
  });
  res.json(map(p));
});
