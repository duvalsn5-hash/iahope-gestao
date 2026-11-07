-- =============================================================================
--  IAHOPE GESTÃO — LOJA DE ROUPAS (grade, trocas/vale, condicional)
--                 + ESTAMPARIA E PERSONALIZADOS (pedidos sob encomenda)
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  Ordem: 00 → 01 → 02 → 03 → 04 → 05 → 06  (rode UMA vez, como dono do banco)
--  Tudo isolado por CNPJ (RLS); funções rodam como invocador.
-- =============================================================================

-- Novas formas de pagamento (precisam ficar fora da transação)
ALTER TYPE app.payment_method ADD VALUE IF NOT EXISTS 'VALE';   -- vale-troca
ALTER TYPE app.payment_method ADD VALUE IF NOT EXISTS 'SINAL';  -- sinal já recebido no pedido

BEGIN;
SET search_path = app, public;

-- -----------------------------------------------------------------------------
--  Módulos MODA e ESTAMPARIA
-- -----------------------------------------------------------------------------
ALTER TABLE app.tenants DROP CONSTRAINT tenants_modules_valid;
ALTER TABLE app.tenants ADD CONSTRAINT tenants_modules_valid
  CHECK (modules <@ ARRAY['PDV','PRODUTIVIDADE','FINANCEIRO','COMPRAS','BALANCA','OFICINA','MODA','ESTAMPARIA']::text[]);

-- Quem já é do ramo ganha o módulo
UPDATE app.tenants SET modules = array_append(modules, 'MODA')
 WHERE business_category = 'MODA' AND NOT 'MODA' = ANY(modules);
UPDATE app.tenants SET modules = array_append(modules, 'ESTAMPARIA')
 WHERE business_category = 'ESTAMPARIA' AND NOT 'ESTAMPARIA' = ANY(modules);

-- =============================================================================
--  GRADE (tamanho × cor): cada combinação é um produto com código próprio
-- =============================================================================
ALTER TABLE app.products
  ADD COLUMN grade_id    uuid,
  ADD COLUMN grade_model text,
  ADD COLUMN size        text CHECK (size IS NULL OR length(size) <= 10),
  ADD COLUMN color       text CHECK (color IS NULL OR length(color) <= 30);
CREATE INDEX ix_products_grade ON app.products(tenant_id, grade_id) WHERE grade_id IS NOT NULL;

-- Código de barras interno EAN-13 (prefixo 29 = uso interno da loja)
CREATE OR REPLACE FUNCTION app.next_internal_ean() RETURNS text
LANGUAGE plpgsql VOLATILE AS $$
DECLARE base text; s int := 0; i int; d int;
BEGIN
  LOOP
    base := '29' || lpad(app.next_counter('ean')::text, 10, '0');
    s := 0;
    FOR i IN 1..12 LOOP
      d := substr(base, i, 1)::int;
      s := s + CASE WHEN i % 2 = 0 THEN d * 3 ELSE d END;
    END LOOP;
    base := base || ((10 - s % 10) % 10)::text;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM app.products WHERE barcode = base);
  END LOOP;
  RETURN base;
END $$;

-- =============================================================================
--  TROCAS E DEVOLUÇÕES + VALE-TROCA
-- =============================================================================
ALTER TABLE app.sale_items ADD COLUMN returned_qty numeric(14,3) NOT NULL DEFAULT 0
  CHECK (returned_qty >= 0 AND returned_qty <= qty);

