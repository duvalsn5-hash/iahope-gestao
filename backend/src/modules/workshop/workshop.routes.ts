import { Router } from 'express';
import { z } from 'zod';
import { db, requireAuth, requireModule, requireRole } from '../../middleware/auth';
import { HttpError } from '../../middleware/errors';
import { absoluteUrl } from '../auth/auth.routes';

/**
 * Módulo OFICINA (motos): motos, tabela de mão de obra, ordens de serviço,
 * fechamento no caixa, comissões e lembretes de revisão.
 */
export const workshopRouter = Router();
workshopRouter.use(requireAuth, requireModule('OFICINA'));

const STAFF = ['ADMIN', 'GERENTE', 'CAIXA', 'MECANICO', 'OPERADOR'] as const;
const MANAGE = ['ADMIN', 'GERENTE'] as const;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const num = (v: any) => (v == null ? null : Number(v));
const plateOf = (v: string) => v.toUpperCase().replace(/[^A-Z0-9]/g, '');

// ============================================================== MOTOS
const mapVehicle = (v: any) => ({
  id: v.id,
  customerId: v.customer_id,
  customerName: v.customer_name,
  customerPhone: v.customer_phone,
  plate: v.plate,
  brand: v.brand,
  model: v.model,
  year: v.year,
  color: v.color,
  km: v.km,
  chassis: v.chassis,
  notes: v.notes,
  isActive: v.is_active,
  lastServiceAt: v.last_service_at ?? null,
  openOrders: v.open_orders != null ? Number(v.open_orders) : undefined,
});

/** GET /workshop/vehicles?q=&customerId= — busca por placa, modelo ou cliente */
workshopRouter.get('/vehicles', requireRole(...STAFF), async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const customer = /^[0-9a-f-]{36}$/i.test(String(req.query.customerId)) ? String(req.query.customerId) : null;
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT v.*, p.name AS customer_name, p.phone AS customer_phone,
                (SELECT max(delivered_at) FROM app.work_orders w WHERE w.vehicle_id = v.id AND w.status = 'ENTREGUE') AS last_service_at,
                (SELECT count(*) FROM app.work_orders w WHERE w.vehicle_id = v.id AND w.status NOT IN ('ENTREGUE','CANCELADA')) AS open_orders
           FROM app.vehicles v JOIN app.partners p ON p.id = v.customer_id
          WHERE v.is_active
            AND ($2::uuid IS NULL OR v.customer_id = $2::uuid)
            AND ($1 = '' OR v.plate LIKE '%' || upper(regexp_replace($1, '[^A-Za-z0-9]', '', 'g')) || '%'
                 OR v.model ILIKE '%' || $1 || '%' OR v.brand ILIKE '%' || $1 || '%' OR p.name ILIKE '%' || $1 || '%')
          ORDER BY v.updated_at DESC LIMIT 200`,
        [q, customer],
      )
    ).rows,
  );
  res.json(rows.map(mapVehicle));
});

const vehicleSchema = z.object({
  customerId: z.string().uuid(),
  plate: z.string().transform(plateOf).refine((p) => /^[A-Z0-9]{5,8}$/.test(p), 'Placa inválida'),
  brand: z.string().trim().max(40).optional().nullable(),
  model: z.string().trim().min(1).max(80),
  year: z.number().int().min(1950).max(2100).optional().nullable(),
  color: z.string().trim().max(30).optional().nullable(),
  km: z.number().int().min(0).optional().nullable(),
  chassis: z.string().trim().max(30).optional().nullable(),
  notes: z.string().max(500).optional().nullable(),
});

workshopRouter.post('/vehicles', requireRole(...STAFF), async (req, res) => {
  const b = vehicleSchema.parse(req.body);
  const v = await db(req, async (c) =>
    (
      await c.query(
        `INSERT INTO app.vehicles (customer_id, plate, brand, model, year, color, km, chassis, notes)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
        [b.customerId, b.plate, b.brand || null, b.model, b.year ?? null, b.color || null, b.km ?? null, b.chassis || null, b.notes || null],
      )
    ).rows[0],
  );
  res.status(201).json(mapVehicle(v));
});

