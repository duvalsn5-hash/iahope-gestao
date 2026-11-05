-- =============================================================================
--  IAHOPE GESTÃO — MÓDULO OFICINA (motos) + FOTO DE PRODUTO + MECÂNICOS
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  Ordem: 00 → 01 → 02 → 03 → 04  (rode UMA vez, como dono do banco)
--  Tudo isolado por CNPJ (RLS); funções rodam como invocador.
-- =============================================================================

-- Novo perfil (precisa ficar fora da transação)
ALTER TYPE app.user_role ADD VALUE IF NOT EXISTS 'MECANICO';

BEGIN;
SET search_path = app, public;

-- -----------------------------------------------------------------------------
--  Módulo OFICINA no catálogo de módulos
-- -----------------------------------------------------------------------------
ALTER TABLE app.tenants DROP CONSTRAINT tenants_modules_valid;
ALTER TABLE app.tenants ADD CONSTRAINT tenants_modules_valid
  CHECK (modules <@ ARRAY['PDV','PRODUTIVIDADE','FINANCEIRO','COMPRAS','BALANCA','OFICINA']::text[]);

-- Comissão do mecânico (% sobre a mão de obra)
ALTER TABLE app.users ADD COLUMN commission_pct numeric(5,2) NOT NULL DEFAULT 0
  CHECK (commission_pct >= 0 AND commission_pct <= 100);

-- =============================================================================
--  FOTO DO PRODUTO (guardada no banco, como a logo)
-- =============================================================================
ALTER TABLE app.products ADD COLUMN image_url text;