CREATE TABLE app.store_credits (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  code           text NOT NULL,
  customer_id    uuid REFERENCES app.partners(id),
  amount         numeric(14,2) NOT NULL CHECK (amount > 0),
  balance        numeric(14,2) NOT NULL CHECK (balance >= 0),
  origin_sale_id uuid REFERENCES app.sales(id),
  expires_at     date,
  created_by     uuid REFERENCES app.users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
CREATE TRIGGER trg_store_credits_tenant BEFORE INSERT OR UPDATE ON app.store_credits
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Uso (−) e estorno (+) do vale
CREATE TABLE app.store_credit_moves (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id  uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  credit_id  uuid NOT NULL REFERENCES app.store_credits(id) ON DELETE CASCADE,
  sale_id    uuid REFERENCES app.sales(id),
  amount     numeric(14,2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_credit_moves_credit ON app.store_credit_moves(credit_id);
CREATE TRIGGER trg_credit_moves_tenant BEFORE INSERT ON app.store_credit_moves
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.sale_returns (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  sale_id     uuid NOT NULL REFERENCES app.sales(id),
  amount      numeric(14,2) NOT NULL,
  mode        text NOT NULL CHECK (mode IN ('VALE', 'DINHEIRO')),
  credit_id   uuid REFERENCES app.store_credits(id),
  items       jsonb NOT NULL,
  reason      text,
  user_id     uuid REFERENCES app.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_sale_returns_sale ON app.sale_returns(sale_id);
CREATE TRIGGER trg_sale_returns_tenant BEFORE INSERT ON app.sale_returns
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  CONDICIONAL (cliente leva para provar)
-- =============================================================================
CREATE TABLE app.consignments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  number      bigint NOT NULL,
  customer_id uuid NOT NULL REFERENCES app.partners(id),
  status      text NOT NULL DEFAULT 'ABERTA' CHECK (status IN ('ABERTA', 'FECHADA', 'CANCELADA')),
  due_date    date,
  notes       text,
  created_by  uuid REFERENCES app.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  closed_at   timestamptz,
  UNIQUE (tenant_id, number)
);
CREATE TRIGGER trg_consignments_tenant BEFORE INSERT OR UPDATE ON app.consignments
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.consignment_items (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id      uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  consignment_id uuid NOT NULL REFERENCES app.consignments(id) ON DELETE CASCADE,
  product_id     uuid NOT NULL REFERENCES app.products(id),
  description    text NOT NULL,
  qty            numeric(14,3) NOT NULL CHECK (qty > 0),
  unit_price     numeric(14,2) NOT NULL,
  returned_qty   numeric(14,3),
  kept_qty       numeric(14,3)
);
CREATE INDEX ix_consignment_items ON app.consignment_items(consignment_id);
CREATE TRIGGER trg_consignment_items_tenant BEFORE INSERT ON app.consignment_items
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  ESTAMPARIA: pedidos sob encomenda
-- =============================================================================
CREATE TABLE app.custom_orders (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  number       bigint NOT NULL,
  customer_id  uuid NOT NULL REFERENCES app.partners(id),
  title        text NOT NULL CHECK (length(title) BETWEEN 2 AND 120),
  technique    text NOT NULL DEFAULT 'DTF'
               CHECK (technique IN ('SERIGRAFIA','SUBLIMACAO','DTF','BORDADO','VINIL','LASER','OUTRO')),
  status       text NOT NULL DEFAULT 'ORCAMENTO'
               CHECK (status IN ('ORCAMENTO','APROVADO','PRODUCAO','PRONTO','ENTREGUE','CANCELADO')),
  due_date     date,
  art_notes    text,       -- posição, tamanho da arte, cores
  notes        text,
  discount     numeric(14,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  deposit      numeric(14,2) NOT NULL DEFAULT 0 CHECK (deposit >= 0),
  sale_id      uuid REFERENCES app.sales(id),
  created_by   uuid REFERENCES app.users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  approved_at  timestamptz,
  ready_at     timestamptz,
  delivered_at timestamptz,
  canceled_at  timestamptz,
  UNIQUE (tenant_id, number)
);
CREATE INDEX ix_custom_orders_status ON app.custom_orders(tenant_id, status, due_date);
CREATE TRIGGER trg_custom_orders_tenant BEFORE INSERT OR UPDATE ON app.custom_orders
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.custom_order_items (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  order_id    uuid NOT NULL REFERENCES app.custom_orders(id) ON DELETE CASCADE,
  product_id  uuid REFERENCES app.products(id),   -- peça lisa do estoque (opcional)
  description text NOT NULL,
  color       text,
  sizes       jsonb NOT NULL DEFAULT '{}'::jsonb, -- {"P":5,"M":10,"G":3}
  qty         numeric(14,3) NOT NULL CHECK (qty > 0),
  unit_price  numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  total       numeric(14,2) NOT NULL
);
CREATE INDEX ix_custom_order_items ON app.custom_order_items(order_id);
CREATE TRIGGER trg_custom_order_items_tenant BEFORE INSERT ON app.custom_order_items
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.custom_order_payments (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id       uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  order_id        uuid NOT NULL REFERENCES app.custom_orders(id) ON DELETE CASCADE,
  method          text NOT NULL CHECK (method IN ('DINHEIRO','PIX','DEBITO','CREDITO')),
  amount          numeric(14,2) NOT NULL CHECK (amount > 0),
  cash_session_id uuid REFERENCES app.cash_sessions(id),
  user_id         uuid REFERENCES app.users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_custom_order_payments_tenant BEFORE INSERT ON app.custom_order_payments
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.custom_order_events (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id  uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  order_id   uuid NOT NULL REFERENCES app.custom_orders(id) ON DELETE CASCADE,
  status     text NOT NULL,
  note       text,
  user_id    uuid REFERENCES app.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_custom_order_events ON app.custom_order_events(order_id, created_at);
CREATE TRIGGER trg_custom_order_events_tenant BEFORE INSERT ON app.custom_order_events
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Artes / fotos do pedido (até 2 MB cada)
CREATE TABLE app.custom_order_arts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  order_id     uuid NOT NULL REFERENCES app.custom_orders(id) ON DELETE CASCADE,
  name         text,
  content_type text NOT NULL CHECK (content_type IN ('image/png','image/jpeg','image/webp')),
  data         bytea NOT NULL CHECK (octet_length(data) <= 2 * 1024 * 1024),
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_custom_order_arts ON app.custom_order_arts(order_id);
CREATE TRIGGER trg_custom_order_arts_tenant BEFORE INSERT ON app.custom_order_arts
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Leitura pública só da imagem (o UUID da arte não é adivinhável)
CREATE OR REPLACE FUNCTION app.public_order_art(p_id uuid)
RETURNS TABLE (content_type text, data bytea, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT a.content_type, a.data, a.created_at FROM app.custom_order_arts a WHERE a.id = p_id
$$;
REVOKE ALL ON FUNCTION app.public_order_art(uuid) FROM PUBLIC;

ALTER TABLE app.sales ADD COLUMN custom_order_id uuid REFERENCES app.custom_orders(id);

-- RLS em todas as tabelas novas
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['store_credits','store_credit_moves','sale_returns','consignments','consignment_items',
                           'custom_orders','custom_order_items','custom_order_payments','custom_order_events','custom_order_arts']
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

-- Pagamentos de uma venda: grava, abate vales-troca e confere troco/fiado.
-- p_payments: [{"method":"DINHEIRO","amount":50},{"method":"VALE","amount":30,"voucher":"VT000012"}]
CREATE OR REPLACE FUNCTION app.apply_sale_payments(
  p_sale uuid, p_payments jsonb, p_total numeric, p_customer uuid, p_due_days int, p_label text)
RETURNS numeric   -- valor pago
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  x jsonb; c app.store_credits%ROWTYPE; v_amt numeric(14,2);
  v_paid numeric(14,2); v_cash numeric(14,2); v_prazo numeric(14,2);
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_payments, '[]')) LOOP
    v_amt := (x->>'amount')::numeric;
    IF v_amt IS NULL OR v_amt <= 0 THEN RAISE EXCEPTION 'Valor de pagamento inválido'; END IF;
    IF x->>'method' = 'SINAL' THEN RAISE EXCEPTION 'Sinal só entra pelo pedido'; END IF;
    IF x->>'method' = 'VALE' THEN
      SELECT * INTO c FROM app.store_credits WHERE upper(code) = upper(trim(x->>'voucher')) FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Vale-troca % não encontrado', x->>'voucher'; END IF;
      IF c.expires_at IS NOT NULL AND c.expires_at < current_date THEN
        RAISE EXCEPTION 'Vale-troca % venceu em %', c.code, to_char(c.expires_at, 'DD/MM/YYYY');
      END IF;
      IF c.balance < v_amt THEN RAISE EXCEPTION 'Saldo do vale % é %', c.code, c.balance; END IF;
      UPDATE app.store_credits SET balance = balance - v_amt WHERE id = c.id;
      INSERT INTO app.store_credit_moves (credit_id, sale_id, amount) VALUES (c.id, p_sale, -v_amt);
    END IF;
    INSERT INTO app.sale_payments (sale_id, method, amount)
    VALUES (p_sale, (x->>'method')::app.payment_method, v_amt);
  END LOOP;

  SELECT coalesce(sum(amount), 0),
         coalesce(sum(amount) FILTER (WHERE method = 'DINHEIRO'), 0),
         coalesce(sum(amount) FILTER (WHERE method::text = 'PRAZO'), 0)
    INTO v_paid, v_cash, v_prazo FROM app.sale_payments WHERE sale_id = p_sale;
  IF v_paid < p_total THEN RAISE EXCEPTION 'Pagamento insuficiente: total %, pago %', p_total, v_paid; END IF;
  IF v_paid - p_total > v_cash THEN RAISE EXCEPTION 'Troco só pode ser dado em dinheiro'; END IF;
  IF v_prazo > 0 THEN
    IF p_customer IS NULL THEN RAISE EXCEPTION 'Venda a prazo exige um cliente identificado'; END IF;
    INSERT INTO app.financial_entries (kind, partner_id, description, document, due_date, amount, origin, ref_id, created_by)
    VALUES ('RECEBER', p_customer, p_label, NULL, current_date + coalesce(p_due_days, 30), v_prazo, 'VENDA', p_sale,
            app.current_user_id());
  END IF;
  RETURN v_paid;
END $$;

-- PDV: fechamento de venda (versão com vale-troca). Mesma assinatura da Fase 1.
CREATE OR REPLACE FUNCTION app.close_sale(
  p_items jsonb, p_payments jsonb, p_discount numeric DEFAULT 0,
  p_customer_doc text DEFAULT NULL, p_allow_negative_stock boolean DEFAULT false,
  p_customer_id uuid DEFAULT NULL, p_due_days int DEFAULT 30)
RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  v_sale_id  uuid := gen_random_uuid();
  v_session  uuid := app.current_cash_session();
  v_subtotal numeric(14,2) := 0;
  v_total    numeric(14,2);
  v_paid     numeric(14,2);
  v_item     jsonb;
  v_prod     app.products%ROWTYPE;
  v_cust     app.partners%ROWTYPE;
  v_qty      numeric(14,3);
  v_number   bigint;
BEGIN
  IF app.current_tenant_id() IS NULL THEN RAISE EXCEPTION 'Contexto de empresa ausente'; END IF;
  IF v_session IS NULL THEN RAISE EXCEPTION 'Abra o caixa antes de vender'; END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Venda sem itens';
  END IF;
  IF p_customer_id IS NOT NULL THEN
    SELECT * INTO v_cust FROM app.partners WHERE id = p_customer_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cliente não encontrado'; END IF;
  END IF;

  v_number := app.next_counter('sale');
  INSERT INTO app.sales (id, tenant_id, sale_number, status, cashier_id, customer_doc, customer_id, cash_session_id)
  VALUES (v_sale_id, app.current_tenant_id(), v_number, 'FINALIZADA', app.current_user_id(),
          coalesce(p_customer_doc, v_cust.doc), p_customer_id, v_session);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (v_item->>'qty')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
    SELECT * INTO v_prod FROM app.products
     WHERE id = (v_item->>'product_id')::uuid AND is_active
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Produto % não encontrado nesta empresa', v_item->>'product_id'; END IF;
    IF NOT p_allow_negative_stock AND v_prod.stock_qty < v_qty THEN
      RAISE EXCEPTION 'Estoque insuficiente para % (disponível: %)', v_prod.name, v_prod.stock_qty;
    END IF;
    INSERT INTO app.sale_items (sale_id, product_id, description, qty, unit_price, total)
    VALUES (v_sale_id, v_prod.id, v_prod.name, v_qty, v_prod.price, round(v_qty * v_prod.price, 2));
    UPDATE app.products SET stock_qty = stock_qty - v_qty WHERE id = v_prod.id;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (v_prod.id, -v_qty, 'VENDA', v_sale_id, app.current_user_id());
    v_subtotal := v_subtotal + round(v_qty * v_prod.price, 2);
  END LOOP;

  IF coalesce(p_discount, 0) > v_subtotal THEN RAISE EXCEPTION 'Desconto maior que o subtotal'; END IF;
  v_total := v_subtotal - coalesce(p_discount, 0);
  v_paid := app.apply_sale_payments(v_sale_id, p_payments, v_total, p_customer_id, p_due_days, 'Venda nº ' || v_number);

  UPDATE app.sales
     SET subtotal = v_subtotal, discount = coalesce(p_discount, 0), total = v_total,
         paid = v_paid, change_due = v_paid - v_total
   WHERE id = v_sale_id;
  RETURN v_sale_id;
END $$;

-- Cancelamento de venda: devolve estoque e vales; desfaz OS/pedido; bloqueia se já houve troca
CREATE OR REPLACE FUNCTION app.cancel_sale(p_sale_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM app.financial_entries
              WHERE ref_id = p_sale_id AND origin = 'VENDA' AND paid_amount > 0) THEN
    RAISE EXCEPTION 'Venda a prazo já teve recebimento; estorne no financeiro antes';
  END IF;
  IF EXISTS (SELECT 1 FROM app.sale_returns WHERE sale_id = p_sale_id) THEN
    RAISE EXCEPTION 'Esta venda já teve troca/devolução e não pode ser cancelada';
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
  -- vales usados voltam a ter saldo
  FOR r IN SELECT credit_id, sum(amount) AS used FROM app.store_credit_moves
            WHERE sale_id = p_sale_id GROUP BY credit_id LOOP
    UPDATE app.store_credits SET balance = balance - r.used WHERE id = r.credit_id;
    INSERT INTO app.store_credit_moves (credit_id, sale_id, amount) VALUES (r.credit_id, p_sale_id, -r.used);
  END LOOP;
  UPDATE app.work_orders SET status = 'PRONTA', delivered_at = NULL, sale_id = NULL WHERE sale_id = p_sale_id;
  UPDATE app.custom_orders SET status = 'PRONTO', delivered_at = NULL, sale_id = NULL WHERE sale_id = p_sale_id;
END $$;

-- Troca / devolução de itens de uma venda.
-- p_items: [{"sale_item_id": 12, "qty": 1}]   p_mode: 'VALE' (gera vale-troca) ou 'DINHEIRO' (sai do caixa)
CREATE OR REPLACE FUNCTION app.return_sale_items(
  p_sale_id uuid, p_items jsonb, p_mode text, p_customer uuid DEFAULT NULL,
  p_reason text DEFAULT NULL, p_valid_days int DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  s app.sales%ROWTYPE; it app.sale_items%ROWTYPE; x jsonb;
  v_qty numeric(14,3); v_factor numeric; v_amount numeric(14,2) := 0; v_line numeric(14,2);
  v_credit uuid; v_code text; v_sess uuid; v_sum jsonb;
BEGIN
  IF p_mode NOT IN ('VALE', 'DINHEIRO') THEN RAISE EXCEPTION 'Escolha vale-troca ou dinheiro'; END IF;
  SELECT * INTO s FROM app.sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND OR s.status <> 'FINALIZADA' THEN RAISE EXCEPTION 'Venda não encontrada ou cancelada'; END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Escolha os itens que voltam';
  END IF;
  -- desconto da venda é rateado: devolve o que o cliente efetivamente pagou
  v_factor := CASE WHEN s.subtotal > 0 THEN s.total / s.subtotal ELSE 1 END;

  FOR x IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (x->>'qty')::numeric;
    SELECT * INTO it FROM app.sale_items WHERE id = (x->>'sale_item_id')::bigint AND sale_id = p_sale_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Item não pertence a esta venda'; END IF;
    IF v_qty IS NULL OR v_qty <= 0 OR v_qty > it.qty - it.returned_qty THEN
      RAISE EXCEPTION 'Quantidade inválida para % (pode voltar até %)', it.description, it.qty - it.returned_qty;
    END IF;
    UPDATE app.sale_items SET returned_qty = returned_qty + v_qty WHERE id = it.id;
    IF it.product_id IS NOT NULL THEN
      UPDATE app.products SET stock_qty = stock_qty + v_qty WHERE id = it.product_id;
      INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
      VALUES (it.product_id, v_qty, 'DEVOLUCAO', p_sale_id, app.current_user_id());
    END IF;
    v_line := round(v_qty * it.unit_price * v_factor, 2);
    v_amount := v_amount + v_line;
  END LOOP;

  IF p_mode = 'VALE' THEN
    v_code := 'VT' || lpad(app.next_counter('vale')::text, 6, '0');
    INSERT INTO app.store_credits (code, customer_id, amount, balance, origin_sale_id, expires_at, created_by)
    VALUES (v_code, coalesce(p_customer, s.customer_id), v_amount, v_amount, p_sale_id,
            CASE WHEN coalesce(p_valid_days, 0) > 0 THEN current_date + p_valid_days END, app.current_user_id())
    RETURNING id INTO v_credit;
  ELSE
    v_sess := app.current_cash_session();
    IF v_sess IS NULL THEN RAISE EXCEPTION 'Abra o caixa para devolver em dinheiro'; END IF;
    v_sum := app.cash_summary(v_sess);
    IF v_amount > (v_sum->>'expectedCash')::numeric THEN
      RAISE EXCEPTION 'Não há dinheiro suficiente na gaveta (%)', v_sum->>'expectedCash';
    END IF;
    INSERT INTO app.cash_movements (session_id, kind, amount, reason, ref_id, user_id)
    VALUES (v_sess, 'PAGAMENTO', v_amount, 'Devolução venda nº ' || s.sale_number, p_sale_id, app.current_user_id());
  END IF;

  INSERT INTO app.sale_returns (sale_id, amount, mode, credit_id, items, reason, user_id)
  VALUES (p_sale_id, v_amount, p_mode, v_credit, p_items, p_reason, app.current_user_id());

  RETURN jsonb_build_object('amount', v_amount, 'mode', p_mode, 'creditId', v_credit, 'code', v_code,
                            'saleNumber', s.sale_number);
END $$;

-- Condicional: separa as peças (saem do estoque enquanto estão com o cliente)
CREATE OR REPLACE FUNCTION app.open_consignment(p_customer uuid, p_items jsonb, p_due date, p_notes text)
RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v_id uuid := gen_random_uuid(); x jsonb; v_prod app.products%ROWTYPE; v_qty numeric(14,3);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app.partners WHERE id = p_customer AND is_active) THEN
    RAISE EXCEPTION 'Cliente não encontrado';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'Condicional sem peças'; END IF;
  INSERT INTO app.consignments (id, number, customer_id, due_date, notes, created_by)
  VALUES (v_id, app.next_counter('condicional'), p_customer, p_due, p_notes, app.current_user_id());
  FOR x IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (x->>'qty')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
    SELECT * INTO v_prod FROM app.products WHERE id = (x->>'product_id')::uuid AND is_active FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Produto não encontrado'; END IF;
    IF v_prod.stock_qty < v_qty THEN
      RAISE EXCEPTION 'Estoque insuficiente para % (disponível: %)', v_prod.name, v_prod.stock_qty;
    END IF;
    INSERT INTO app.consignment_items (consignment_id, product_id, description, qty, unit_price)
    VALUES (v_id, v_prod.id, v_prod.name, v_qty, v_prod.price);
    UPDATE app.products SET stock_qty = stock_qty - v_qty WHERE id = v_prod.id;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (v_prod.id, -v_qty, 'CONDICIONAL', v_id, app.current_user_id());
  END LOOP;
  RETURN v_id;
END $$;

-- Condicional: acerto. Tudo volta ao estoque; o que o cliente ficou é devolvido
-- na resposta para ser vendido no PDV (que baixa o estoque de novo).
-- p_returns: [{"item_id": 3, "returned": 2}]  (item fora da lista = volta tudo)
CREATE OR REPLACE FUNCTION app.close_consignment(p_id uuid, p_returns jsonb, p_cancel boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE AS $$
DECLARE c app.consignments%ROWTYPE; it record; v_ret numeric(14,3); v_kept jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO c FROM app.consignments WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Condicional não encontrada'; END IF;
  IF c.status <> 'ABERTA' THEN RAISE EXCEPTION 'Condicional já está %', lower(c.status); END IF;
  FOR it IN SELECT * FROM app.consignment_items WHERE consignment_id = p_id ORDER BY id LOOP
    IF p_cancel THEN
      v_ret := it.qty;
    ELSE
      SELECT (r->>'returned')::numeric INTO v_ret
        FROM jsonb_array_elements(coalesce(p_returns, '[]')) r WHERE (r->>'item_id')::bigint = it.id;
      v_ret := coalesce(v_ret, it.qty);
    END IF;
    IF v_ret < 0 OR v_ret > it.qty THEN RAISE EXCEPTION 'Devolução inválida para %', it.description; END IF;
    UPDATE app.consignment_items SET returned_qty = v_ret, kept_qty = it.qty - v_ret WHERE id = it.id;
    UPDATE app.products SET stock_qty = stock_qty + it.qty WHERE id = it.product_id;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (it.product_id, it.qty, 'RETORNO_CONDICIONAL', p_id, app.current_user_id());
    IF it.qty - v_ret > 0 THEN
      v_kept := v_kept || jsonb_build_object('product_id', it.product_id, 'qty', it.qty - v_ret);
    END IF;
  END LOOP;
  UPDATE app.consignments SET status = CASE WHEN p_cancel THEN 'CANCELADA' ELSE 'FECHADA' END, closed_at = now()
   WHERE id = p_id;
  RETURN jsonb_build_object('customerId', c.customer_id, 'kept', v_kept);
END $$;

-- Estamparia: sinal do pedido (dinheiro entra na gaveta do caixa aberto)
CREATE OR REPLACE FUNCTION app.add_order_deposit(p_id uuid, p_amount numeric, p_method text) RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE o app.custom_orders%ROWTYPE; v_sess uuid := app.current_cash_session(); v_total numeric(14,2);
BEGIN
  SELECT * INTO o FROM app.custom_orders WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido não encontrado'; END IF;
  IF o.status IN ('ENTREGUE', 'CANCELADO') THEN RAISE EXCEPTION 'Pedido já está %', lower(o.status); END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Valor inválido'; END IF;
  SELECT coalesce(sum(total), 0) - o.discount INTO v_total FROM app.custom_order_items WHERE order_id = p_id;
  IF o.deposit + p_amount > v_total THEN
    RAISE EXCEPTION 'Sinal maior que o total do pedido (falta %)', v_total - o.deposit;
  END IF;
  IF p_method = 'DINHEIRO' THEN
    IF v_sess IS NULL THEN RAISE EXCEPTION 'Abra o caixa no PDV para receber em dinheiro'; END IF;
    INSERT INTO app.cash_movements (session_id, kind, amount, reason, ref_id, user_id)
    VALUES (v_sess, 'RECEBIMENTO', p_amount, 'Sinal pedido nº ' || o.number, p_id, app.current_user_id());
  END IF;
  INSERT INTO app.custom_order_payments (order_id, method, amount, cash_session_id, user_id)
  VALUES (p_id, p_method, p_amount, v_sess, app.current_user_id());
  UPDATE app.custom_orders SET deposit = deposit + p_amount WHERE id = p_id;
  INSERT INTO app.custom_order_events (order_id, status, note, user_id)
  VALUES (p_id, o.status, 'Sinal de R$ ' || to_char(p_amount, 'FM999G990D00') || ' (' || lower(p_method) || ')',
          app.current_user_id());
END $$;

-- Estamparia: entrega + recebimento do restante no caixa. Gera a venda;
-- peças do estoque baixam; o sinal entra como pagamento SINAL.
CREATE OR REPLACE FUNCTION app.close_custom_order(p_id uuid, p_payments jsonb, p_due_days int DEFAULT 30)
RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  o app.custom_orders%ROWTYPE; v_sale uuid := gen_random_uuid(); v_sess uuid := app.current_cash_session();
  v_number bigint; v_sub numeric(14,2) := 0; v_total numeric(14,2); v_paid numeric(14,2);
  it record; v_prod app.products%ROWTYPE; v_sizes text;
BEGIN
  SELECT * INTO o FROM app.custom_orders WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido não encontrado'; END IF;
  IF o.status IN ('ENTREGUE', 'CANCELADO') THEN RAISE EXCEPTION 'Pedido já está %', lower(o.status); END IF;
  IF v_sess IS NULL THEN RAISE EXCEPTION 'Abra o caixa no PDV antes de entregar o pedido'; END IF;
  IF NOT EXISTS (SELECT 1 FROM app.custom_order_items WHERE order_id = p_id) THEN RAISE EXCEPTION 'Pedido sem itens'; END IF;

  v_number := app.next_counter('sale');
  INSERT INTO app.sales (id, tenant_id, sale_number, status, cashier_id, customer_id, customer_doc, cash_session_id, custom_order_id)
  SELECT v_sale, app.current_tenant_id(), v_number, 'FINALIZADA', app.current_user_id(), o.customer_id, p.doc, v_sess, p_id
    FROM app.partners p WHERE p.id = o.customer_id;

  FOR it IN SELECT * FROM app.custom_order_items WHERE order_id = p_id ORDER BY id LOOP
    IF it.product_id IS NOT NULL THEN
      SELECT * INTO v_prod FROM app.products WHERE id = it.product_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Peça % não encontrada', it.description; END IF;
      IF v_prod.stock_qty < it.qty THEN
        RAISE EXCEPTION 'Estoque insuficiente para % (disponível: %)', v_prod.name, v_prod.stock_qty;
      END IF;
      UPDATE app.products SET stock_qty = stock_qty - it.qty WHERE id = v_prod.id;
      INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
      VALUES (v_prod.id, -it.qty, 'VENDA', v_sale, app.current_user_id());
    END IF;
    SELECT string_agg(k || ':' || v, ' ') INTO v_sizes FROM jsonb_each_text(it.sizes) AS e(k, v);
    INSERT INTO app.sale_items (sale_id, product_id, description, qty, unit_price, total)
    VALUES (v_sale, it.product_id,
            it.description || coalesce(' ' || it.color, '') || coalesce(' (' || v_sizes || ')', ''),
            it.qty, it.unit_price, it.total);
    v_sub := v_sub + it.total;
  END LOOP;

  IF o.discount > v_sub THEN RAISE EXCEPTION 'Desconto maior que o total do pedido'; END IF;
  v_total := v_sub - o.discount;
  IF o.deposit > 0 THEN
    INSERT INTO app.sale_payments (sale_id, method, amount) VALUES (v_sale, 'SINAL', o.deposit);
  END IF;
  v_paid := app.apply_sale_payments(v_sale, p_payments, v_total, o.customer_id, p_due_days, 'Pedido nº ' || o.number);

  UPDATE app.sales SET subtotal = v_sub, discount = o.discount, total = v_total, paid = v_paid,
                       change_due = v_paid - v_total
   WHERE id = v_sale;
  UPDATE app.custom_orders SET status = 'ENTREGUE', delivered_at = now(), sale_id = v_sale,
                               ready_at = coalesce(ready_at, now())
   WHERE id = p_id;
  INSERT INTO app.custom_order_events (order_id, status, note, user_id)
  VALUES (p_id, 'ENTREGUE', 'Entregue e recebido no caixa (venda nº ' || v_number || ')', app.current_user_id());
  RETURN v_sale;
END $$;

-- Defesa: VALE só entra abatendo um vale-troca; SINAL só em venda de pedido
CREATE OR REPLACE FUNCTION app.check_sale_payment() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.method::text = 'VALE' AND NOT EXISTS (
       SELECT 1 FROM app.store_credit_moves WHERE sale_id = NEW.sale_id AND amount < 0) THEN
    RAISE EXCEPTION 'Pagamento com vale-troca precisa do código do vale';
  END IF;
  IF NEW.method::text = 'SINAL' AND NOT EXISTS (
       SELECT 1 FROM app.sales WHERE id = NEW.sale_id AND custom_order_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Sinal só entra pelo pedido';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_sale_payments_check BEFORE INSERT ON app.sale_payments
  FOR EACH ROW EXECUTE FUNCTION app.check_sale_payment();

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_api;

COMMIT;
