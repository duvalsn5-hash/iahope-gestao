-- =============================================================================
--  IAHOPE GESTÃO — FASE 1
--  Módulos por empresa · Clientes/Fornecedores · Caixa · Contas a pagar/receber
--  Entrada de mercadoria por XML de NF-e · Etiqueta de balança
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  Ordem: 00_roles → 01_schema → 02_seed → 03_fase1  (rode UMA vez, como dono)
--  Todas as tabelas novas seguem o mesmo isolamento por CNPJ (RLS).
--  Todas as funções novas rodam como INVOCADOR: o RLS vale dentro delas.
-- =============================================================================

-- Novo meio de pagamento "a prazo" (fiado) — precisa ficar fora da transação
ALTER TYPE app.payment_method ADD VALUE IF NOT EXISTS 'PRAZO';

BEGIN;
SET search_path = app, public;

-- =============================================================================
--  1. MÓDULOS POR EMPRESA + CONFIGURAÇÃO DE BALANÇA
-- =============================================================================
--  Núcleo (sempre ativo): Produtos, Clientes/Fornecedores, Empresa.
--  Módulos contratáveis: PDV, PRODUTIVIDADE, FINANCEIRO, COMPRAS, BALANCA.
ALTER TABLE app.tenants
  ADD COLUMN modules text[] NOT NULL
      DEFAULT ARRAY['PDV','PRODUTIVIDADE','FINANCEIRO','COMPRAS']::text[],
  ADD COLUMN scale_config jsonb NOT NULL
      DEFAULT '{"prefix":"2","codeLength":4,"valueLength":5,"valueType":"PRECO"}'::jsonb;
ALTER TABLE app.tenants ADD CONSTRAINT tenants_modules_valid
  CHECK (modules <@ ARRAY['PDV','PRODUTIVIDADE','FINANCEIRO','COMPRAS','BALANCA']::text[]);

-- Só o Master altera os módulos contratados
CREATE OR REPLACE FUNCTION app.guard_tenant_admin_fields() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT app.is_super_admin() AND (
       NEW.status IS DISTINCT FROM OLD.status
    OR NEW.license_expires_at IS DISTINCT FROM OLD.license_expires_at
    OR NEW.max_users IS DISTINCT FROM OLD.max_users
    OR NEW.cnpj IS DISTINCT FROM OLD.cnpj
    OR NEW.is_platform IS DISTINCT FROM OLD.is_platform
    OR NEW.blocked_reason IS DISTINCT FROM OLD.blocked_reason
    OR NEW.modules IS DISTINCT FROM OLD.modules) THEN
    RAISE EXCEPTION 'Somente o Administrador Master pode alterar status, licença, CNPJ ou módulos';
  END IF;
  RETURN NEW;
END $$;

