import { Router } from 'express';
import { z } from 'zod';
import { db, requireAuth, requireRole } from '../../middleware/auth';

/** Produtividade de descarga hora a hora + ordens logísticas */
export const productivityRouter = Router();
productivityRouter.use(requireAuth);

const recordSchema = z.object({
  hourStart: z.string().datetime({ offset: true }).optional(), // padrão: hora cheia atual
  dock: z.string().trim().min(1).default('GERAL'),
  orderId: z.string().uuid().optional(),
  volumes: z.number().int().min(0),
  weightKg: z.number().min(0).default(0),
  pallets: z.number().int().min(0).default(0),
  teamSize: z.number().int().positive().default(1),
  targetVolumes: z.number().int().min(0).default(0),
  mode: z.enum(['add', 'set']).default('add'), // add = soma ao lançamento da hora; set = sobrescreve
});

/**
 * POST /productivity/hourly
 * Registra (ou acumula) a produção de uma doca na hora. Uma linha por doca/hora.
 */
productivityRouter.post('/hourly', requireRole('ADMIN', 'GERENTE', 'OPERADOR'), async (req, res) => {
  const b = recordSchema.parse(req.body);
  const row = await db(req, async (c) => {
    const r = await c.query(
      `INSERT INTO app.hourly_productivity
         (hour_start, dock, order_id, volumes, weight_kg, pallets, team_size, target_volumes, recorded_by)
       VALUES (date_trunc('hour', coalesce($1::timestamptz, now())), $2, $3, $4, $5, $6, $7, $8, app.current_user_id())
       ON CONFLICT (tenant_id, dock, hour_start) DO UPDATE SET
         volumes   = CASE WHEN $9::text = 'add' THEN app.hourly_productivity.volumes   + EXCLUDED.volumes   ELSE EXCLUDED.volumes END,
         weight_kg = CASE WHEN $9::text = 'add' THEN app.hourly_productivity.weight_kg + EXCLUDED.weight_kg ELSE EXCLUDED.weight_kg END,
         pallets   = CASE WHEN $9::text = 'add' THEN app.hourly_productivity.pallets   + EXCLUDED.pallets   ELSE EXCLUDED.pallets END,
         team_size = EXCLUDED.team_size,
         target_volumes = CASE WHEN EXCLUDED.target_volumes > 0 THEN EXCLUDED.target_volumes
                               ELSE app.hourly_productivity.target_volumes END,
         order_id  = coalesce(EXCLUDED.order_id, app.hourly_productivity.order_id),
         recorded_by = EXCLUDED.recorded_by
       RETURNING *`,
      [b.hourStart ?? null, b.dock, b.orderId ?? null, b.volumes, b.weightKg, b.pallets, b.teamSize, b.targetVolumes, b.mode],
    );
    if (b.orderId && b.volumes > 0) {
      await c.query(
        `UPDATE app.logistics_orders SET unloaded_volumes = unloaded_volumes + $2,
                status = CASE WHEN status = 'AGUARDANDO' THEN 'EM_DESCARGA' ELSE status END,
                started_at = coalesce(started_at, now())
          WHERE id = $1`,
        [b.orderId, b.volumes],
      );
    }
    return r.rows[0];
  });
  res.status(201).json(row);
});

/**
 * GET /productivity/dashboard?date=YYYY-MM-DD
 * Série hora a hora (00h–23h, preenchendo horas vazias com zero) + totais por doca.
 * O app chama a cada 15–30 s para o "tempo real".
 */
