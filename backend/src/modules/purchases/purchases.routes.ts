import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { parseNfeXml } from './nfe-parser';

/**
 * Entrada de mercadoria por XML de NF-e (modelo 55).
 * 1) POST /purchases/preview  → lê o XML e sugere o produto de cada item
 * 2) POST /purchases          → grava: estoque, custo, fornecedor e contas a pagar
 */
export const purchasesRouter = Router();
purchasesRouter.use(requireAuth, requireModule('COMPRAS'), requireRole('ADMIN', 'GERENTE'));

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 2 * 1024 * 1024 } });

purchasesRouter.post('/preview', upload.single('xml'), async (req, res) => {
  const xml = req.file ? req.file.buffer.toString('utf8') : typeof req.body?.xml === 'string' ? req.body.xml : '';
  if (!xml) throw new HttpError(400, 'SEM_ARQUIVO', 'Envie o XML da NF-e no campo "xml"');
  const nfe = parseNfeXml(xml);

  const out = await db(req, async (c) => {
    const tenant = (await c.query('SELECT cnpj FROM app.tenants WHERE id = $1', [req.auth!.tid])).rows[0];
    const supplier = nfe.supplier.doc
      ? (await c.query('SELECT id, name FROM app.partners WHERE doc = $1', [nfe.supplier.doc])).rows[0]
      : undefined;
    const already = nfe.accessKey
      ? (await c.query('SELECT id, created_at FROM app.purchases WHERE access_key = $1', [nfe.accessKey])).rows[0]
      : undefined;

    const items = [];
    for (const it of nfe.items) {
      // 1) código já aprendido deste fornecedor  2) código de barras  3) produto novo
      let match: any = null;
      let factor = 1;
      let by: 'FORNECEDOR' | 'CODIGO_BARRAS' | null = null;
      if (supplier) {
        const m = (
          await c.query(
            `SELECT p.id, p.name, p.sku, p.unit, p.price, s.factor FROM app.supplier_product_codes s
               JOIN app.products p ON p.id = s.product_id
              WHERE s.partner_id = $1 AND s.supplier_code = $2`,
            [supplier.id, it.supplierCode],
          )
        ).rows[0];
        if (m) {
          match = m;
          factor = Number(m.factor);
          by = 'FORNECEDOR';
        }
      }
      if (!match && it.barcode) {
        const m = (await c.query('SELECT id, name, sku, unit, price FROM app.products WHERE barcode = $1', [it.barcode])).rows[0];
        if (m) {
          match = m;
          by = 'CODIGO_BARRAS';
        }
      }
      items.push({
        ...it,
        factor,
        match: match
          ? { productId: match.id, name: match.name, sku: match.sku, unit: match.unit, price: Number(match.price), by }
          : null,
      });
    }
    return {
      tenantCnpj: tenant.cnpj,
      supplierId: supplier?.id ?? null,
      alreadyImportedAt: already?.created_at ?? null,
      items,
    };
  });

  const warnings: string[] = [];
  if (nfe.recipientDoc && nfe.recipientDoc !== out.tenantCnpj) {
    warnings.push(`Esta nota foi emitida para outro destinatário (${nfe.recipientDoc}).`);
  }
  if (out.alreadyImportedAt) warnings.push('Esta nota já foi lançada anteriormente.');

  res.json({
    ...nfe,
    items: out.items,
    supplierRegistered: !!out.supplierId,
    alreadyImported: !!out.alreadyImportedAt,
    warnings,
  });
});

const itemSchema = z
  .object({
    supplierCode: z.string().max(60),
    description: z.string().min(1).max(200),
    qty: z.number().positive(),
    unitPrice: z.number().min(0),
    total: z.number().min(0),
    factor: z.number().positive().default(1),
    productId: z.string().uuid().optional(),
    newProduct: z
      .object({
        sku: z.string().trim().min(1).max(40),
        barcode: z.string().trim().max(20).optional().nullable(),
        name: z.string().trim().min(2).max(120),
        unit: z.string().trim().min(1).max(6).default('UN'),
        price: z.number().min(0),
      })
      .optional(),
  })
  .refine((i) => !!i.productId !== !!i.newProduct, 'Cada item precisa de um produto existente OU de um produto novo');

const registerSchema = z.object({
  accessKey: z.string().regex(/^\d{44}$/).nullable().optional(),
  number: z.string().max(20),
  series: z.string().max(5).optional(),
  issueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  total: z.number().min(0),
  supplier: z.object({
    doc: z.string().max(14),
    name: z.string().min(1).max(150),
    tradeName: z.string().max(150).optional(),
    ie: z.string().max(20).optional(),
    phone: z.string().max(30).optional(),
    zip: z.string().max(10).optional(),
    street: z.string().max(150).optional(),
    number: z.string().max(20).optional(),
    district: z.string().max(80).optional(),
    city: z.string().max(80).optional(),
    state: z.string().max(2).optional(),
  }),
  items: z.array(itemSchema).min(1),
  installments: z.array(z.object({ document: z.string().max(40), dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), amount: z.number().positive() })),
});

/** POST /purchases — grava a nota (transação única no banco: app.register_purchase) */
purchasesRouter.post('/', async (req, res) => {
  const b = registerSchema.parse(req.body);
  const id = await db(req, async (c) => (await c.query('SELECT app.register_purchase($1::jsonb) AS id', [JSON.stringify(b)])).rows[0].id);
  res.status(201).json({ id });
});

/** GET /purchases — notas lançadas */
purchasesRouter.get('/', async (req, res) => {
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT pu.*, p.name AS supplier_name, p.doc AS supplier_doc, u.full_name AS user_name
           FROM app.purchases pu
           LEFT JOIN app.partners p ON p.id = pu.partner_id
           LEFT JOIN app.users u ON u.id = pu.created_by
          ORDER BY pu.created_at DESC LIMIT 200`,
      )
    ).rows,
  );
  res.json(
    rows.map((r: any) => ({
      id: r.id,
      number: r.number,
      series: r.series,
      accessKey: r.access_key,
      issueDate: r.issue_date,
      total: Number(r.total),
      itemsCount: r.items_count,
      supplierName: r.supplier_name,
      supplierDoc: r.supplier_doc,
      createdAt: r.created_at,
      user: r.user_name,
    })),
  );
});
