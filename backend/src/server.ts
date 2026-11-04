/**
 * IAHOPE GESTÃO — API
 * Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
 */
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'node:path';
import { CREDITS, env } from './config/env';
import { errorHandler } from './middleware/errors';
import { authRouter } from './modules/auth/auth.routes';
import { adminRouter } from './modules/admin/admin.routes';
import { companyRouter } from './modules/tenants/company.routes';
import { productivityRouter } from './modules/productivity/productivity.routes';
import { productsRouter } from './modules/products/products.routes';
import { posRouter } from './modules/pos/pos.routes';
import { publicRouter } from './modules/public/public.routes';
import { partnersRouter } from './modules/partners/partners.routes';
import { cashRouter } from './modules/cash/cash.routes';
import { financeRouter } from './modules/finance/finance.routes';
import { purchasesRouter } from './modules/purchases/purchases.routes';
import { assertSafeDbRole } from './db/safety';

export const app = express();

// Render, Railway, Nginx, Caddy, Cloudflare: a API fica atrás de 1 proxy
app.set('trust proxy', 1);

app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } })); // logo carregada pelo app Web
app.use(cors({ origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(',') }));
app.use(express.json({ limit: '2mb' }));
if (env.STORAGE_DRIVER === 'local') {
  app.use('/uploads', express.static(path.resolve(env.UPLOAD_DIR), { maxAge: '7d', index: false }));
}

// /health não toca no banco: monitores de "manter acordado" não gastam as horas do Neon
app.get('/health', (_req, res) => res.json({ ok: true, credits: CREDITS }));
app.use('/public', publicRouter);
app.use('/auth', authRouter);
app.use('/admin', adminRouter);
app.use('/company', companyRouter);
app.use('/products', productsRouter);
app.use('/productivity', productivityRouter);
app.use('/pos', posRouter);
app.use('/partners', partnersRouter);
app.use('/cash', cashRouter);
app.use('/finance', financeRouter);
app.use('/purchases', purchasesRouter);

app.use(errorHandler);

if (require.main === module) {
  assertSafeDbRole()
    .then(() =>
      app.listen(env.PORT, () =>
        console.log(`API em http://0.0.0.0:${env.PORT} · logos: ${env.STORAGE_DRIVER} · ${CREDITS}`),
      ),
    )
    .catch((err) => {
      console.error(err.message);
      process.exit(1);
    });
}