-- Login e checagem de sessão passam a devolver os módulos da empresa
DROP FUNCTION app.auth_lookup(text, text);
CREATE FUNCTION app.auth_lookup(p_cnpj text, p_username text)
RETURNS TABLE (user_id uuid, tenant_id uuid, username text, full_name text,
               password_hash text, role app.user_role, user_active boolean,
               tenant_status app.tenant_status, license_expires_at date,
               nome_fantasia text, razao_social text, logo_url text,
               primary_color text, cnpj text, modules text[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT u.id, t.id, u.username::text, u.full_name, u.password_hash, u.role, u.is_active,
         t.status, t.license_expires_at, t.nome_fantasia, t.razao_social, t.logo_url,
         t.primary_color, t.cnpj, t.modules
    FROM app.users u
    JOIN app.tenants t ON t.id = u.tenant_id
   WHERE t.cnpj = regexp_replace(p_cnpj, '\D', '', 'g')
     AND lower(u.username::text) = lower(p_username)
$$;

DROP FUNCTION app.session_check(uuid, uuid);
CREATE FUNCTION app.session_check(p_user_id uuid, p_tenant_id uuid)
RETURNS TABLE (ok boolean, reason text, modules text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
DECLARE r record;
BEGIN
  SELECT u.is_active, u.role, t.status, t.license_expires_at, t.modules
    INTO r
    FROM app.users u JOIN app.tenants t ON t.id = u.tenant_id
   WHERE u.id = p_user_id AND t.id = p_tenant_id;
  IF NOT FOUND THEN RETURN QUERY SELECT false, 'USUARIO_INEXISTENTE', NULL::text[]; RETURN; END IF;
  IF NOT r.is_active THEN RETURN QUERY SELECT false, 'USUARIO_INATIVO', NULL::text[]; RETURN; END IF;
  IF r.role <> 'SUPER_ADMIN' THEN
    IF r.status = 'BLOQUEADO' THEN RETURN QUERY SELECT false, 'EMPRESA_BLOQUEADA', NULL::text[]; RETURN; END IF;
    IF r.license_expires_at < current_date THEN RETURN QUERY SELECT false, 'LICENCA_EXPIRADA', NULL::text[]; RETURN; END IF;
  END IF;
  RETURN QUERY SELECT true, NULL::text, r.modules;
END $$;

REVOKE ALL ON FUNCTION app.auth_lookup(text, text), app.session_check(uuid, uuid) FROM PUBLIC;

-- =============================================================================
--  2. PRODUTOS: código da balança
-- =============================================================================
ALTER TABLE app.products ADD COLUMN scale_code int CHECK (scale_code > 0);
CREATE UNIQUE INDEX ux_products_scale_code ON app.products(tenant_id, scale_code) WHERE scale_code IS NOT NULL;

-- =============================================================================
--  3. CLIENTES E FORNECEDORES
-- =============================================================================
CREATE OR REPLACE FUNCTION app.cpf_is_valid(p text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d text := regexp_replace(coalesce(p, ''), '\D', '', 'g'); s int; r int; i int;
BEGIN
  IF length(d) <> 11 OR d ~ '^(\d)\1{10}$' THEN RETURN false; END IF;
  s := 0; FOR i IN 1..9 LOOP s := s + substr(d, i, 1)::int * (11 - i); END LOOP;
  r := (s * 10) % 11; IF r = 10 THEN r := 0; END IF;
  IF r <> substr(d, 10, 1)::int THEN RETURN false; END IF;
  s := 0; FOR i IN 1..10 LOOP s := s + substr(d, i, 1)::int * (12 - i); END LOOP;
  r := (s * 10) % 11; IF r = 10 THEN r := 0; END IF;
  RETURN r = substr(d, 11, 1)::int;
END $$;

CREATE TYPE app.partner_kind AS ENUM ('CLIENTE', 'FORNECEDOR', 'AMBOS');

CREATE TABLE app.partners (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  kind          app.partner_kind NOT NULL DEFAULT 'CLIENTE',
  doc           text CHECK (doc IS NULL OR app.cpf_is_valid(doc) OR app.cnpj_is_valid(doc)),
  name          text NOT NULL,
  trade_name    text,
  ie            text,
  phone         text,
  email         text,
  zip           text,
  street        text,
  number        text,
  district      text,
  city          text,
  state         char(2),
  credit_limit  numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0),
  notes         text,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, doc)
);
CREATE INDEX ix_partners_tenant_name ON app.partners(tenant_id, lower(name));
CREATE TRIGGER trg_partners_updated BEFORE UPDATE ON app.partners
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_partners_tenant BEFORE INSERT OR UPDATE ON app.partners
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Código do produto no fornecedor → produto da empresa (aprende na 1ª importação de XML)
CREATE TABLE app.supplier_product_codes (
  tenant_id     uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  partner_id    uuid NOT NULL REFERENCES app.partners(id) ON DELETE CASCADE,
  supplier_code text NOT NULL,
  product_id    uuid NOT NULL REFERENCES app.products(id) ON DELETE CASCADE,
  factor        numeric(14,4) NOT NULL DEFAULT 1 CHECK (factor > 0),
  PRIMARY KEY (tenant_id, partner_id, supplier_code)
);
CREATE TRIGGER trg_spc_tenant BEFORE INSERT OR UPDATE ON app.supplier_product_codes
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  4. CAIXA (abertura, sangria, suprimento, fechamento)
-- =============================================================================
CREATE TABLE app.cash_sessions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES app.users(id),
  status           text NOT NULL DEFAULT 'ABERTO' CHECK (status IN ('ABERTO', 'FECHADO')),
  opened_at        timestamptz NOT NULL DEFAULT now(),
  opening_amount   numeric(14,2) NOT NULL DEFAULT 0 CHECK (opening_amount >= 0),
  closed_at        timestamptz,
  closing_counted  numeric(14,2),
  expected_cash    numeric(14,2),
  difference       numeric(14,2),
  notes            text
);
-- um caixa aberto por operador
CREATE UNIQUE INDEX ux_cash_open_per_user ON app.cash_sessions(tenant_id, user_id) WHERE status = 'ABERTO';
CREATE INDEX ix_cash_sessions_tenant ON app.cash_sessions(tenant_id, opened_at DESC);
CREATE TRIGGER trg_cash_sessions_tenant BEFORE INSERT OR UPDATE ON app.cash_sessions
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.cash_movements (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  session_id  uuid NOT NULL REFERENCES app.cash_sessions(id) ON DELETE CASCADE,
  -- SANGRIA/PAGAMENTO tiram dinheiro da gaveta; SUPRIMENTO/RECEBIMENTO colocam
  kind        text NOT NULL CHECK (kind IN ('SANGRIA', 'SUPRIMENTO', 'RECEBIMENTO', 'PAGAMENTO')),
  amount      numeric(14,2) NOT NULL CHECK (amount > 0),
  reason      text,
  ref_id      uuid,
  user_id     uuid REFERENCES app.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cash_movements_session ON app.cash_movements(session_id);
CREATE TRIGGER trg_cash_movements_tenant BEFORE INSERT ON app.cash_movements
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

ALTER TABLE app.sales
  ADD COLUMN cash_session_id uuid REFERENCES app.cash_sessions(id),
  ADD COLUMN customer_id uuid REFERENCES app.partners(id);
CREATE INDEX ix_sales_cash_session ON app.sales(cash_session_id);

-- =============================================================================
--  5. CONTAS A PAGAR E A RECEBER
-- =============================================================================
CREATE TABLE app.financial_entries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  kind            text NOT NULL CHECK (kind IN ('PAGAR', 'RECEBER')),
  partner_id      uuid REFERENCES app.partners(id),
  description     text NOT NULL,
  category        text,
  document        text,
  issue_date      date NOT NULL DEFAULT current_date,
  due_date        date NOT NULL,
  amount          numeric(14,2) NOT NULL CHECK (amount > 0),
  paid_amount     numeric(14,2) NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
  paid_at         timestamptz,
  status          text NOT NULL DEFAULT 'ABERTO' CHECK (status IN ('ABERTO', 'PARCIAL', 'PAGO', 'CANCELADO')),
  origin          text NOT NULL DEFAULT 'MANUAL' CHECK (origin IN ('MANUAL', 'VENDA', 'COMPRA')),
  ref_id          uuid,
  payment_method  text,
  created_by      uuid REFERENCES app.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (paid_amount <= amount)
);
CREATE INDEX ix_fin_tenant_kind_due ON app.financial_entries(tenant_id, kind, status, due_date);
CREATE INDEX ix_fin_ref ON app.financial_entries(ref_id);
CREATE TRIGGER trg_fin_updated BEFORE UPDATE ON app.financial_entries
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_fin_tenant BEFORE INSERT OR UPDATE ON app.financial_entries
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  6. COMPRAS (entrada de mercadoria por XML de NF-e)
-- =============================================================================
CREATE TABLE app.purchases (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  partner_id   uuid REFERENCES app.partners(id),
  access_key   char(44),
  number       text,
  series       text,
  issue_date   date,
  total        numeric(14,2) NOT NULL DEFAULT 0,
  items_count  int NOT NULL DEFAULT 0,
  created_by   uuid REFERENCES app.users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, access_key)        -- a mesma nota não entra duas vezes
);
CREATE INDEX ix_purchases_tenant ON app.purchases(tenant_id, created_at DESC);
CREATE TRIGGER trg_purchases_tenant BEFORE INSERT OR UPDATE ON app.purchases
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.purchase_items (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id     uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  purchase_id   uuid NOT NULL REFERENCES app.purchases(id) ON DELETE CASCADE,
  product_id    uuid NOT NULL REFERENCES app.products(id),
  supplier_code text,
  description   text NOT NULL,
  qty_invoice   numeric(14,4) NOT NULL,
  factor        numeric(14,4) NOT NULL DEFAULT 1,
  qty_stock     numeric(14,3) NOT NULL,
  unit_cost     numeric(14,4) NOT NULL,
  total         numeric(14,2) NOT NULL
);
CREATE INDEX ix_purchase_items_purchase ON app.purchase_items(purchase_id);
CREATE TRIGGER trg_purchase_items_tenant BEFORE INSERT ON app.purchase_items
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  7. RLS nas tabelas novas (mesma regra de todo o sistema)
-- =============================================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['partners','supplier_product_codes','cash_sessions','cash_movements',
                           'financial_entries','purchases','purchase_items']
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
--  8. FUNÇÕES DE NEGÓCIO (todas como invocador → RLS se aplica)
-- =============================================================================

