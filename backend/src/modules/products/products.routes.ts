import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { parseScaleBarcode, ScaleConfig } from '../../utils/scale';
import { absoluteUrl } from '../auth/auth.routes';

/** Cadastro de produtos (núcleo — disponível em todos os planos) */
export const productsRouter = Router();
productsRouter.use(requireAuth);

const map = (p: any) => ({
  id: p.id,
  sku: p.sku,
  barcode: p.barcode,
  name: p.name,
  unit: p.unit,
  price: Number(p.price),
  cost: Number(p.cost),
  stockQty: Number(p.stock_qty),
  minStock: Number(p.min_stock),
  scaleCode: p.scale_code ?? null,
  imageUrl: absoluteUrl(p.image_url),
  isActive: p.is_active,
});

/**
 * GET /products?q=&all=1&low=1
 * Busca por nome, SKU ou código de barras. all=1 inclui inativos (tela de cadastro);
 * low=1 só estoque abaixo do mínimo.
 */
productsRouter.get('/', async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const all = req.query.all === '1';
  const low = req.query.low === '1';
  const limit = all ? 500 : 50;
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT * FROM app.products
          WHERE ($2 OR is_active)
            AND (NOT $3 OR stock_qty <= min_stock)
            AND ($1 = '' OR barcode = $1 OR sku ILIKE $1 || '%' OR name ILIKE '%' || $1 || '%'
                 OR scale_code::text = $1)
          ORDER BY (barcode = $1) DESC NULLS LAST, is_active DESC, name
          LIMIT ${limit}`,
        [q, all, low],
      )
    ).rows,
  );
  res.json(rows.map(map));
});

/**
 * GET /products/barcode/:code — leitura do scanner.
 * 1) EAN ou SKU exato  2) etiqueta de balança (módulo BALANCA), que já traz a quantidade.
 */
productsRouter.get('/barcode/:code', async (req, res) => {
  const code = String(req.params.code).trim();
  const found = await db(req, async (c) => {
    const exact = (await c.query('SELECT * FROM app.products WHERE is_active AND (barcode = $1 OR sku = $1) LIMIT 1', [code]))
      .rows[0];
    if (exact) return { product: exact, qty: null as number | null, labelTotal: null as number | null };

    if (!req.auth!.modules.includes('BALANCA')) return null;
    const cfg = (await c.query('SELECT scale_config FROM app.tenants WHERE id = $1', [req.auth!.tid])).rows[0]
      ?.scale_config as ScaleConfig | undefined;
    const read = cfg ? parseScaleBarcode(code, cfg) : null;
    if (!read) return null;
    const p = (await c.query('SELECT * FROM app.products WHERE is_active AND scale_code = $1', [read.scaleCode])).rows[0];
    if (!p) return null;
    const price = Number(p.price);
    if (read.valueType === 'PESO') return { product: p, qty: read.value, labelTotal: Math.round(read.value * price * 100) / 100 };
    if (price <= 0) throw new HttpError(422, 'SEM_PRECO', `Produto ${p.name} sem preço de venda`);
    // etiqueta de preço: quantidade = total ÷ preço/kg (3 casas)
    return { product: p, qty: Math.round((read.value / price) * 1000) / 1000, labelTotal: read.value };
  });
  if (!found) throw new HttpError(404, 'PRODUTO_NAO_ENCONTRADO', `Código ${code} não cadastrado`);
  res.json({ ...map(found.product), scaleQty: found.qty, scaleTotal: found.labelTotal });
});

const upsertSchema = z.object({
  sku: z.string().trim().min(1).max(40),
  barcode: z.string().trim().max(20).optional().nullable(),
  name: z.string().trim().min(2).max(120),
  unit: z.string().trim().min(1).max(6).default('UN'),
  price: z.number().min(0),
  cost: z.number().min(0).default(0),
  stockQty: z.number().default(0),
  minStock: z.number().min(0).default(0),
  scaleCode: z.number().int().positive().optional().nullable(),
  isActive: z.boolean().default(true),
});

/** POST /products */
productsRouter.post('/', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  const b = upsertSchema.parse(req.body);
  const p = await db(req, async (c) => {
    const r = await c.query(
      `INSERT INTO app.products (sku, barcode, name, unit, price, cost, stock_qty, min_stock, scale_code, is_active)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [b.sku, b.barcode || null, b.name, b.unit.toUpperCase(), b.price, b.cost, b.stockQty, b.minStock, b.scaleCode ?? null, b.isActive],
    );
    if (b.stockQty) {
      await c.query(
        `INSERT INTO app.stock_movements (product_id, qty, reason, user_id) VALUES ($1, $2, 'AJUSTE', app.current_user_id())`,
        [r.rows[0].id, b.stockQty],
      );
    }
    return r.rows[0];
  });
  res.status(201).json(map(p));
});

