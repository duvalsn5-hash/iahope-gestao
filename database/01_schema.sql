-- =============================================================================
--  IAHOPE GESTÃO — Operação, Logística e PDV
--  Schema PostgreSQL 14+ com isolamento multi-tenant por CNPJ via RLS
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  Modelo de segurança
--  - A API conecta com o papel `app_api` (NÃO é dono das tabelas, NÃO é superuser,
--    NÃO tem BYPASSRLS). Logo, toda consulta passa pelas políticas RLS.
--  - A cada transação a API define o contexto com:
--        SELECT set_config('app.tenant_id', '<uuid>', true);
--        SELECT set_config('app.user_id',   '<uuid>', true);
--        SELECT set_config('app.role',      'SUPER_ADMIN' | 'ADMIN' | ..., true);
--    (o 3º parâmetro `true` = vale só para a transação corrente; seguro com pool)
--  - RLS ativo em todas as tabelas. O DONO das tabelas (usado só em migrações
--    e nas funções de login) não é afetado; a API nunca conecta como dono.
--  - Funções SECURITY DEFINER estreitas cobrem os únicos acessos "pré-login"
--    (identificar empresa pelo CNPJ e buscar credenciais do usuário).
--  - NÃO exige superusuário nem BYPASSRLS: roda em Postgres gerenciado
--    (Neon, Supabase, Render, RDS) e em VPS própria, sem alteração.
--
--  Ordem: 00_roles.sql → 01_schema.sql → 02_seed.sql
--  Rode 00 e 01 com o usuário DONO do banco (no Neon: neondb_owner).
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- username sem diferenciar maiúsculas

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_api') THEN
    RAISE EXCEPTION 'Crie o papel app_api primeiro (database/00_roles.sql)';
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS app;
SET search_path = app, public;

-- -----------------------------------------------------------------------------
--  Tipos
-- -----------------------------------------------------------------------------
CREATE TYPE app.tenant_status  AS ENUM ('ATIVO', 'BLOQUEADO');
CREATE TYPE app.user_role      AS ENUM ('SUPER_ADMIN', 'ADMIN', 'GERENTE', 'OPERADOR', 'CAIXA');
CREATE TYPE app.order_status   AS ENUM ('AGUARDANDO', 'EM_DESCARGA', 'CONFERIDO', 'FINALIZADO', 'CANCELADO');
CREATE TYPE app.sale_status    AS ENUM ('ABERTA', 'FINALIZADA', 'CANCELADA');
CREATE TYPE app.payment_method AS ENUM ('DINHEIRO', 'PIX', 'DEBITO', 'CREDITO', 'OUTROS');

-- -----------------------------------------------------------------------------
--  Funções de contexto (lidas pelas políticas)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.current_tenant_id() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION app.current_user_id() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION app.is_super_admin() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT coalesce(current_setting('app.role', true), '') = 'SUPER_ADMIN'
$$;