-- Caixa aberto do operador atual (ou NULL)
CREATE OR REPLACE FUNCTION app.current_cash_session() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT id FROM app.cash_sessions
   WHERE user_id = app.current_user_id() AND status = 'ABERTO'
   LIMIT 1
$$;

-- Resumo do caixa: vendas por forma de pagamento e dinheiro esperado na gaveta
CREATE OR REPLACE FUNCTION app.cash_summary(p_session uuid) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  WITH s AS (SELECT * FROM app.cash_sessions WHERE id = p_session),
  sales AS (
    SELECT sa.id, sa.total, sa.change_due FROM app.sales sa
     WHERE sa.cash_session_id = p_session AND sa.status = 'FINALIZADA'),
  pays AS (
    SELECT p.method::text AS method, sum(p.amount) AS amount
      FROM app.sale_payments p JOIN sales ON sales.id = p.sale_id
     GROUP BY p.method),
  mov AS (
    SELECT kind, sum(amount) AS amount FROM app.cash_movements
     WHERE session_id = p_session GROUP BY kind),
  v AS (
    SELECT
      (SELECT opening_amount FROM s) AS opening,
      (SELECT count(*) FROM sales) AS sales_count,
      coalesce((SELECT sum(total) FROM sales), 0) AS sales_total,
      coalesce((SELECT amount FROM pays WHERE method = 'DINHEIRO'), 0)
        - coalesce((SELECT sum(change_due) FROM sales), 0) AS cash_sales,
      coalesce((SELECT amount FROM mov WHERE kind = 'SUPRIMENTO'), 0) AS supply,
      coalesce((SELECT amount FROM mov WHERE kind = 'SANGRIA'), 0) AS withdrawal,
      coalesce((SELECT amount FROM mov WHERE kind = 'RECEBIMENTO'), 0) AS received,
      coalesce((SELECT amount FROM mov WHERE kind = 'PAGAMENTO'), 0) AS paid_out)
  SELECT jsonb_build_object(
    'sessionId', p_session,
    'status', (SELECT status FROM s),
    'openedAt', (SELECT opened_at FROM s),
    'closedAt', (SELECT closed_at FROM s),
    'opening', v.opening,
    'salesCount', v.sales_count,
    'salesTotal', v.sales_total,
    'byMethod', coalesce((SELECT jsonb_object_agg(method, amount) FROM pays), '{}'::jsonb),
    'change', coalesce((SELECT sum(change_due) FROM sales), 0),
    'supply', v.supply,
    'withdrawal', v.withdrawal,
    'received', v.received,
    'paidOut', v.paid_out,
    'expectedCash', v.opening + v.cash_sales + v.supply + v.received - v.withdrawal - v.paid_out,
    'counted', (SELECT closing_counted FROM s),
    'difference', (SELECT difference FROM s))
  FROM v