/** PUT /products/:id — edita o cadastro (estoque muda só por movimentação) */
productsRouter.put('/:id', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  const b = upsertSchema.omit({ stockQty: true }).parse(req.body);
  const p = await db(req, async (c) =>
    (
      await c.query(
        `UPDATE app.products SET sku = $2, barcode = $3, name = $4, unit = $5, price = $6, cost = $7,
                min_stock = $8, scale_code = $9, is_active = $10
          WHERE id = $1 RETURNING *`,
        [req.params.id, b.sku, b.barcode || null, b.name, b.unit.toUpperCase(), b.price, b.cost, b.minStock, b.scaleCode ?? null, b.isActive],
      )
    ).rows[0],
  );
  if (!p) throw new HttpError(404, 'NAO_ENCONTRADO', 'Produto não encontrado');
  res.json(map(p));
});

/** POST /products/:id/stock — entrada ou ajuste de estoque ({qty: +/-}) */
productsRouter.post('/:id/stock', requireRole('ADMIN', 'GERENTE', 'OPERADOR'), async (req, res) => {
  const b = z.object({ qty: z.number().refine((v) => v !== 0), reason: z.enum(['ENTRADA', 'AJUSTE']) }).parse(req.body);
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

// ---------------------------------------------------------------- foto do produto
const imageUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 1024 * 1024 } });

function sniffImage(buf: Buffer): string | null {
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 4).toString() === 'RIFF' && buf.subarray(8, 12).toString() === 'WEBP') return 'image/webp';
  return null;
}

/**
 * POST /products/:id/image (multipart, campo "image", até 1 MB)
 * O app já reduz a foto para ~600 px em JPEG antes de enviar (~40–80 KB).
 */
productsRouter.post('/:id/image', requireRole('ADMIN', 'GERENTE'), imageUpload.single('image'), async (req, res) => {
  if (!req.file) throw new HttpError(400, 'SEM_ARQUIVO', 'Envie a foto no campo "image"');
  const type = sniffImage(req.file.buffer);
  if (!type) throw new HttpError(415, 'FORMATO', 'Use uma foto JPG, PNG ou WEBP');
  const file = req.file;
  const url = await db(req, async (c) => {
    const p = (await c.query('SELECT id FROM app.products WHERE id = $1', [req.params.id])).rows[0];
    if (!p) throw new HttpError(404, 'NAO_ENCONTRADO', 'Produto não encontrado');
    await c.query(
      `INSERT INTO app.product_images (product_id, content_type, data, updated_at) VALUES ($1, $2, $3, now())
       ON CONFLICT (product_id) DO UPDATE SET content_type = EXCLUDED.content_type, data = EXCLUDED.data, updated_at = now()`,
      [p.id, type, file.buffer],
    );
    const u = `/public/products/${p.id}/image?v=${Date.now()}`;
    await c.query('UPDATE app.products SET image_url = $2 WHERE id = $1', [p.id, u]);
    return u;
  });
  res.json({ imageUrl: absoluteUrl(url) });
});

/** DELETE /products/:id/image */
productsRouter.delete('/:id/image', requireRole('ADMIN', 'GERENTE'), async (req, res) => {
  await db(req, async (c) => {
    await c.query('DELETE FROM app.product_images WHERE product_id = $1', [req.params.id]);
    await c.query('UPDATE app.products SET image_url = NULL WHERE id = $1', [req.params.id]);
  });
  res.json({ imageUrl: null });
});

/** GET /products/:id/movements — histórico de estoque */
productsRouter.get('/:id/movements', async (req, res) => {
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT m.qty, m.reason, m.created_at, u.full_name AS user_name
           FROM app.stock_movements m LEFT JOIN app.users u ON u.id = m.user_id
          WHERE m.product_id = $1 ORDER BY m.created_at DESC LIMIT 100`,
        [req.params.id],
      )
    ).rows,
  );
  res.json(rows.map((r: any) => ({ qty: Number(r.qty), reason: r.reason, createdAt: r.created_at, user: r.user_name })));
});
