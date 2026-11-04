-- =============================================================================
--  Testes de isolamento RLS — rode conectado como app_api:
--    psql -U app_api -d gestao -v ON_ERROR_STOP=1 -f 03_rls_tests.sql
--  Cada bloco termina em ROLLBACK, nada fica gravado.
-- =============================================================================
\set QUIET on
SET search_path = app, public;

-- Proteção: este script cria e depois APAGA a empresa de teste 45.723.174/0001-10.
-- Se ela já existir (cliente real com esse CNPJ), aborta sem tocar em nada.
DO $$ BEGIN
  PERFORM set_config('app.role', 'SUPER_ADMIN', true);
  IF EXISTS (SELECT 1 FROM app.tenants WHERE cnpj = '45723174000110') THEN
    RAISE EXCEPTION 'CNPJ de teste 45723174000110 já existe neste banco. Rode os testes num banco de teste.';
  END IF;
END $$;

-- Cria uma 2ª empresa de teste como Super Admin
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
INSERT INTO tenants (cnpj, razao_social, nome_fantasia) VALUES ('45723174000110', 'OUTRA EMPRESA LTDA', 'Outra');
INSERT INTO products (tenant_id, sku, barcode, name, price, stock_qty)
  SELECT id, 'SEGREDO-1', '7890000000001', 'Produto secreto da Outra', 10, 5 FROM tenants WHERE cnpj = '45723174000110';
COMMIT;

-- ---------------------------------------------------------------- 1. sem contexto
BEGIN;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM app.tenants) = 0,  'sem contexto não deve ver empresas';
  ASSERT (SELECT count(*) FROM app.products) = 0, 'sem contexto não deve ver produtos';
  RAISE NOTICE 'OK 1: sem contexto não enxerga nada';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 2. empresa demo
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
SELECT set_config('app.tmp_a', (SELECT id::text FROM app.tenants WHERE cnpj = '11444777000161'), true);
SELECT set_config('app.tmp_b', (SELECT id::text FROM app.tenants WHERE cnpj = '45723174000110'), true);
SELECT set_config('app.role', 'ADMIN', true);
SELECT set_config('app.tenant_id', current_setting('app.tmp_a'), true);
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM app.tenants) = 1, 'deve ver só a própria empresa';
  ASSERT (SELECT count(*) FROM app.products WHERE sku = 'SEGREDO-1') = 0, 'vazou produto de outra empresa';
  ASSERT (SELECT count(*) FROM app.products) = 5, 'deve ver os 5 produtos próprios';
  RAISE NOTICE 'OK 2: empresa demo vê só os próprios dados';
END $$;

-- 2b. tentar gravar com tenant_id de outra empresa
DO $$ BEGIN
  BEGIN
    INSERT INTO app.products (tenant_id, sku, name) VALUES (current_setting('app.tmp_b')::uuid, 'INVASAO', 'x');
    RAISE EXCEPTION 'FALHA: inseriu em outra empresa';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK 2b: INSERT em outra empresa bloqueado pelo RLS';
  END;
END $$;

-- 2c. tentar UPDATE em produto alheio (afeta 0 linhas)
DO $$ DECLARE n int; BEGIN
  UPDATE app.products SET price = 0 WHERE sku = 'SEGREDO-1';
  GET DIAGNOSTICS n = ROW_COUNT;
  ASSERT n = 0, 'FALHA: alterou produto de outra empresa';
  RAISE NOTICE 'OK 2c: UPDATE em outra empresa afeta 0 linhas';
END $$;

-- 2d. cliente tentando se desbloquear / estender licença
DO $$ BEGIN
  BEGIN
    UPDATE app.tenants SET license_expires_at = '2099-01-01';
    RAISE EXCEPTION 'FALHA: cliente alterou a própria licença';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    RAISE NOTICE 'OK 2d: cliente não altera status/licença (%)', SQLERRM;
  END;
END $$;

-- 2e. cliente pode trocar a própria logo
DO $$ DECLARE n int; BEGIN
  UPDATE app.tenants SET logo_url = '/uploads/logo.png';
  GET DIAGNOSTICS n = ROW_COUNT;
  ASSERT n = 1, 'cliente deveria poder alterar a logo';
  RAISE NOTICE 'OK 2e: cliente altera a própria logo';
END $$;