-- Validação de CNPJ (dígitos verificadores)
CREATE OR REPLACE FUNCTION app.cnpj_is_valid(p text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  d  text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
  w1 int[] := ARRAY[5,4,3,2,9,8,7,6,5,4,3,2];
  w2 int[] := ARRAY[6,5,4,3,2,9,8,7,6,5,4,3,2];
  s int; r int; i int;
BEGIN
  IF length(d) <> 14 OR d ~ '^(\d)\1{13}$' THEN RETURN false; END IF;
  s := 0; FOR i IN 1..12 LOOP s := s + substr(d, i, 1)::int * w1[i]; END LOOP;
  r := s % 11; r := CASE WHEN r < 2 THEN 0 ELSE 11 - r END;
  IF r <> substr(d, 13, 1)::int THEN RETURN false; END IF;
  s := 0; FOR i IN 1..13 LOOP s := s + substr(d, i, 1)::int * w2[i]; END LOOP;
  r := s % 11; r := CASE WHEN r < 2 THEN 0 ELSE 11 - r END;
  RETURN r = substr(d, 14, 1)::int;
END $$;

CREATE OR REPLACE FUNCTION app.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

-- Preenche tenant_id automaticamente a partir do contexto e impede troca de tenant
CREATE OR REPLACE FUNCTION app.enforce_tenant_id() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.tenant_id IS NULL THEN
    NEW.tenant_id := app.current_tenant_id();
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.tenant_id <> OLD.tenant_id AND NOT app.is_super_admin() THEN
    RAISE EXCEPTION 'Não é permitido mover registros entre empresas';
  END IF;
  RETURN NEW;
END $$;

-- =============================================================================
--  TENANTS (empresas / CNPJ)
-- =============================================================================
CREATE TABLE app.tenants (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cnpj            char(14)  NOT NULL UNIQUE CHECK (app.cnpj_is_valid(cnpj)),
  razao_social    text      NOT NULL,
  nome_fantasia   text,
  logo_url        text,
  primary_color   char(7)   DEFAULT '#0F4C81' CHECK (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  status          app.tenant_status NOT NULL DEFAULT 'ATIVO',
  blocked_reason  text,
  license_expires_at date   NOT NULL DEFAULT (current_date + 30),
  max_users       int       NOT NULL DEFAULT 10 CHECK (max_users > 0),
  is_platform     boolean   NOT NULL DEFAULT false,   -- tenant da própria IaHope (super admins)
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_tenants_updated BEFORE UPDATE ON app.tenants
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Empresa só altera os próprios dados de marca; status/licença só o Super Admin
CREATE OR REPLACE FUNCTION app.guard_tenant_admin_fields() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT app.is_super_admin() AND (
       NEW.status IS DISTINCT FROM OLD.status
    OR NEW.license_expires_at IS DISTINCT FROM OLD.license_expires_at
    OR NEW.max_users IS DISTINCT FROM OLD.max_users
    OR NEW.cnpj IS DISTINCT FROM OLD.cnpj
    OR NEW.is_platform IS DISTINCT FROM OLD.is_platform
    OR NEW.blocked_reason IS DISTINCT FROM OLD.blocked_reason) THEN
    RAISE EXCEPTION 'Somente o Administrador Master pode alterar status, licença ou CNPJ';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_tenants_guard BEFORE UPDATE ON app.tenants
  FOR EACH ROW EXECUTE FUNCTION app.guard_tenant_admin_fields();

-- =============================================================================
--  USERS
-- =============================================================================
CREATE TABLE app.users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  username      citext NOT NULL,
  full_name     text   NOT NULL,
  email         citext,
  password_hash text   NOT NULL,              -- bcrypt (gerado na API)
  role          app.user_role NOT NULL DEFAULT 'OPERADOR',
  is_active     boolean NOT NULL DEFAULT true,
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, username)
);
CREATE INDEX ix_users_tenant ON app.users(tenant_id);
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_users_tenant BEFORE INSERT OR UPDATE ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- SUPER_ADMIN só pode existir no tenant da plataforma, e só um Super Admin cria outro
CREATE OR REPLACE FUNCTION app.guard_super_admin_role() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.role = 'SUPER_ADMIN' THEN
    IF NOT app.is_super_admin() AND current_setting('app.bootstrap', true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION 'Somente o Administrador Master pode conceder o perfil SUPER_ADMIN';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM app.tenants t WHERE t.id = NEW.tenant_id AND t.is_platform) THEN
      RAISE EXCEPTION 'SUPER_ADMIN deve pertencer ao tenant da plataforma';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_users_superadmin BEFORE INSERT OR UPDATE OF role ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.guard_super_admin_role();

-- =============================================================================
--  PRODUCTS (SKU + código de barras)
-- =============================================================================
CREATE TABLE app.products (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  sku         text NOT NULL,
  barcode     text,
  name        text NOT NULL,
  unit        text NOT NULL DEFAULT 'UN',
  price       numeric(14,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  cost        numeric(14,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
  stock_qty   numeric(14,3) NOT NULL DEFAULT 0,
  min_stock   numeric(14,3) NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, sku),
  UNIQUE (tenant_id, barcode)
);
CREATE INDEX ix_products_tenant_name ON app.products(tenant_id, lower(name));
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON app.products
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_products_tenant BEFORE INSERT OR UPDATE ON app.products
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Histórico de movimentação de estoque
CREATE TABLE app.stock_movements (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  product_id  uuid NOT NULL REFERENCES app.products(id) ON DELETE CASCADE,
  qty         numeric(14,3) NOT NULL,          -- negativo = saída
  reason      text NOT NULL,                   -- 'VENDA', 'ENTRADA', 'AJUSTE', 'CANCELAMENTO'
  ref_id      uuid,
  user_id     uuid REFERENCES app.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_stock_mov_tenant ON app.stock_movements(tenant_id, product_id, created_at DESC);
CREATE TRIGGER trg_stock_mov_tenant BEFORE INSERT ON app.stock_movements
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  LOGISTICS_ORDERS (cargas / ordens de descarga)
-- =============================================================================
CREATE TABLE app.logistics_orders (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  order_number    text NOT NULL,
  carrier         text,
  vehicle_plate   text,
  dock            text,
  expected_volumes int  NOT NULL DEFAULT 0 CHECK (expected_volumes >= 0),
  unloaded_volumes int  NOT NULL DEFAULT 0 CHECK (unloaded_volumes >= 0),
  weight_kg       numeric(14,3) NOT NULL DEFAULT 0,
  status          app.order_status NOT NULL DEFAULT 'AGUARDANDO',
  scheduled_at    timestamptz,
  started_at      timestamptz,
  finished_at     timestamptz,
  notes           text,
  created_by      uuid REFERENCES app.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, order_number)
);
CREATE INDEX ix_log_orders_tenant_status ON app.logistics_orders(tenant_id, status);
CREATE TRIGGER trg_log_orders_updated BEFORE UPDATE ON app.logistics_orders
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_log_orders_tenant BEFORE INSERT OR UPDATE ON app.logistics_orders
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  HOURLY_PRODUCTIVITY (produtividade de descarga hora a hora)
-- =============================================================================
CREATE TABLE app.hourly_productivity (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  order_id      uuid REFERENCES app.logistics_orders(id) ON DELETE SET NULL,
  hour_start    timestamptz NOT NULL,               -- truncado na hora cheia
  dock          text NOT NULL DEFAULT 'GERAL',
  volumes       int  NOT NULL DEFAULT 0 CHECK (volumes >= 0),
  weight_kg     numeric(14,3) NOT NULL DEFAULT 0 CHECK (weight_kg >= 0),
  pallets       int  NOT NULL DEFAULT 0 CHECK (pallets >= 0),
  team_size     int  NOT NULL DEFAULT 1 CHECK (team_size > 0),
  target_volumes int NOT NULL DEFAULT 0 CHECK (target_volumes >= 0),
  recorded_by   uuid REFERENCES app.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (hour_start = date_trunc('hour', hour_start)),
  UNIQUE (tenant_id, dock, hour_start)
);
CREATE INDEX ix_hourly_tenant_hour ON app.hourly_productivity(tenant_id, hour_start DESC);
CREATE TRIGGER trg_hourly_updated BEFORE UPDATE ON app.hourly_productivity
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
CREATE TRIGGER trg_hourly_tenant BEFORE INSERT OR UPDATE ON app.hourly_productivity
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- =============================================================================
--  SALES (PDV) + itens + pagamentos
-- =============================================================================
CREATE TABLE app.sales (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  sale_number   bigint NOT NULL,
  status        app.sale_status NOT NULL DEFAULT 'FINALIZADA',
  subtotal      numeric(14,2) NOT NULL DEFAULT 0,
  discount      numeric(14,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  total         numeric(14,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  paid          numeric(14,2) NOT NULL DEFAULT 0,
  change_due    numeric(14,2) NOT NULL DEFAULT 0,
  customer_doc  text,
  cashier_id    uuid REFERENCES app.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  canceled_at   timestamptz,
  UNIQUE (tenant_id, sale_number)
);
CREATE INDEX ix_sales_tenant_date ON app.sales(tenant_id, created_at DESC);
CREATE TRIGGER trg_sales_tenant BEFORE INSERT OR UPDATE ON app.sales
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.sale_items (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  sale_id     uuid NOT NULL REFERENCES app.sales(id) ON DELETE CASCADE,
  product_id  uuid NOT NULL REFERENCES app.products(id),
  description text NOT NULL,
  qty         numeric(14,3) NOT NULL CHECK (qty > 0),
  unit_price  numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  total       numeric(14,2) NOT NULL
);
CREATE INDEX ix_sale_items_sale ON app.sale_items(sale_id);
CREATE TRIGGER trg_sale_items_tenant BEFORE INSERT ON app.sale_items
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

CREATE TABLE app.sale_payments (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  sale_id     uuid NOT NULL REFERENCES app.sales(id) ON DELETE CASCADE,
  method      app.payment_method NOT NULL,
  amount      numeric(14,2) NOT NULL CHECK (amount > 0)
);
CREATE TRIGGER trg_sale_pay_tenant BEFORE INSERT ON app.sale_payments
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();

-- Numeração sequencial de vendas por empresa (sem buracos entre tenants)
CREATE TABLE app.tenant_counters (
  tenant_id  uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  name       text NOT NULL,
  value      bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (tenant_id, name)
);

-- =============================================================================
--  AUDIT LOG (ações do Super Admin e eventos sensíveis)
-- =============================================================================
CREATE TABLE app.audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid REFERENCES app.tenants(id) ON DELETE SET NULL,
  user_id     uuid,
  action      text NOT NULL,
  details     jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
--  ROW LEVEL SECURITY
-- =============================================================================
ALTER TABLE app.tenants             ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.products            ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.stock_movements     ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.logistics_orders    ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.hourly_productivity ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.sales               ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.sale_items          ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.sale_payments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.tenant_counters     ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audit_log           ENABLE ROW LEVEL SECURITY;


-- ---- tenants -----------------------------------------------------------------
-- Usuário comum: vê e edita (marca) apenas a própria empresa.
-- SUPER_ADMIN: vê, cria, edita e remove qualquer empresa.
CREATE POLICY tenants_select ON app.tenants FOR SELECT
  USING (app.is_super_admin() OR id = app.current_tenant_id());
CREATE POLICY tenants_insert ON app.tenants FOR INSERT
  WITH CHECK (app.is_super_admin());
CREATE POLICY tenants_update ON app.tenants FOR UPDATE
  USING (app.is_super_admin() OR id = app.current_tenant_id())
  WITH CHECK (app.is_super_admin() OR id = app.current_tenant_id());
CREATE POLICY tenants_delete ON app.tenants FOR DELETE
  USING (app.is_super_admin() AND NOT is_platform);

-- ---- tabelas operacionais: mesma regra para todas ----------------------------
-- tenant_id = contexto, ou SUPER_ADMIN (acesso global de suporte/gestão)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['users','products','stock_movements','logistics_orders',
                           'hourly_productivity','sales','sale_items','sale_payments',
                           'tenant_counters']
  LOOP
    EXECUTE format($f$
      CREATE POLICY %1$s_isolation ON app.%1$s
        USING (app.is_super_admin() OR tenant_id = app.current_tenant_id())
        WITH CHECK (app.is_super_admin() OR tenant_id = app.current_tenant_id())
    $f$, t);
  END LOOP;
END $$;

-- ---- audit_log: inserção livre para o próprio contexto, leitura só Super Admin
CREATE POLICY audit_insert ON app.audit_log FOR INSERT
  WITH CHECK (app.is_super_admin() OR tenant_id = app.current_tenant_id());
CREATE POLICY audit_select ON app.audit_log FOR SELECT
  USING (app.is_super_admin());

-- =============================================================================
--  Funções SECURITY DEFINER para o fluxo PRÉ-LOGIN
--  (sem contexto de tenant ainda; expõem o mínimo necessário)
--  Elas pertencem ao dono das tabelas, que não é sujeito ao RLS (sem FORCE),
--  então enxergam o necessário sem precisar de superusuário ou BYPASSRLS.
-- =============================================================================

-- 1) Tela de login: digitou o CNPJ → mostra logo/nome da empresa.
CREATE OR REPLACE FUNCTION app.public_tenant_branding(p_cnpj text)
RETURNS TABLE (cnpj text, nome_fantasia text, razao_social text, logo_url text,
               primary_color text, status app.tenant_status)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT t.cnpj, t.nome_fantasia, t.razao_social, t.logo_url, t.primary_color, t.status
    FROM app.tenants t
   WHERE t.cnpj = regexp_replace(p_cnpj, '\D', '', 'g')
$$;

-- 2) Login: devolve hash da senha + status da empresa para a API validar.
CREATE OR REPLACE FUNCTION app.auth_lookup(p_cnpj text, p_username text)
RETURNS TABLE (user_id uuid, tenant_id uuid, username text, full_name text,
               password_hash text, role app.user_role, user_active boolean,
               tenant_status app.tenant_status, license_expires_at date,
               nome_fantasia text, razao_social text, logo_url text,
               primary_color text, cnpj text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT u.id, t.id, u.username::text, u.full_name, u.password_hash, u.role, u.is_active,
         t.status, t.license_expires_at, t.nome_fantasia, t.razao_social, t.logo_url,
         t.primary_color, t.cnpj
    FROM app.users u
    JOIN app.tenants t ON t.id = u.tenant_id
   WHERE t.cnpj = regexp_replace(p_cnpj, '\D', '', 'g')
     AND lower(u.username::text) = lower(p_username)
$$;

-- 3) Validação a cada requisição (middleware): empresa ainda ativa? usuário ativo?
CREATE OR REPLACE FUNCTION app.session_check(p_user_id uuid, p_tenant_id uuid)
RETURNS TABLE (ok boolean, reason text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
DECLARE r record;
BEGIN
  SELECT u.is_active, u.role, t.status, t.license_expires_at
    INTO r
    FROM app.users u JOIN app.tenants t ON t.id = u.tenant_id
   WHERE u.id = p_user_id AND t.id = p_tenant_id;
  IF NOT FOUND THEN RETURN QUERY SELECT false, 'USUARIO_INEXISTENTE'; RETURN; END IF;
  IF NOT r.is_active THEN RETURN QUERY SELECT false, 'USUARIO_INATIVO'; RETURN; END IF;
  IF r.role <> 'SUPER_ADMIN' THEN
    IF r.status = 'BLOQUEADO' THEN RETURN QUERY SELECT false, 'EMPRESA_BLOQUEADA'; RETURN; END IF;
    IF r.license_expires_at < current_date THEN RETURN QUERY SELECT false, 'LICENCA_EXPIRADA'; RETURN; END IF;
  END IF;
  RETURN QUERY SELECT true, NULL::text;
END $$;

-- 4) Registro do último login (não exige contexto)
CREATE OR REPLACE FUNCTION app.touch_last_login(p_user_id uuid) RETURNS void
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  UPDATE app.users SET last_login_at = now() WHERE id = p_user_id
$$;

-- Próximo número de venda por empresa (respeita RLS: roda como invocador)
CREATE OR REPLACE FUNCTION app.next_counter(p_name text) RETURNS bigint
LANGUAGE sql VOLATILE AS $$
  INSERT INTO app.tenant_counters (tenant_id, name, value)
  VALUES (app.current_tenant_id(), p_name, 1)
  ON CONFLICT (tenant_id, name) DO UPDATE SET value = app.tenant_counters.value + 1
  RETURNING value
$$;

-- =============================================================================
--  PDV: fechamento de venda atômico com baixa de estoque
--  Roda como INVOCADOR → RLS garante que só produtos da própria empresa entram.
--  p_items:    [{"product_id": "...", "qty": 2}, ...]
--  p_payments: [{"method": "PIX", "amount": 10.50}, ...]
-- =============================================================================
CREATE OR REPLACE FUNCTION app.close_sale(
  p_items jsonb, p_payments jsonb, p_discount numeric DEFAULT 0,
  p_customer_doc text DEFAULT NULL, p_allow_negative_stock boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  v_sale_id  uuid := gen_random_uuid();
  v_subtotal numeric(14,2) := 0;
  v_total    numeric(14,2);
  v_paid     numeric(14,2);
  v_item     jsonb;
  v_prod     app.products%ROWTYPE;
  v_qty      numeric(14,3);
BEGIN
  IF app.current_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'Contexto de empresa ausente';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Venda sem itens';
  END IF;

  INSERT INTO app.sales (id, tenant_id, sale_number, status, cashier_id, customer_doc)
  VALUES (v_sale_id, app.current_tenant_id(), app.next_counter('sale'), 'FINALIZADA',
          app.current_user_id(), p_customer_doc);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (v_item->>'qty')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;

    -- trava a linha do produto (evita venda simultânea do mesmo estoque)
    SELECT * INTO v_prod FROM app.products
     WHERE id = (v_item->>'product_id')::uuid AND is_active
     FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produto % não encontrado nesta empresa', v_item->>'product_id';
    END IF;
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

  SELECT coalesce(sum(amount), 0) INTO v_paid FROM app.sale_payments WHERE sale_id = v_sale_id;
  IF v_paid < v_total THEN
    RAISE EXCEPTION 'Pagamento insuficiente: total %, pago %', v_total, v_paid;
  END IF;

  UPDATE app.sales
     SET subtotal = v_subtotal, discount = coalesce(p_discount, 0), total = v_total,
         paid = v_paid, change_due = v_paid - v_total
   WHERE id = v_sale_id;

  RETURN v_sale_id;
END $$;

-- Cancelamento devolve estoque
CREATE OR REPLACE FUNCTION app.cancel_sale(p_sale_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE AS $$
DECLARE r record;
BEGIN
  UPDATE app.sales SET status = 'CANCELADA', canceled_at = now()
   WHERE id = p_sale_id AND status = 'FINALIZADA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Venda não encontrada ou já cancelada'; END IF;
  FOR r IN SELECT product_id, qty FROM app.sale_items WHERE sale_id = p_sale_id LOOP
    UPDATE app.products SET stock_qty = stock_qty + r.qty WHERE id = r.product_id;
    INSERT INTO app.stock_movements (product_id, qty, reason, ref_id, user_id)
    VALUES (r.product_id, r.qty, 'CANCELAMENTO', p_sale_id, app.current_user_id());
  END LOOP;
END $$;

-- Painel de produtividade (view respeita RLS por ser security_invoker)
CREATE VIEW app.v_productivity_today WITH (security_invoker = true) AS
SELECT tenant_id, dock, hour_start, volumes, weight_kg, pallets, team_size, target_volumes,
       CASE WHEN team_size > 0 THEN round(volumes::numeric / team_size, 2) END AS volumes_per_person,
       CASE WHEN target_volumes > 0 THEN round(100.0 * volumes / target_volumes, 1) END AS pct_target
  FROM app.hourly_productivity
 WHERE hour_start >= date_trunc('day', now());

-- =============================================================================
--  TENANT_ASSETS — logo da empresa guardada no próprio banco (driver "db")
--  Ideal para hospedagem gratuita: sem serviço de arquivos extra, entra no
--  backup do banco e migra junto. Logos ficam em ~10–200 KB cada.
-- =============================================================================
CREATE TABLE app.tenant_assets (
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
  kind         text NOT NULL DEFAULT 'logo' CHECK (kind IN ('logo')),
  content_type text NOT NULL CHECK (content_type IN ('image/png','image/jpeg','image/webp')),
  data         bytea NOT NULL CHECK (octet_length(data) <= 2 * 1024 * 1024),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, kind)
);
CREATE TRIGGER trg_assets_tenant BEFORE INSERT OR UPDATE ON app.tenant_assets
  FOR EACH ROW EXECUTE FUNCTION app.enforce_tenant_id();
ALTER TABLE app.tenant_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_assets_isolation ON app.tenant_assets
  USING      (app.is_super_admin() OR tenant_id = app.current_tenant_id())
  WITH CHECK (app.is_super_admin() OR tenant_id = app.current_tenant_id());

-- Leitura pública SÓ da logo (a tela de login exibe antes de autenticar)
CREATE OR REPLACE FUNCTION app.public_tenant_logo(p_tenant_id uuid)
RETURNS TABLE (content_type text, data bytea, updated_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT a.content_type, a.data, a.updated_at
    FROM app.tenant_assets a
   WHERE a.tenant_id = p_tenant_id AND a.kind = 'logo'
$$;

-- =============================================================================
--  Permissões
-- =============================================================================
GRANT USAGE ON SCHEMA app TO app_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_api;
REVOKE ALL ON FUNCTION app.public_tenant_branding(text), app.auth_lookup(text, text),
                       app.session_check(uuid, uuid), app.touch_last_login(uuid),
                       app.public_tenant_logo(uuid) FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_api;
-- audit_log: API só insere e (super admin) lê
REVOKE UPDATE, DELETE ON app.audit_log FROM app_api;

COMMIT;
