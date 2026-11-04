-- =============================================================================
--  Seeds iniciais — rode como superusuário/owner logo após 01_schema.sql
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  ATENÇÃO: troque as senhas antes de colocar em produção.
--    Super Admin  → CNPJ 11.222.333/0001-81 · usuário: master · senha: Master@2026
--    Empresa demo → CNPJ 11.444.777/0001-61 · usuário: admin  · senha: Admin@2026
-- =============================================================================
BEGIN;
SET search_path = app, public;
-- Seeds rodam com o dono do banco (sem BYPASSRLS): contexto de Super Admin
-- só nesta transação para passar pelas políticas RLS.
SELECT set_config('app.role', 'SUPER_ADMIN', true);
SELECT set_config('app.bootstrap', 'on', true);

-- Tenant da plataforma (dono do sistema, onde vivem os SUPER_ADMIN)
INSERT INTO app.tenants (cnpj, razao_social, nome_fantasia, status, license_expires_at, is_platform, max_users)
VALUES ('11222333000181', 'IAHOPE TECHNOLOGY LTDA', 'IaHope-Technology', 'ATIVO', '2099-12-31', true, 50)
ON CONFLICT (cnpj) DO NOTHING;

INSERT INTO app.users (tenant_id, username, full_name, password_hash, role)
SELECT id, 'master', 'Administrador Master', crypt('Master@2026', gen_salt('bf', 10)), 'SUPER_ADMIN'
  FROM app.tenants WHERE cnpj = '11222333000181'
ON CONFLICT (tenant_id, username) DO NOTHING;

-- Empresa cliente de demonstração
INSERT INTO app.tenants (cnpj, razao_social, nome_fantasia, status, license_expires_at)
VALUES ('11444777000161', 'DISTRIBUIDORA EXEMPLO LTDA', 'Distribuidora Exemplo', 'ATIVO', current_date + 90)
ON CONFLICT (cnpj) DO NOTHING;

INSERT INTO app.users (tenant_id, username, full_name, password_hash, role)
SELECT id, 'admin', 'Gestor da Distribuidora', crypt('Admin@2026', gen_salt('bf', 10)), 'ADMIN'
  FROM app.tenants WHERE cnpj = '11444777000161'
ON CONFLICT (tenant_id, username) DO NOTHING;

INSERT INTO app.users (tenant_id, username, full_name, password_hash, role)
SELECT id, 'caixa1', 'Operador de Caixa 1', crypt('Caixa@2026', gen_salt('bf', 10)), 'CAIXA'
  FROM app.tenants WHERE cnpj = '11444777000161'
ON CONFLICT (tenant_id, username) DO NOTHING;

INSERT INTO app.products (tenant_id, sku, barcode, name, unit, price, cost, stock_qty, min_stock)
SELECT t.id, p.sku, p.barcode, p.name, p.unit, p.price, p.cost, p.stock, 5
  FROM app.tenants t,
       (VALUES ('CX-001', '7891000100103', 'Caixa de papelão 40x30x20', 'UN', 4.90, 2.10, 500),
               ('FT-002', '7891000200209', 'Fita adesiva transparente 45mm', 'UN', 7.50, 3.20, 200),
               ('PL-003', '7891000300305', 'Pallet PBR madeira', 'UN', 69.90, 41.00, 40),
               ('FS-004', '7891000400401', 'Filme stretch 500mm', 'RL', 54.00, 30.50, 60),
               ('ET-005', '7891000500507', 'Etiqueta térmica 100x150 (rolo)', 'RL', 32.00, 18.00, 80))
         AS p(sku, barcode, name, unit, price, cost, stock)
 WHERE t.cnpj = '11444777000161'
ON CONFLICT (tenant_id, sku) DO NOTHING;

COMMIT;
