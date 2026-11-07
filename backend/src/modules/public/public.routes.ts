import { Router } from 'express';
import { publicQuery } from '../../db/pool';
import { HttpError } from '../../middleware/errors';

/**
 * GET /public/logos/:tenantId — serve a logo guardada no banco (STORAGE_DRIVER=db).
 * Público porque a tela de login mostra a logo antes de autenticar.
 * Cache longo: a URL muda (?v=) sempre que a logo é trocada.
 */
export const publicRouter = Router();

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** GET /public/products/:id/image — foto do produto (PDV, cadastro, OS) */
publicRouter.get('/products/:id/image', async (req, res) => {
  const id = String(req.params.id);
  if (!UUID.test(id)) throw new HttpError(400, 'ID_INVALIDO', 'Identificador inválido');
  const { rows } = await publicQuery('SELECT content_type, data, updated_at FROM app.public_product_image($1)', [id]);
  const img = rows[0];
  if (!img) throw new HttpError(404, 'SEM_FOTO', 'Produto sem foto');
  res
    .set('Content-Type', img.content_type)
    .set('Cache-Control', 'public, max-age=31536000, immutable')
    .send(img.data);
});

publicRouter.get('/arts/:id', async (req, res) => {
  const id = String(req.params.id);
  if (!UUID.test(id)) throw new HttpError(400, 'ID_INVALIDO', 'Identificador inválido');
  const { rows } = await publicQuery('SELECT content_type, data FROM app.public_order_art($1)', [id]);
  const img = rows[0];
  if (!img) throw new HttpError(404, 'SEM_ARTE', 'Arte não encontrada');
  res.set('Content-Type', img.content_type).set('Cache-Control', 'public, max-age=31536000, immutable').send(img.data);
});

publicRouter.get('/logos/:tenantId', async (req, res) => {
  const id = String(req.params.tenantId);
  if (!UUID.test(id)) throw new HttpError(400, 'ID_INVALIDO', 'Identificador inválido');
  const { rows } = await publicQuery('SELECT content_type, data, updated_at FROM app.public_tenant_logo($1)', [id]);
  const logo = rows[0];
  if (!logo) throw new HttpError(404, 'SEM_LOGO', 'Empresa sem logo');
  res
    .set('Content-Type', logo.content_type)
    .set('Cache-Control', 'public, max-age=31536000, immutable')
    .set('Last-Modified', new Date(logo.updated_at).toUTCString())
    .send(logo.data);
});