$$;

CREATE OR REPLACE FUNCTION app.open_cash_session(p_opening numeric) RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v_id uuid;
BEGIN
  IF app.current_cash_session() IS NOT NULL THEN
    RAISE EXCEPTION 'Você já tem um caixa aberto';
  END IF;
  INSERT INTO app.cash_sessions (user_id, opening_amount)
  VALUES (app.current_user_id(), coalesce(p_opening, 0))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION app.cash_movement(p_kind text, p_amount numeric, p_reason text) RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v_session uuid := app.current_cash_session(); v_sum jsonb;
BEGIN
  IF v_session IS NULL THEN RAISE EXCEPTION 'Abra o caixa primeiro'; END IF;
  IF p_kind NOT IN ('SANGRIA', 'SUPRIMENTO') THEN RAISE EXCEPTION 'Movimento inválido'; END IF;
  IF p_kind = 'SANGRIA' THEN
    v_sum := app.cash_summary(v_session);
    IF p_amount > (v_sum->>'expectedCash')::numeric THEN
      RAISE EXCEPTION 'Sangria maior que o dinheiro em caixa (%)', v_sum->>'expectedCash';
    END IF;
  END IF;
  INSERT INTO app.cash_movements (session_id, kind, amount, reason, user_id)
  VALUES (v_session, p_kind, p_amount, p_reason, app.current_user_id());