CREATE TABLE app.product_images (
  product_id   uuid PRIMARY KEY REFERENCES app.products(id) ON DELETE CASCADE,
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  content_type text NOT NULL CHECK (content_type IN ('image/png','image/jpeg','image/webp')),
  data         bytea NOT NULL CHECK (octet_length(data) <= 1024 * 1024),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_product_images_tenant ON app.product_images(tenant_id);
CREATE TRIGGER trg_product_images_tenant BEFORE INSERT OR UPDATE ON app.product_images
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Leitura pública só da imagem (a URL tem o UUID do produto, que não é adivinhável)
CREATE OR REPLACE FUNCTION app.public_product_image(p_product_id uuid)
RETURNS TABLE (content_type text, data bytea, updated_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT i.content_type, i.data, i.updated_at FROM app.product_images i WHERE i.product_id = p_product_id
$$;
REVOKE ALL ON FUNCTION app.public_product_image(uuid) FROM PUBLIC;

-- =============================================================================
--  OFICINA
-- =============================================================================
-- Motos (ligadas ao cliente)
CREATE TABLE app.vehicles (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  customer_id  uuid NOT NULL REFERENCES app.partners(id),
  plate        text NOT NULL CHECK (plate ~ '^[A-Z0-9]{5,8}$'),   -- sem traço, maiúsculas
  brand        text,
  model        text NOT NULL,
  year         int CHECK (year IS NULL OR year BETWEEN 1950 AND 2100),
  color        text,
  km           int CHECK (km IS NULL OR km >= 0),
  chassis      text,
  notes        text,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, plate)
);
CREATE INDEX ix_vehicles_customer ON app.vehicles(tenant_id, customer_id);
CREATE TRIGGER trg_vehicles_updated BEFORE UPDATE ON app.vehicles
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_vehicles_tenant BEFORE INSERT OR UPDATE ON app.vehicles
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Tabela de mão de obra
CREATE TABLE app.service_catalog (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  name         text NOT NULL,
  price        numeric(14,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  est_minutes  int CHECK (est_minutes IS NULL OR est_minutes > 0),
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_service_catalog_name ON app.service_catalog(tenant_id, lower(name));
CREATE TRIGGER trg_service_catalog_updated BEFORE UPDATE ON app.service_catalog
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_service_catalog_tenant BEFORE INSERT OR UPDATE ON app.service_catalog
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Ordens de serviço
--  ABERTA → ORCAMENTO → APROVADA → EM_EXECUCAO → PRONTA → ENTREGUE   (ou CANCELADA)
CREATE TABLE app.work_orders (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  number            bigint NOT NULL,
  status            text NOT NULL DEFAULT 'ABERTA'
                    CHECK (status IN ('ABERTA','ORCAMENTO','APROVADA','EM_EXECUCAO','PRONTA','ENTREGUE','CANCELADA')),
  customer_id       uuid NOT NULL REFERENCES app.partners(id),
  vehicle_id        uuid NOT NULL REFERENCES app.vehicles(id),
  mechanic_id       uuid REFERENCES app.users(id),
  complaint         text,                                   -- o que o cliente relatou
  diagnosis         text,                                   -- o que o mecânico encontrou
  km_in             int CHECK (km_in IS NULL OR km_in >= 0),
  fuel_level        text CHECK (fuel_level IS NULL OR fuel_level IN ('RESERVA','1/4','1/2','3/4','CHEIO')),
  checklist         jsonb NOT NULL DEFAULT '{}',            -- {"Retrovisores": true, "Riscos": "tanque lado esq."...}
  promised_at       timestamptz,
  discount          numeric(14,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  warranty_days     int NOT NULL DEFAULT 90 CHECK (warranty_days >= 0),
  next_service_date date,
  next_service_km   int,
  notes             text,
  sale_id           uuid REFERENCES app.sales(id),
  opened_at         timestamptz NOT NULL DEFAULT now(),
  approved_at       timestamptz,
  finished_at       timestamptz,
  delivered_at      timestamptz,
  canceled_at       timestamptz,
  created_by        uuid REFERENCES app.users(id),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, number)
);
CREATE INDEX ix_work_orders_status ON app.work_orders(tenant_id, status, opened_at DESC);
CREATE INDEX ix_work_orders_vehicle ON app.work_orders(vehicle_id, opened_at DESC);
CREATE TRIGGER trg_work_orders_updated BEFORE UPDATE ON app.work_orders
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_work_orders_tenant BEFORE INSERT OR UPDATE ON app.work_orders
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.work_order_items (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id      uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  work_order_id  uuid NOT NULL REFERENCES app.work_orders(id) ON DELETE CASCADE,
  kind           text NOT NULL CHECK (kind IN ('PECA','SERVICO')),
  product_id     uuid REFERENCES app.products(id),
  service_id     uuid REFERENCES app.service_catalog(id),
  description    text NOT NULL,
  qty            numeric(14,3) NOT NULL CHECK (qty > 0),
  unit_price     numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  total          numeric(14,2) NOT NULL,
  mechanic_id    uuid REFERENCES app.users(id),
  CHECK (kind = 'SERVICO' OR product_id IS NOT NULL)
);
CREATE INDEX ix_wo_items_order ON app.work_order_items(work_order_id);
CREATE TRIGGER trg_wo_items_tenant BEFORE INSERT OR UPDATE ON app.work_order_items
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Linha do tempo da OS
CREATE TABLE app.work_order_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id      uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  work_order_id  uuid NOT NULL REFERENCES app.work_orders(id) ON DELETE CASCADE,
  status         text NOT NULL,
  note           text,
  user_id        uuid REFERENCES app.users(id),
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_wo_events_order ON app.work_order_events(work_order_id, created_at);
CREATE TRIGGER trg_wo_events_tenant BEFORE INSERT ON app.work_order_events
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Venda gerada pela OS: serviços não têm produto
ALTER TABLE app.sale_items ALTER COLUMN product_id DROP NOT NULL;
ALTER TABLE app.sales ADD COLUMN work_order_id uuid REFERENCES app.work_orders(id);

-- RLS
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['product_images','vehicles','service_catalog','work_orders','work_order_items','work_order_events']
  LOOP
    EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format($f$
      CREATE POLICY %1$s_isolation ON app.%1$s
        USING (app.is_super_admin() OR tenant_id = app.current_tenant_id())
        WITH CHECK (app.is_super_admin() OR tenant_id = app.current_tenant_id())
    $f$, t);
  END LOOP;
END $$;

-- =============================================================================
--  FUNÇÕES
-- =============================================================================

-- Cancelamento de venda: serviços (sem produto) não mexem em estoque
CREATE OR REPLACE FUNCTION app.cancel_sale(p_sale_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM app.financial_entries
              WHERE ref_id = p_sale_id AND origin = 'VENDA' AND paid_amount > 0) THEN
    RAISE EXCEPTION 'Venda a prazo já teve recebimento; estorne no financeiro antes';
  END IF;
  UPDATE app.sales SET status = 'CANCELADA', canceled_at = now()
   WHERE id = p_sale_id AND status = 'FINALIZADA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Venda não encontrada ou já cancelada'; END IF;
  FOR r IN SELECT product_id, qty FROM app.sale_items WHERE sale_id = p_sale_id AND product_id IS NOT NULL LOOP
    UPDATE app.products SET stock_qty = stock_qty + r.qty WHERE id = r.product_id;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (r.product_id, r.qty, 'CANCELAMENTO', p_sale_id, app.current_user_id());
  END LOOP;
  UPDATE app.financial_entries SET status = 'CANCELADO'
   WHERE ref_id = p_sale_id AND origin = 'VENDA' AND status = 'ABERTO';
  -- OS entregue volta para PRONTA
  UPDATE app.work_orders SET status = 'PRONTA', delivered_at = NULL, sale_id = NULL
   WHERE sale_id = p_sale_id;
END $$;

-- Abre uma OS (número sequencial por empresa)
CREATE OR REPLACE FUNCTION app.open_work_order(
  p_customer uuid, p_vehicle uuid, p_complaint text, p_km int, p_fuel text,
  p_checklist jsonb, p_mechanic uuid, p_promised timestamptz)
RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.vehicles WHERE id = p_vehicle AND customer_id = p_customer) THEN
    RAISE EXCEPTION 'Moto não encontrada para este cliente';
  END IF;
  INSERT INTO app.work_orders (id, number, customer_id, vehicle_id, complaint, km_in, fuel_level, checklist,
                               mechanic_id, promised_at, created_by)
  VALUES (v_id, app.next_counter('os'), p_customer, p_vehicle, p_complaint, p_km, p_fuel,
          coalesce(p_checklist, '{}'), p_mechanic, p_promised, app.current_user_id());
  INSERT INTO app.work_order_events (work_order_id, status, note, user_id)
  VALUES (v_id, 'ABERTA', 'OS aberta', app.current_user_id());
  -- atualiza a km da moto
  IF p_km IS NOT NULL THEN
    UPDATE app.vehicles SET km = greatest(coalesce(km, 0), p_km) WHERE id = p_vehicle;
  END IF;
  RETURN v_id;
END $$;

-- Troca o andamento da OS (ENTREGUE só pelo fechamento no caixa)
CREATE OR REPLACE FUNCTION app.set_work_order_status(p_id uuid, p_status text, p_note text) RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE cur text;
BEGIN
  SELECT status INTO cur FROM app.work_orders WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'OS não encontrada'; END IF;
  IF cur IN ('ENTREGUE', 'CANCELADA') THEN RAISE EXCEPTION 'OS já está %', lower(cur); END IF;
  IF p_status NOT IN ('ABERTA','ORCAMENTO','APROVADA','EM_EXECUCAO','PRONTA','CANCELADA') THEN
    RAISE EXCEPTION 'Status inválido (para entregar, feche a OS no caixa)';
  END IF;
  UPDATE app.work_orders
     SET status = p_status,
         approved_at = CASE WHEN p_status = 'APROVADA' THEN coalesce(approved_at, now()) ELSE approved_at END,
         finished_at = CASE WHEN p_status = 'PRONTA' THEN now() ELSE finished_at END,
         canceled_at = CASE WHEN p_status = 'CANCELADA' THEN now() ELSE canceled_at END
   WHERE id = p_id;
  INSERT INTO app.work_order_events (work_order_id, status, note, user_id)
  VALUES (p_id, p_status, p_note, app.current_user_id());
END $$;

-- Fecha a OS no caixa: gera a venda (peças baixam estoque; serviços não),
-- pagamentos, fiado (a receber), e marca ENTREGUE com garantia e próxima revisão.
CREATE OR REPLACE FUNCTION app.close_work_order(
  p_id uuid, p_payments jsonb, p_due_days int DEFAULT 30,
  p_next_date date DEFAULT NULL, p_next_km int DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  o        app.work_orders%ROWTYPE;
  v_sale   uuid := gen_random_uuid();
  v_sess   uuid := app.current_cash_session();
  v_number bigint;
  v_sub    numeric(14,2) := 0;
  v_total  numeric(14,2);
  v_paid   numeric(14,2); v_cash numeric(14,2); v_prazo numeric(14,2);
  it       record;
  v_prod   app.products%ROWTYPE;
BEGIN
  SELECT * INTO o FROM app.work_orders WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'OS não encontrada'; END IF;
  IF o.status IN ('ENTREGUE','CANCELADA') THEN RAISE EXCEPTION 'OS já está %', lower(o.status); END IF;
  IF v_sess IS NULL THEN RAISE EXCEPTION 'Abra o caixa no PDV antes de receber a OS'; END IF;
  IF NOT EXISTS (SELECT 1 FROM app.work_order_items WHERE work_order_id = p_id) THEN
    RAISE EXCEPTION 'OS sem peças nem serviços';
  END IF;

  v_number := app.next_counter('sale');
  INSERT INTO app.sales (id, tenant_id, sale_number, status, cashier_id, customer_id, customer_doc,
                         cash_session_id, work_order_id)
  SELECT v_sale, app.current_tenant_id(), v_number, 'FINALIZADA', app.current_user_id(), o.customer_id, p.doc,
         v_sess, p_id
    FROM app.partners p WHERE p.id = o.customer_id;

  FOR it IN SELECT * FROM app.work_order_items WHERE work_order_id = p_id ORDER BY id LOOP
    IF it.kind = 'PECA' THEN
      SELECT * INTO v_prod FROM app.products WHERE id = it.product_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Peça % não encontrada', it.description; END IF;
      IF v_prod.stock_qty < it.qty THEN
        RAISE EXCEPTION 'Estoque insuficiente para % (disponível: %)', v_prod.name, v_prod.stock_qty;
      END IF;
      UPDATE app.products SET stock_qty = stock_qty - it.qty WHERE id = v_prod.id;
      INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
      VALUES (v_prod.id, -it.qty, 'VENDA', v_sale, app.current_user_id());
    END IF;
    INSERT INTO app.sale_items (sale_id, product_id, description, qty, unit_price, total)
    VALUES (v_sale, it.product_id, CASE WHEN it.kind = 'SERVICO' THEN 'Serviço: ' || it.description ELSE it.description END,
            it.qty, it.unit_price, it.total);
    v_sub := v_sub + it.total;
  END LOOP;

  IF o.discount > v_sub THEN RAISE EXCEPTION 'Desconto maior que o total da OS'; END IF;
  v_total := v_sub - o.discount;

  INSERT INTO app.sale_payments (sale_id, method, amount)
  SELECT v_sale, (x->>'method')::app.payment_method, (x->>'amount')::numeric
    FROM jsonb_array_elements(coalesce(p_payments, '[]')) x;
  SELECT coalesce(sum(amount), 0),
         coalesce(sum(amount) FILTER (WHERE method = 'DINHEIRO'), 0),
         coalesce(sum(amount) FILTER (WHERE method::text = 'PRAZO'), 0)
    INTO v_paid, v_cash, v_prazo FROM app.sale_payments WHERE sale_id = v_sale;
  IF v_paid < v_total THEN RAISE EXCEPTION 'Pagamento insuficiente: total %, pago %', v_total, v_paid; END IF;
  IF v_paid - v_total > v_cash THEN RAISE EXCEPTION 'Troco só pode ser dado em dinheiro'; END IF;
  IF v_prazo > 0 THEN
    INSERT INTO app.financial_entries (kind, partner_id, description, document, due_date, amount, origin, ref_id, created_by)
    VALUES ('RECEBER', o.customer_id, 'OS nº ' || o.number, o.number::text,
            current_date + coalesce(p_due_days, 30), v_prazo, 'VENDA', v_sale, app.current_user_id());
  END IF;

  UPDATE app.sales SET subtotal = v_sub, discount = o.discount, total = v_total, paid = v_paid,
                       change_due = v_paid - v_total
   WHERE id = v_sale;
  UPDATE app.work_orders
     SET status = 'ENTREGUE', delivered_at = now(), sale_id = v_sale,
         finished_at = coalesce(finished_at, now()),
         next_service_date = p_next_date, next_service_km = p_next_km
   WHERE id = p_id;
  INSERT INTO app.work_order_events (work_order_id, status, note, user_id)
  VALUES (p_id, 'ENTREGUE', 'Entregue e recebida no caixa (venda nº ' || v_number || ')', app.current_user_id());
  RETURN v_sale;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_api;

COMMIT;
