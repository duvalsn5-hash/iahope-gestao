-- =============================================================================
--  IAHOPE GESTÃO — CATEGORIA DE NEGÓCIO (ramo da empresa) + CATEGORIA DE PRODUTO
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  Ordem: 00 → 01 → 02 → 03 → 04 → 05  (rode UMA vez, como dono do banco)
-- =============================================================================
BEGIN;
SET search_path = app, public;

-- -----------------------------------------------------------------------------
--  Ramo da empresa: define módulos sugeridos, categorias de produto e textos do app
-- -----------------------------------------------------------------------------
ALTER TABLE app.tenants ADD COLUMN business_category text NOT NULL DEFAULT 'OUTRO'
  CHECK (business_category IN ('OFICINA_MOTO','MERCADINHO','ESTAMPARIA','MODA','LOJA','DISTRIBUIDORA','OUTRO'));

-- Empresas que já existem: deduz o ramo pelos módulos contratados
UPDATE app.tenants SET business_category = CASE
    WHEN is_platform                      THEN 'OUTRO'
    WHEN 'OFICINA' = ANY(modules)         THEN 'OFICINA_MOTO'
    WHEN 'BALANCA' = ANY(modules)         THEN 'MERCADINHO'
    WHEN 'PRODUTIVIDADE' = ANY(modules)   THEN 'DISTRIBUIDORA'
    ELSE 'LOJA' END;
-- empresa de demonstração
UPDATE app.tenants SET business_category = 'MERCADINHO' WHERE cnpj = '11444777000161';

-- Login devolve também o ramo
DROP FUNCTION app.auth_lookup(text, text);
CREATE FUNCTION app.auth_lookup(p_cnpj text, p_username text)
RETURNS TABLE (user_id uuid, tenant_id uuid, username text, full_name text,
               password_hash text, role app.user_role, user_active boolean,
               tenant_status app.tenant_status, license_expires_at date,
               nome_fantasia text, razao_social text, logo_url text,
               primary_color text, cnpj text, modules text[], business_category text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT u.id, t.id, u.username::text, u.full_name, u.password_hash, u.role, u.is_active,
         t.status, t.license_expires_at, t.nome_fantasia, t.razao_social, t.logo_url,
         t.primary_color, t.cnpj, t.modules, t.business_category
    FROM app.users u
    JOIN app.tenants t ON t.id = u.tenant_id
   WHERE t.cnpj = regexp_replace(p_cnpj, '\D', '', 'g')
     AND lower(u.username::text) = lower(p_username)
$$;
REVOKE ALL ON FUNCTION app.auth_lookup(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.auth_lookup(text, text) TO app_api;

-- -----------------------------------------------------------------------------
--  Categoria do produto (texto livre; o app sugere as do ramo)
-- -----------------------------------------------------------------------------
ALTER TABLE app.products ADD COLUMN category text CHECK (category IS NULL OR length(category) BETWEEN 1 AND 40);
CREATE INDEX ix_products_category ON app.products(tenant_id, lower(category)) WHERE category IS NOT NULL;

COMMIT;