-- 2f. cliente não pode se promover a SUPER_ADMIN
DO $$ BEGIN
  BEGIN
    UPDATE app.users SET role = 'SUPER_ADMIN' WHERE username = 'admin';
    RAISE EXCEPTION 'FALHA: virou super admin';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF;
    RAISE NOTICE 'OK 2f: escalada para SUPER_ADMIN bloqueada';
  END;
END $$;

-- 2g. venda no PDV com baixa de estoque
DO $$ DECLARE sid uuid; pid uuid; before numeric; after numeric; BEGIN
  SELECT id, stock_qty INTO pid, before FROM app.products WHERE sku = 'CX-001';
  PERFORM set_config('app.user_id', (SELECT id::text FROM app.users WHERE username = 'caixa1'), true);
  sid := app.close_sale(jsonb_build_array(jsonb_build_object('product_id', pid, 'qty', 3)),
                        '[{"method":"DINHEIRO","amount":20}]');
  SELECT stock_qty INTO after FROM app.products WHERE id = pid;
  ASSERT after = before - 3, 'estoque não baixou';
  ASSERT (SELECT total FROM app.sales WHERE id = sid) = 14.70, 'total errado';
  ASSERT (SELECT change_due FROM app.sales WHERE id = sid) = 5.30, 'troco errado';
  RAISE NOTICE 'OK 2g: venda fechada, estoque % → %, troco 5,30', before, after;
END $$;

-- 2h. vender produto de outra empresa pelo PDV
DO $$ BEGIN
  BEGIN
    PERFORM app.close_sale(
      jsonb_build_array(jsonb_build_object('product_id',
        (SELECT id FROM app.products WHERE false UNION ALL SELECT current_setting('app.tmp_b')::uuid LIMIT 1), 'qty', 1)),
      '[{"method":"PIX","amount":100}]');
    RAISE EXCEPTION 'FALHA';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'FALHA' THEN RAISE; END IF;
    RAISE NOTICE 'OK 2h: produto fora da empresa rejeitado (%)', SQLERRM;
  END;
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 3. super admin
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
DO $$ DECLARE n int; BEGIN
  ASSERT (SELECT count(*) FROM app.tenants) >= 3, 'super admin deve ver todas as empresas';
  UPDATE app.tenants SET status = 'BLOQUEADO', blocked_reason = 'Inadimplência' WHERE cnpj = '45723174000110';
  GET DIAGNOSTICS n = ROW_COUNT;
  ASSERT n = 1, 'super admin deveria bloquear';
  RAISE NOTICE 'OK 3: super admin vê todas e bloqueia empresa';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 4. funções pré-login
BEGIN;
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM app.public_tenant_branding('11.444.777/0001-61');
  ASSERT r.nome_fantasia = 'Distribuidora Exemplo', 'branding falhou';
  SELECT * INTO r FROM app.auth_lookup('11.444.777/0001-61', 'ADMIN');
  ASSERT r.password_hash = crypt('Admin@2026', r.password_hash), 'hash/senha não confere';
  RAISE NOTICE 'OK 4: branding e auth_lookup pré-login funcionam';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 5. logos no banco
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
SELECT set_config('app.tmp_b', (SELECT id::text FROM app.tenants WHERE cnpj = '45723174000110'), true);
INSERT INTO app.tenant_assets (tenant_id, content_type, data)
  VALUES (current_setting('app.tmp_b')::uuid, 'image/png', '\x89504e47'::bytea);
SELECT set_config('app.role', 'ADMIN', true);
DO $$ BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  ASSERT (SELECT count(*) FROM app.tenant_assets) = 0, 'vazou logo de outra empresa pela tabela';
  ASSERT (SELECT count(*) FROM app.public_tenant_logo(current_setting('app.tmp_b')::uuid)) = 1,
         'logo pública deveria ser legível pela função';
  RAISE NOTICE 'OK 5: logo isolada na tabela e pública só pela função';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 6. API não pode ser dona
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'app' AND tableowner = current_user),
         'PERIGO: este usuário é DONO das tabelas, o RLS não se aplica a ele. Conecte a API como app_api.';
  ASSERT NOT (SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname = current_user),
         'PERIGO: este usuário tem BYPASSRLS/superuser.';
  RAISE NOTICE 'OK 6: usuário da API não é dono nem ignora RLS';
END $$;

-- limpeza
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
DELETE FROM app.tenants WHERE cnpj = '45723174000110';
COMMIT;
\echo 'Todos os testes de RLS passaram.'