workshopRouter.put('/vehicles/:id', requireRole(...STAFF), async (req, res) => {
  const b = vehicleSchema.parse(req.body);
  const v = await db(req, async (c) =>
    (
      await c.query(
        `UPDATE app.vehicles SET customer_id=$2, plate=$3, brand=$4, model=$5, year=$6, color=$7, km=$8, chassis=$9, notes=$10
          WHERE id = $1 RETURNING *`,
        [req.params.id, b.customerId, b.plate, b.brand || null, b.model, b.year ?? null, b.color || null, b.km ?? null, b.chassis || null, b.notes || null],
      )
    ).rows[0],
  );
  if (!v) throw new HttpError(404, 'NAO_ENCONTRADO', 'Moto não encontrada');
  res.json(mapVehicle(v));
});

// ============================================================== MÃO DE OBRA
const mapService = (s: any) => ({ id: s.id, name: s.name, price: Number(s.price), estMinutes: s.est_minutes, isActive: s.is_active });

workshopRouter.get('/services', requireRole(...STAFF), async (req, res) => {
  const q = String(req.query.q ?? '').trim();
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT * FROM app.service_catalog WHERE ($2 OR is_active) AND ($1 = '' OR name ILIKE '%' || $1 || '%') ORDER BY name`,
        [q, req.query.all === '1'],
      )
    ).rows,
  );
  res.json(rows.map(mapService));
});

const serviceSchema = z.object({
  name: z.string().trim().min(2).max(120),
  price: z.number().min(0),
  estMinutes: z.number().int().positive().optional().nullable(),
  isActive: z.boolean().default(true),
});

workshopRouter.post('/services', requireRole(...MANAGE), async (req, res) => {
  const b = serviceSchema.parse(req.body);
  const s = await db(req, async (c) =>
    (await c.query('INSERT INTO app.service_catalog (name, price, est_minutes, is_active) VALUES ($1,$2,$3,$4) RETURNING *', [
      b.name, b.price, b.estMinutes ?? null, b.isActive,
    ])).rows[0],
  );
  res.status(201).json(mapService(s));
});

workshopRouter.put('/services/:id', requireRole(...MANAGE), async (req, res) => {
  const b = serviceSchema.parse(req.body);
  const s = await db(req, async (c) =>
    (await c.query('UPDATE app.service_catalog SET name=$2, price=$3, est_minutes=$4, is_active=$5 WHERE id=$1 RETURNING *', [
      req.params.id, b.name, b.price, b.estMinutes ?? null, b.isActive,
    ])).rows[0],
  );
  if (!s) throw new HttpError(404, 'NAO_ENCONTRADO', 'Serviço não encontrado');
  res.json(mapService(s));
});

/** Tabela inicial de serviços comuns de moto (preços de exemplo, a oficina ajusta) */
const DEFAULT_SERVICES: [string, number, number][] = [
  ['Troca de óleo', 25, 20],
  ['Revisão geral', 120, 120],
  ['Troca de relação (kit transmissão)', 60, 60],
  ['Regulagem de freio', 25, 20],
  ['Troca de pastilha de freio', 30, 30],
  ['Troca de pneu', 25, 30],
  ['Conserto de câmara de ar', 20, 20],
  ['Limpeza de carburador', 80, 60],
  ['Limpeza de bico injetor', 90, 60],
  ['Regulagem de válvulas', 70, 60],
  ['Troca de vela', 15, 10],
  ['Troca de cabo de embreagem', 30, 30],
  ['Troca de cabo de acelerador', 30, 30],
  ['Troca de bateria', 15, 10],
  ['Revisão elétrica', 60, 60],
  ['Troca de óleo da suspensão', 80, 60],
  ['Troca de retentor da bengala', 90, 90],
  ['Alinhamento de roda / raiação', 50, 60],
  ['Lavagem', 30, 30],
  ['Diagnóstico (scanner)', 50, 30],
];

workshopRouter.post('/services/defaults', requireRole(...MANAGE), async (req, res) => {
  const added = await db(req, async (c) => {
    let n = 0;
    for (const [name, price, min] of DEFAULT_SERVICES) {
      const r = await c.query(
        `INSERT INTO app.service_catalog (name, price, est_minutes) VALUES ($1,$2,$3)
         ON CONFLICT (tenant_id, lower(name)) DO NOTHING`,
        [name, price, min],
      );
      n += r.rowCount ?? 0;
    }
    return n;
  });
  res.json({ added });
});

// ============================================================== ORDENS DE SERVIÇO
const STATUSES = ['ABERTA', 'ORCAMENTO', 'APROVADA', 'EM_EXECUCAO', 'PRONTA', 'ENTREGUE', 'CANCELADA'] as const;

const mapOrderRow = (o: any) => ({
  id: o.id,
  number: Number(o.number),
  status: o.status,
  customerId: o.customer_id,
  customerName: o.customer_name,
  customerPhone: o.customer_phone,
  vehicleId: o.vehicle_id,
  plate: o.plate,
  vehicleLabel: [o.brand, o.model, o.year].filter(Boolean).join(' '),
  mechanicId: o.mechanic_id,
  mechanicName: o.mechanic_name,
  complaint: o.complaint,
  total: num(o.items_total) != null ? Number(o.items_total) - Number(o.discount) : null,
  openedAt: o.opened_at,
  promisedAt: o.promised_at,
  deliveredAt: o.delivered_at,
});

const ORDER_SELECT = `
  SELECT w.*, p.name AS customer_name, p.phone AS customer_phone, p.doc AS customer_doc,
         v.plate, v.brand, v.model, v.year, v.color, v.km AS vehicle_km,
         u.full_name AS mechanic_name,
         (SELECT coalesce(sum(total), 0) FROM app.work_order_items i WHERE i.work_order_id = w.id) AS items_total
    FROM app.work_orders w
    JOIN app.partners p ON p.id = w.customer_id
    JOIN app.vehicles v ON v.id = w.vehicle_id
    LEFT JOIN app.users u ON u.id = w.mechanic_id`;

/** GET /workshop/orders?status=ABERTAS|ENTREGUES|CANCELADAS|<STATUS>&q= */
workshopRouter.get('/orders', requireRole(...STAFF), async (req, res) => {
  const status = String(req.query.status ?? 'ABERTAS');
  const q = String(req.query.q ?? '').trim();
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `${ORDER_SELECT}
          WHERE CASE $1
                  WHEN 'ABERTAS' THEN w.status NOT IN ('ENTREGUE','CANCELADA')
                  WHEN 'ENTREGUES' THEN w.status = 'ENTREGUE'
                  WHEN 'CANCELADAS' THEN w.status = 'CANCELADA'
                  WHEN 'TODAS' THEN true
                  ELSE w.status = $1 END
            AND ($2 = '' OR w.number::text = $2 OR v.plate LIKE '%' || upper(regexp_replace($2, '[^A-Za-z0-9]', '', 'g')) || '%'
                 OR p.name ILIKE '%' || $2 || '%' OR v.model ILIKE '%' || $2 || '%')
            AND ($3 = '' OR w.mechanic_id::text = $3)
          ORDER BY CASE w.status WHEN 'PRONTA' THEN 0 WHEN 'APROVADA' THEN 1 WHEN 'EM_EXECUCAO' THEN 2
                                 WHEN 'ORCAMENTO' THEN 3 WHEN 'ABERTA' THEN 4 ELSE 5 END, w.opened_at DESC
          LIMIT 300`,
        // mecânico vê só as OS dele
        [status, q, req.auth!.role === 'MECANICO' ? req.auth!.sub : ''],
      )
    ).rows,
  );
  res.json(rows.map(mapOrderRow));
});

/** GET /workshop/summary — contagem por andamento (quadro da oficina) */
workshopRouter.get('/summary', requireRole(...STAFF), async (req, res) => {
  const r = await db(req, async (c) =>
    (
      await c.query(`
        SELECT status, count(*)::int AS n FROM app.work_orders
         WHERE status NOT IN ('ENTREGUE','CANCELADA') OR delivered_at >= date_trunc('day', now())
         GROUP BY status`)
    ).rows,
  );
  res.json(Object.fromEntries(r.map((x: any) => [x.status, x.n])));
});

async function loadOrder(c: any, id: string) {
  const o = (await c.query(`${ORDER_SELECT} WHERE w.id = $1`, [id])).rows[0];
  if (!o) throw new HttpError(404, 'NAO_ENCONTRADO', 'OS não encontrada');
  const items = (
    await c.query(
      `SELECT i.*, p.image_url, p.stock_qty, p.unit, u.full_name AS mechanic_name
         FROM app.work_order_items i
         LEFT JOIN app.products p ON p.id = i.product_id
         LEFT JOIN app.users u ON u.id = i.mechanic_id
        WHERE i.work_order_id = $1 ORDER BY i.kind, i.id`,
      [id],
    )
  ).rows;
  const events = (
    await c.query(
      `SELECT e.status, e.note, e.created_at, u.full_name AS user_name
         FROM app.work_order_events e LEFT JOIN app.users u ON u.id = e.user_id
        WHERE e.work_order_id = $1 ORDER BY e.created_at`,
      [id],
    )
  ).rows;
  const parts = items.filter((i: any) => i.kind === 'PECA').reduce((a: number, i: any) => a + Number(i.total), 0);
  const labor = items.filter((i: any) => i.kind === 'SERVICO').reduce((a: number, i: any) => a + Number(i.total), 0);
  return {
    ...mapOrderRow(o),
    customerDoc: o.customer_doc,
    vehicle: { id: o.vehicle_id, plate: o.plate, brand: o.brand, model: o.model, year: o.year, color: o.color, km: o.vehicle_km },
    diagnosis: o.diagnosis,
    kmIn: o.km_in,
    fuelLevel: o.fuel_level,
    checklist: o.checklist ?? {},
    discount: Number(o.discount),
    warrantyDays: o.warranty_days,
    nextServiceDate: o.next_service_date,
    nextServiceKm: o.next_service_km,
    notes: o.notes,
    saleId: o.sale_id,
    approvedAt: o.approved_at,
    finishedAt: o.finished_at,
    partsTotal: Math.round(parts * 100) / 100,
    laborTotal: Math.round(labor * 100) / 100,
    subtotal: Math.round((parts + labor) * 100) / 100,
    total: Math.round((parts + labor - Number(o.discount)) * 100) / 100,
    items: items.map((i: any) => ({
      id: Number(i.id),
      kind: i.kind,
      productId: i.product_id,
      serviceId: i.service_id,
      description: i.description,
      qty: Number(i.qty),
      unitPrice: Number(i.unit_price),
      total: Number(i.total),
      mechanicId: i.mechanic_id,
      mechanicName: i.mechanic_name,
      imageUrl: absoluteUrl(i.image_url),
      stockQty: num(i.stock_qty),
      unit: i.unit,
    })),
    events: events.map((e: any) => ({ status: e.status, note: e.note, createdAt: e.created_at, user: e.user_name })),
  };
}

workshopRouter.get('/orders/:id', requireRole(...STAFF), async (req, res) => {
  res.json(await db(req, (c) => loadOrder(c, String(req.params.id))));
});

const checklistSchema = z.record(z.string().max(60), z.union([z.boolean(), z.string().max(200)]));
const FUEL = z.enum(['RESERVA', '1/4', '1/2', '3/4', 'CHEIO']);

const openSchema = z.object({
  customerId: z.string().uuid(),
  vehicleId: z.string().uuid(),
  complaint: z.string().trim().max(2000).optional().nullable(),
  kmIn: z.number().int().min(0).optional().nullable(),
  fuelLevel: FUEL.optional().nullable(),
  checklist: checklistSchema.default({}),
  mechanicId: z.string().uuid().optional().nullable(),
  promisedAt: z.string().datetime({ offset: true }).optional().nullable(),
});

/** POST /workshop/orders — abre a OS (recepção da moto) */
workshopRouter.post('/orders', requireRole(...STAFF), async (req, res) => {
  const b = openSchema.parse(req.body);
  const o = await db(req, async (c) => {
    const id = (
      await c.query('SELECT app.open_work_order($1,$2,$3,$4,$5,$6::jsonb,$7,$8) AS id', [
        b.customerId, b.vehicleId, b.complaint || null, b.kmIn ?? null, b.fuelLevel ?? null,
        JSON.stringify(b.checklist), b.mechanicId ?? null, b.promisedAt ?? null,
      ])
    ).rows[0].id;
    return loadOrder(c, id);
  });
  res.status(201).json(o);
});

const itemSchema = z.object({
  kind: z.enum(['PECA', 'SERVICO']),
  productId: z.string().uuid().optional().nullable(),
  serviceId: z.string().uuid().optional().nullable(),
  description: z.string().trim().min(1).max(200),
  qty: z.number().positive(),
  unitPrice: z.number().min(0),
  mechanicId: z.string().uuid().optional().nullable(),
});

const updateSchema = z.object({
  complaint: z.string().trim().max(2000).optional().nullable(),
  diagnosis: z.string().trim().max(2000).optional().nullable(),
  kmIn: z.number().int().min(0).optional().nullable(),
  fuelLevel: FUEL.optional().nullable(),
  checklist: checklistSchema.default({}),
  mechanicId: z.string().uuid().optional().nullable(),
  promisedAt: z.string().datetime({ offset: true }).optional().nullable(),
  discount: z.number().min(0).default(0),
  warrantyDays: z.number().int().min(0).max(3650).default(90),
  notes: z.string().max(2000).optional().nullable(),
  items: z.array(itemSchema).max(200),
});

/** PUT /workshop/orders/:id — salva dados, peças e serviços (enquanto não entregue) */
workshopRouter.put('/orders/:id', requireRole(...STAFF), async (req, res) => {
  const b = updateSchema.parse(req.body);
  const o = await db(req, async (c) => {
    const cur = (await c.query('SELECT status FROM app.work_orders WHERE id = $1 FOR UPDATE', [req.params.id])).rows[0];
    if (!cur) throw new HttpError(404, 'NAO_ENCONTRADO', 'OS não encontrada');
    if (['ENTREGUE', 'CANCELADA'].includes(cur.status)) throw new HttpError(422, 'OS_FECHADA', 'OS entregue ou cancelada não pode ser alterada');
    await c.query(
      `UPDATE app.work_orders SET complaint=$2, diagnosis=$3, km_in=$4, fuel_level=$5, checklist=$6::jsonb, mechanic_id=$7,
              promised_at=$8, discount=$9, warranty_days=$10, notes=$11
        WHERE id = $1`,
      [req.params.id, b.complaint || null, b.diagnosis || null, b.kmIn ?? null, b.fuelLevel ?? null, JSON.stringify(b.checklist),
        b.mechanicId ?? null, b.promisedAt ?? null, b.discount, b.warrantyDays, b.notes || null],
    );
    await c.query('DELETE FROM app.work_order_items WHERE work_order_id = $1', [req.params.id]);
    for (const it of b.items) {
      if (it.kind === 'PECA' && !it.productId) throw new HttpError(400, 'VALIDACAO', `Peça "${it.description}" sem produto do estoque`);
      await c.query(
        `INSERT INTO app.work_order_items (work_order_id, kind, product_id, service_id, description, qty, unit_price, total, mechanic_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,round($6::numeric * $7::numeric, 2),$8)`,
        [req.params.id, it.kind, it.kind === 'PECA' ? it.productId : null, it.kind === 'SERVICO' ? it.serviceId ?? null : null,
          it.description, it.qty, it.unitPrice, it.mechanicId ?? null],
      );
    }
    return loadOrder(c, String(req.params.id));
  });
  res.json(o);
});

/** POST /workshop/orders/:id/status { status, note } — andamento */
workshopRouter.post('/orders/:id/status', requireRole(...STAFF), async (req, res) => {
  const b = z.object({ status: z.enum(STATUSES), note: z.string().max(500).optional() }).parse(req.body);
  if (b.status === 'CANCELADA' && !['ADMIN', 'GERENTE', 'SUPER_ADMIN'].includes(req.auth!.role)) {
    throw new HttpError(403, 'SEM_PERMISSAO', 'Só gerente ou administrador cancela OS');
  }
  const o = await db(req, async (c) => {
    await c.query('SELECT app.set_work_order_status($1, $2, $3)', [req.params.id, b.status, b.note ?? null]);
    return loadOrder(c, String(req.params.id));
  });
  res.json(o);
});

const closeSchema = z.object({
  payments: z
    .array(z.object({ method: z.enum(['DINHEIRO', 'PIX', 'DEBITO', 'CREDITO', 'OUTROS', 'PRAZO']), amount: z.number().positive() }))
    .min(1),
  dueDays: z.number().int().min(0).max(365).default(30),
  nextServiceDate: z.string().regex(DATE).optional().nullable(),
  nextServiceKm: z.number().int().min(0).optional().nullable(),
});

/** POST /workshop/orders/:id/close — recebe no caixa e entrega a moto. Devolve o id da venda (cupom em /pos/sales/:id) */
workshopRouter.post('/orders/:id/close', requireRole('ADMIN', 'GERENTE', 'CAIXA'), async (req, res) => {
  const b = closeSchema.parse(req.body);
  const r = await db(req, async (c) => {
    const saleId = (
      await c.query('SELECT app.close_work_order($1, $2::jsonb, $3, $4, $5) AS id', [
        req.params.id, JSON.stringify(b.payments), b.dueDays, b.nextServiceDate ?? null, b.nextServiceKm ?? null,
      ])
    ).rows[0].id;
    return { saleId, order: await loadOrder(c, String(req.params.id)) };
  });
  res.json(r);
});

/** GET /workshop/vehicles/:id/history — tudo que já foi feito na moto */
workshopRouter.get('/vehicles/:id/history', requireRole(...STAFF), async (req, res) => {
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `${ORDER_SELECT} WHERE w.vehicle_id = $1 ORDER BY w.opened_at DESC LIMIT 100`,
        [req.params.id],
      )
    ).rows,
  );
  const items = await db(req, async (c) =>
    (
      await c.query(
        `SELECT i.work_order_id, i.kind, i.description, i.qty FROM app.work_order_items i
           JOIN app.work_orders w ON w.id = i.work_order_id
          WHERE w.vehicle_id = $1 AND w.status = 'ENTREGUE' ORDER BY i.id`,
        [req.params.id],
      )
    ).rows,
  );
  res.json(
    rows.map((o: any) => ({
      ...mapOrderRow(o),
      kmIn: o.km_in,
      items: items.filter((i: any) => i.work_order_id === o.id).map((i: any) => ({ kind: i.kind, description: i.description, qty: Number(i.qty) })),
    })),
  );
});

/** GET /workshop/commissions?from=&to= — comissão sobre a mão de obra das OS entregues */
workshopRouter.get('/commissions', requireRole(...MANAGE), async (req, res) => {
  const from = DATE.test(String(req.query.from)) ? String(req.query.from) : null;
  const to = DATE.test(String(req.query.to)) ? String(req.query.to) : null;
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT u.id, u.full_name, u.commission_pct,
                count(DISTINCT w.id)::int AS orders,
                coalesce(sum(i.total), 0) AS labor
           FROM app.work_orders w
           JOIN app.work_order_items i ON i.work_order_id = w.id AND i.kind = 'SERVICO'
           JOIN app.users u ON u.id = coalesce(i.mechanic_id, w.mechanic_id)
          WHERE w.status = 'ENTREGUE'
            AND ($1::date IS NULL OR w.delivered_at >= $1::date)
            AND ($2::date IS NULL OR w.delivered_at < $2::date + 1)
          GROUP BY u.id ORDER BY labor DESC`,
        [from, to],
      )
    ).rows,
  );
  res.json(
    rows.map((r: any) => ({
      mechanicId: r.id,
      name: r.full_name,
      commissionPct: Number(r.commission_pct),
      orders: r.orders,
      labor: Number(r.labor),
      commission: Math.round(Number(r.labor) * Number(r.commission_pct)) / 100,
    })),
  );
});