productivityRouter.get('/dashboard', async (req, res) => {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(req.query.date)) ? String(req.query.date) : null;
  const tz = 'America/Fortaleza';
  const data = await db(req, async (c) => {
    const hours = (
      await c.query(
        `WITH d AS (SELECT coalesce($1::date, (now() AT TIME ZONE $2)::date) AS dia),
              h AS (SELECT generate_series(0, 23) AS hr)
         SELECT h.hr AS hour,
                coalesce(sum(p.volumes), 0)::int        AS volumes,
                coalesce(sum(p.weight_kg), 0)::float    AS weight_kg,
                coalesce(sum(p.pallets), 0)::int        AS pallets,
                coalesce(sum(p.target_volumes), 0)::int AS target,
                coalesce(sum(p.team_size), 0)::int      AS team
           FROM h CROSS JOIN d
           LEFT JOIN app.hourly_productivity p
             ON (p.hour_start AT TIME ZONE $2)::date = d.dia
            AND extract(hour FROM p.hour_start AT TIME ZONE $2) = h.hr
          GROUP BY h.hr ORDER BY h.hr`,
        [date, tz],
      )
    ).rows;
    const docks = (
      await c.query(
        `SELECT dock, sum(volumes)::int AS volumes, sum(weight_kg)::float AS weight_kg,
                sum(target_volumes)::int AS target, max(hour_start) AS last_hour
           FROM app.hourly_productivity
          WHERE (hour_start AT TIME ZONE $2)::date = coalesce($1::date, (now() AT TIME ZONE $2)::date)
          GROUP BY dock ORDER BY dock`,
        [date, tz],
      )
    ).rows;
    const orders = (
      await c.query(
        `SELECT id, order_number, carrier, vehicle_plate, dock, status, expected_volumes, unloaded_volumes, started_at
           FROM app.logistics_orders WHERE status IN ('AGUARDANDO','EM_DESCARGA') ORDER BY scheduled_at NULLS LAST LIMIT 50`,
      )
    ).rows;
    return { hours, docks, orders };
  });

  const total = data.hours.reduce((a: number, h: any) => a + h.volumes, 0);
  const target = data.hours.reduce((a: number, h: any) => a + h.target, 0);
  const worked = data.hours.filter((h: any) => h.volumes > 0);
  res.json({
    ...data,
    summary: {
      totalVolumes: total,
      totalWeightKg: data.hours.reduce((a: number, h: any) => a + h.weight_kg, 0),
      targetVolumes: target,
      pctTarget: target ? Math.round((1000 * total) / target) / 10 : null,
      avgPerHour: worked.length ? Math.round(total / worked.length) : 0,
      peakHour: worked.sort((a: any, b: any) => b.volumes - a.volumes)[0]?.hour ?? null,
    },
  });
});

const orderSchema = z.object({
  orderNumber: z.string().trim().min(1),
  carrier: z.string().optional(),
  vehiclePlate: z.string().optional(),
  dock: z.string().optional(),
  expectedVolumes: z.number().int().min(0).default(0),
  weightKg: z.number().min(0).default(0),
  scheduledAt: z.string().datetime({ offset: true }).optional(),
  notes: z.string().optional(),
});

/** POST /productivity/orders — nova ordem de descarga */
productivityRouter.post('/orders', requireRole('ADMIN', 'GERENTE', 'OPERADOR'), async (req, res) => {
  const b = orderSchema.parse(req.body);
  const row = await db(req, async (c) =>
    (
      await c.query(
        `INSERT INTO app.logistics_orders (order_number, carrier, vehicle_plate, dock, expected_volumes, weight_kg, scheduled_at, notes, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8, app.current_user_id()) RETURNING *`,
        [b.orderNumber, b.carrier, b.vehiclePlate, b.dock, b.expectedVolumes, b.weightKg, b.scheduledAt, b.notes],
      )
    ).rows[0],
  );
  res.status(201).json(row);
});

/** PATCH /productivity/orders/:id/status */
productivityRouter.patch('/orders/:id/status', requireRole('ADMIN', 'GERENTE', 'OPERADOR'), async (req, res) => {
  const { status } = z.object({ status: z.enum(['AGUARDANDO', 'EM_DESCARGA', 'CONFERIDO', 'FINALIZADO', 'CANCELADO']) }).parse(req.body);
  const row = await db(req, async (c) =>
    (
      await c.query(
        `UPDATE app.logistics_orders SET status = $2::app.order_status,
                started_at  = CASE WHEN $2::text = 'EM_DESCARGA' THEN coalesce(started_at, now()) ELSE started_at END,
                finished_at = CASE WHEN $2::text IN ('FINALIZADO','CANCELADO') THEN now() ELSE finished_at END
          WHERE id = $1 RETURNING *`,
        [req.params.id, status],
      )
    ).rows[0],
  );
  res.json(row);
});