END $$;

CREATE OR REPLACE FUNCTION app.close_cash_session(p_counted numeric, p_notes text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v_session uuid := app.current_cash_session(); v_sum jsonb; v_expected numeric;
BEGIN
  IF v_session IS NULL THEN RAISE EXCEPTION 'Não há caixa aberto'; END IF;
  v_sum := app.cash_summary(v_session);
  v_expected := (v_sum->>'expectedCash')::numeric;
  UPDATE app.cash_sessions
     SET status = 'FECHADO', closed_at = now(), closing_counted = p_counted,
         expected_cash = v_expected, difference = p_counted - v_expected, notes = p_notes
   WHERE id = v_session;
  RETURN app.cash_summary(v_session);
END $$;

-- -----------------------------------------------------------------------------
--  PDV: fechamento de venda (versão Fase 1)
--  + exige caixa aberto  + cliente opcional  + pagamento A PRAZO gera conta a receber
--  + troco só pode sair do dinheiro
-- -----------------------------------------------------------------------------
DROP FUNCTION app.close_sale(jsonb, jsonb, numeric, text, boolean);
CREATE FUNCTION app.close_sale(
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
  v_cash     numeric(14,2);
  v_prazo    numeric(14,2);
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

  INSERT INTO app.sale_payments (sale_id, method, amount)
  SELECT v_sale_id, (p->>'method')::app.payment_method, (p->>'amount')::numeric
    FROM jsonb_array_elements(coalesce(p_payments, '[]')) p;

  SELECT coalesce(sum(amount), 0),
         coalesce(sum(amount) FILTER (WHERE method = 'DINHEIRO'), 0),
         coalesce(sum(amount) FILTER (WHERE method::text = 'PRAZO'), 0)
    INTO v_paid, v_cash, v_prazo
    FROM app.sale_payments WHERE sale_id = v_sale_id;

  IF v_paid < v_total THEN RAISE EXCEPTION 'Pagamento insuficiente: total %, pago %', v_total, v_paid; END IF;
  IF v_paid - v_total > v_cash THEN RAISE EXCEPTION 'Troco só pode ser dado em dinheiro'; END IF;

  IF v_prazo > 0 THEN
    IF p_customer_id IS NULL THEN RAISE EXCEPTION 'Venda a prazo exige um cliente identificado'; END IF;
    INSERT INTO app.financial_entries
      (kind, partner_id, description, document, due_date, amount, origin, ref_id, created_by)
    VALUES ('RECEBER', p_customer_id, 'Venda nº ' || v_number, v_number::text,
            current_date + coalesce(p_due_days, 30), v_prazo, 'VENDA', v_sale_id, app.current_user_id());
  END IF;

  UPDATE app.sales
     SET subtotal = v_subtotal, discount = coalesce(p_discount, 0), total = v_total,
         paid = v_paid, change_due = v_paid - v_total
   WHERE id = v_sale_id;
  RETURN v_sale_id;
END $$;

-- Cancelamento devolve estoque e cancela o a receber ainda não recebido
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
  FOR r IN SELECT product_id, qty FROM app.sale_items WHERE sale_id = p_sale_id LOOP
    UPDATE app.products SET stock_qty = stock_qty + r.qty WHERE id = r.product_id;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (r.product_id, r.qty, 'CANCELAMENTO', p_sale_id, app.current_user_id());
  END LOOP;
  UPDATE app.financial_entries SET status = 'CANCELADO'
   WHERE ref_id = p_sale_id AND origin = 'VENDA' AND status = 'ABERTO';
END $$;

-- Baixa (total ou parcial) de conta a pagar/receber.
-- p_from_cash = true → o dinheiro entra/sai da gaveta do caixa aberto.
CREATE OR REPLACE FUNCTION app.settle_entry(p_id uuid, p_amount numeric, p_method text, p_from_cash boolean)
RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE e app.financial_entries%ROWTYPE; v_session uuid; v_new numeric(14,2);
BEGIN
  SELECT * INTO e FROM app.financial_entries WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Lançamento não encontrado'; END IF;
  IF e.status IN ('PAGO', 'CANCELADO') THEN RAISE EXCEPTION 'Lançamento já está %', lower(e.status); END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Valor inválido'; END IF;
  v_new := e.paid_amount + p_amount;
  IF v_new > e.amount THEN RAISE EXCEPTION 'Valor maior que o saldo (%)', e.amount - e.paid_amount; END IF;

  IF p_from_cash THEN
    v_session := app.current_cash_session();
    IF v_session IS NULL THEN RAISE EXCEPTION 'Abra o caixa para movimentar dinheiro'; END IF;
    INSERT INTO app.cash_movements (session_id, kind, amount, reason, ref_id, user_id)
    VALUES (v_session, CASE WHEN e.kind = 'RECEBER' THEN 'RECEBIMENTO' ELSE 'PAGAMENTO' END,
            p_amount, e.description, e.id, app.current_user_id());
  END IF;

  UPDATE app.financial_entries
     SET paid_amount = v_new,
         status = CASE WHEN v_new >= amount THEN 'PAGO' ELSE 'PARCIAL' END,
         paid_at = CASE WHEN v_new >= amount THEN now() ELSE paid_at END,
         payment_method = coalesce(p_method, payment_method)
   WHERE id = p_id;
END $$;

-- -----------------------------------------------------------------------------
--  Entrada de NF-e de compra (tudo numa transação)
--  p: {supplier:{doc,name,tradeName,ie,phone,zip,street,number,district,city,state},
--      accessKey, number, series, issueDate, total,
--      items:[{supplierCode, description, qty, unitPrice, total, factor,
--              productId | newProduct:{sku, barcode, name, unit, price}}],
--      installments:[{document, dueDate, amount}]}
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.register_purchase(p jsonb) RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  v_partner uuid; v_purchase uuid; v_item jsonb; v_prod uuid; v_factor numeric;
  v_qty_stock numeric; v_cost numeric; v_inst jsonb; v_count int := 0;
  v_doc text := regexp_replace(coalesce(p->'supplier'->>'doc', ''), '\D', '', 'g');
BEGIN
  IF app.current_tenant_id() IS NULL THEN RAISE EXCEPTION 'Contexto de empresa ausente'; END IF;
  IF jsonb_array_length(coalesce(p->'items', '[]')) = 0 THEN RAISE EXCEPTION 'Nota sem itens'; END IF;
  IF p->>'accessKey' IS NOT NULL AND EXISTS (SELECT 1 FROM app.purchases WHERE access_key = p->>'accessKey') THEN
    RAISE EXCEPTION 'Esta nota já foi lançada (chave %)', p->>'accessKey';
  END IF;

  -- fornecedor: localiza pelo CNPJ/CPF ou cadastra
  SELECT id INTO v_partner FROM app.partners WHERE doc = nullif(v_doc, '');
  IF v_partner IS NULL THEN
    INSERT INTO app.partners (kind, doc, name, trade_name, ie, phone, zip, street, number, district, city, state)
    VALUES ('FORNECEDOR', nullif(v_doc, ''), coalesce(p->'supplier'->>'name', 'Fornecedor'),
            p->'supplier'->>'tradeName', p->'supplier'->>'ie', p->'supplier'->>'phone',
            p->'supplier'->>'zip', p->'supplier'->>'street', p->'supplier'->>'number',
            p->'supplier'->>'district', p->'supplier'->>'city', p->'supplier'->>'state')
    RETURNING id INTO v_partner;
  ELSE
    UPDATE app.partners SET kind = 'AMBOS' WHERE id = v_partner AND kind = 'CLIENTE';
  END IF;

  INSERT INTO app.purchases (partner_id, access_key, number, series, issue_date, total, created_by)
  VALUES (v_partner, p->>'accessKey', p->>'number', p->>'series',
          coalesce((p->>'issueDate')::date, current_date), coalesce((p->>'total')::numeric, 0),
          app.current_user_id())
  RETURNING id INTO v_purchase;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p->'items') LOOP
    v_factor := coalesce(nullif(v_item->>'factor', '')::numeric, 1);
    IF v_factor <= 0 THEN RAISE EXCEPTION 'Fator de conversão inválido em %', v_item->>'description'; END IF;

    IF v_item->>'productId' IS NOT NULL THEN
      v_prod := (v_item->>'productId')::uuid;
      PERFORM 1 FROM app.products WHERE id = v_prod;
      IF NOT FOUND THEN RAISE EXCEPTION 'Produto não encontrado para %', v_item->>'description'; END IF;
    ELSIF v_item ? 'newProduct' THEN
      INSERT INTO app.products (sku, barcode, name, unit, price)
      VALUES (v_item->'newProduct'->>'sku', nullif(v_item->'newProduct'->>'barcode', ''),
              v_item->'newProduct'->>'name', coalesce(v_item->'newProduct'->>'unit', 'UN'),
              coalesce((v_item->'newProduct'->>'price')::numeric, 0))
      RETURNING id INTO v_prod;
    ELSE
      RAISE EXCEPTION 'Item sem produto vinculado: %', v_item->>'description';
    END IF;

    v_qty_stock := round((v_item->>'qty')::numeric * v_factor, 3);
    v_cost := CASE WHEN v_qty_stock > 0 THEN (v_item->>'total')::numeric / v_qty_stock ELSE 0 END;

    INSERT INTO app.purchase_items
      (purchase_id, product_id, supplier_code, description, qty_invoice, factor, qty_stock, unit_cost, total)
    VALUES (v_purchase, v_prod, v_item->>'supplierCode', v_item->>'description',
            (v_item->>'qty')::numeric, v_factor, v_qty_stock, round(v_cost, 4), (v_item->>'total')::numeric);

    UPDATE app.products SET stock_qty = stock_qty + v_qty_stock, cost = round(v_cost, 2) WHERE id = v_prod;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (v_prod, v_qty_stock, 'ENTRADA', v_purchase, app.current_user_id());

    IF v_item->>'supplierCode' IS NOT NULL THEN
      INSERT INTO app.supplier_product_codes (partner_id, supplier_code, product_id, factor)
      VALUES (v_partner, v_item->>'supplierCode', v_prod, v_factor)
      ON CONFLICT (tenant_id, partner_id, supplier_code)
      DO UPDATE SET product_id = EXCLUDED.product_id, factor = EXCLUDED.factor;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  UPDATE app.purchases SET items_count = v_count WHERE id = v_purchase;

  -- duplicatas da nota viram contas a pagar
  FOR v_inst IN SELECT * FROM jsonb_array_elements(coalesce(p->'installments', '[]')) LOOP
    INSERT INTO app.financial_entries
      (kind, partner_id, description, category, document, issue_date, due_date, amount, origin, ref_id, created_by)
    VALUES ('PAGAR', v_partner, 'NF-e ' || coalesce(p->>'number', '') || ' - ' || coalesce(p->'supplier'->>'name', ''),
            'Compras', v_inst->>'document', coalesce((p->>'issueDate')::date, current_date),
            (v_inst->>'dueDate')::date, (v_inst->>'amount')::numeric, 'COMPRA', v_purchase, app.current_user_id());
  END LOOP;

  RETURN v_purchase;
END $$;

-- =============================================================================
--  9. Permissões
-- =============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_api;

COMMIT;