/** GET /workshop/reminders?days=15 — revisões que vencem (pela data marcada na entrega) */
workshopRouter.get('/reminders', requireRole(...STAFF), async (req, res) => {
  const days = Math.min(Math.max(Number(req.query.days ?? 15) || 15, 1), 120);
  const rows = await db(req, async (c) =>
    (
      await c.query(
        `SELECT DISTINCT ON (w.vehicle_id) w.vehicle_id, w.next_service_date, w.next_service_km, w.number, w.delivered_at,
                v.plate, v.brand, v.model, v.km, p.id AS customer_id, p.name AS customer_name, p.phone AS customer_phone
           FROM app.work_orders w
           JOIN app.vehicles v ON v.id = w.vehicle_id
           JOIN app.partners p ON p.id = w.customer_id
          WHERE w.status = 'ENTREGUE' AND w.next_service_date IS NOT NULL
          ORDER BY w.vehicle_id, w.delivered_at DESC`,
      )
    ).rows,
  );
  const limit = new Date(Date.now() + days * 864e5).toISOString().slice(0, 10);
  res.json(
    rows
      .filter((r: any) => String(r.next_service_date) <= limit)
      .sort((a: any, b: any) => String(a.next_service_date).localeCompare(String(b.next_service_date)))
      .map((r: any) => ({
        vehicleId: r.vehicle_id,
        plate: r.plate,
        vehicleLabel: [r.brand, r.model].filter(Boolean).join(' '),
        km: r.km,
        customerId: r.customer_id,
        customerName: r.customer_name,
        customerPhone: r.customer_phone,
        nextServiceDate: r.next_service_date,
        nextServiceKm: r.next_service_km,
        lastOrderNumber: Number(r.number),
      })),
  );
});
