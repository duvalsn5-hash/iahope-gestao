-- =============================================================================
--  Testes de isolamento RLS — rode conectado como app_api:
--    psql -U app_api -d gestao -v ON_ERROR_STOP=1 -f 99_rls_tests.sql
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
  PERFORM app.open_cash_session(50);   -- Fase 1: venda exige caixa aberto
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

-- ================================================================ FASE 1
-- ---------------------------------------------------------------- 7. clientes/fornecedores isolados
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
INSERT INTO app.partners (tenant_id, kind, doc, name)
  SELECT id, 'CLIENTE', '52998224725', 'Cliente secreto da Outra' FROM app.tenants WHERE cnpj = '45723174000110';
SELECT set_config('app.role', 'ADMIN', true);
DO $$ BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  ASSERT (SELECT count(*) FROM app.partners WHERE name LIKE '%secreto%') = 0, 'vazou cliente de outra empresa';
  -- o mesmo CPF pode existir em outra empresa
  INSERT INTO app.partners (kind, doc, name) VALUES ('CLIENTE', '52998224725', 'Cliente da Demo');
  BEGIN
    INSERT INTO app.partners (kind, doc, name) VALUES ('CLIENTE', '12345678900', 'CPF inválido');
    RAISE EXCEPTION 'FALHA: aceitou CPF inválido';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'OK 7: clientes isolados por empresa e CPF validado';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 8. caixa + venda a prazo
BEGIN;
SELECT set_config('app.role', 'CAIXA', true);
DO $$ DECLARE pid uuid; cid uuid; sid uuid; v jsonb; BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','caixa1') u), true);
  PERFORM set_config('app.user_id', (SELECT u.user_id::text FROM app.auth_lookup('11444777000161','caixa1') u), true);
  SELECT id INTO pid FROM app.products WHERE sku = 'FT-002';   -- R$ 7,50
  BEGIN
    PERFORM app.close_sale(jsonb_build_array(jsonb_build_object('product_id', pid, 'qty', 1)), '[{"method":"PIX","amount":7.5}]');
    RAISE EXCEPTION 'FALHA: vendeu sem caixa aberto';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;

  PERFORM app.open_cash_session(100);
  PERFORM app.cash_movement('SUPRIMENTO', 20, 'troco extra');
  PERFORM app.cash_movement('SANGRIA', 30, 'cofre');
  -- dinheiro: 10 por 7,50 → troco 2,50 (entra 7,50 líquido)
  PERFORM app.close_sale(jsonb_build_array(jsonb_build_object('product_id', pid, 'qty', 1)), '[{"method":"DINHEIRO","amount":10}]');
  -- troco não pode sair do cartão
  BEGIN
    PERFORM app.close_sale(jsonb_build_array(jsonb_build_object('product_id', pid, 'qty', 1)), '[{"method":"DEBITO","amount":10}]');
    RAISE EXCEPTION 'FALHA: deu troco em cartão';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;
  -- a prazo sem cliente → erro; com cliente → gera conta a receber
  BEGIN
    PERFORM app.close_sale(jsonb_build_array(jsonb_build_object('product_id', pid, 'qty', 2)), '[{"method":"PRAZO","amount":15}]');
    RAISE EXCEPTION 'FALHA: vendeu a prazo sem cliente';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;
  INSERT INTO app.partners (kind, doc, name) VALUES ('CLIENTE', '52998224725', 'Maria') RETURNING id INTO cid;
  sid := app.close_sale(jsonb_build_array(jsonb_build_object('product_id', pid, 'qty', 2)),
                        '[{"method":"PRAZO","amount":15}]', 0, NULL, false, cid, 15);
  ASSERT (SELECT count(*) FROM app.financial_entries WHERE ref_id = sid AND kind = 'RECEBER'
            AND amount = 15 AND due_date = current_date + 15) = 1, 'não gerou conta a receber';
  -- recebe 5 em dinheiro pelo caixa
  PERFORM app.settle_entry((SELECT id FROM app.financial_entries WHERE ref_id = sid), 5, 'DINHEIRO', true);
  ASSERT (SELECT status FROM app.financial_entries WHERE ref_id = sid) = 'PARCIAL', 'baixa parcial falhou';
  -- esperado na gaveta: 100 + 20 - 30 + 7,50 + 5 = 102,50
  v := app.close_cash_session(102.50, 'ok');
  ASSERT (v->>'expectedCash')::numeric = 102.50, format('esperado errado: %s', v->>'expectedCash');
  ASSERT (v->>'difference')::numeric = 0, 'diferença errada';
  ASSERT (v->>'salesCount')::int = 2, 'contagem de vendas errada';
  RAISE NOTICE 'OK 8: caixa (abre, sangria, suprimento, fecha = R$ 102,50) e venda a prazo → a receber';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 9. entrada de NF-e
BEGIN;
SELECT set_config('app.role', 'ADMIN', true);
DO $$ DECLARE pid uuid; before numeric; pur uuid; nf jsonb; BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  PERFORM set_config('app.user_id', (SELECT u.user_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  SELECT id, stock_qty INTO pid, before FROM app.products WHERE sku = 'FT-002';
  nf := jsonb_build_object(
    'supplier', jsonb_build_object('doc', '45.723.174/0001-10', 'name', 'Fornecedor Teste LTDA'),
    'accessKey', '25261145723174000110550010000012341000012345', 'number', '1234', 'series', '1',
    'issueDate', current_date, 'total', 300,
    'items', jsonb_build_array(
       jsonb_build_object('supplierCode', 'F-77', 'description', 'FITA 45MM CX C/12', 'qty', 5, 'unitPrice', 36,
                          'total', 180, 'factor', 12, 'productId', pid),
       jsonb_build_object('supplierCode', 'F-88', 'description', 'LACRE PLASTICO', 'qty', 100, 'unitPrice', 1.2,
                          'total', 120, 'factor', 1,
                          'newProduct', jsonb_build_object('sku', 'LC-006', 'name', 'Lacre plástico', 'price', 2.5))),
    'installments', jsonb_build_array(
       jsonb_build_object('document', '001', 'dueDate', current_date + 30, 'amount', 150),
       jsonb_build_object('document', '002', 'dueDate', current_date + 60, 'amount', 150)));
  pur := app.register_purchase(nf);
  ASSERT (SELECT stock_qty FROM app.products WHERE id = pid) = before + 60, 'estoque não entrou (5 cx × 12)';
  ASSERT (SELECT cost FROM app.products WHERE id = pid) = 3.00, 'custo unitário errado (180 / 60)';
  ASSERT (SELECT stock_qty FROM app.products WHERE sku = 'LC-006') = 100, 'produto novo não criado';
  ASSERT (SELECT count(*) FROM app.financial_entries WHERE ref_id = pur AND kind = 'PAGAR') = 2, 'duplicatas não viraram contas a pagar';
  ASSERT (SELECT kind FROM app.partners WHERE doc = '45723174000110') = 'FORNECEDOR', 'fornecedor não cadastrado';
  ASSERT (SELECT product_id FROM app.supplier_product_codes WHERE supplier_code = 'F-77') = pid, 'não aprendeu o código do fornecedor';
  BEGIN
    PERFORM app.register_purchase(nf);
    RAISE EXCEPTION 'FALHA: lançou a mesma nota duas vezes';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK 9: NF-e de compra → estoque (+60 com fator 12), custo, fornecedor, 2 contas a pagar; duplicada bloqueada';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 10. módulos só pelo Master
BEGIN;
SELECT set_config('app.role', 'ADMIN', true);
DO $$ BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  BEGIN
    UPDATE app.tenants SET modules = ARRAY['PDV','PRODUTIVIDADE','FINANCEIRO','COMPRAS','BALANCA'];
    RAISE EXCEPTION 'FALHA: cliente ativou módulo sozinho';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK 10: só o Master liga/desliga módulos';
END $$;
ROLLBACK;

-- ================================================================ OFICINA
-- ---------------------------------------------------------------- 11. OS completa
BEGIN;
SELECT set_config('app.role', 'ADMIN', true);
DO $$ DECLARE cid uuid; vid uuid; os uuid; pid uuid; sid uuid; st0 numeric; sale uuid; v jsonb; BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  PERFORM set_config('app.user_id', (SELECT u.user_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  INSERT INTO app.partners (kind, doc, name, phone) VALUES ('CLIENTE', '52998224725', 'João Motoqueiro', '83999990000') RETURNING id INTO cid;
  INSERT INTO app.vehicles (customer_id, plate, brand, model, year, km) VALUES (cid, 'QWE1A23', 'Honda', 'CG 160 Titan', 2022, 18000) RETURNING id INTO vid;
  INSERT INTO app.products (sku, name, unit, price, stock_qty) VALUES ('OL-10W30', 'Óleo 10W30 1L', 'UN', 38, 10) RETURNING id INTO pid;
  INSERT INTO app.service_catalog (name, price) VALUES ('Troca de óleo', 25) RETURNING id INTO sid;

  os := app.open_work_order(cid, vid, 'Barulho no motor e troca de óleo', 18500, '1/2', '{"Retrovisores": true}', NULL, NULL);
  ASSERT (SELECT number FROM app.work_orders WHERE id = os) = 1, 'numeração da OS';
  ASSERT (SELECT km FROM app.vehicles WHERE id = vid) = 18500, 'km da moto não atualizou';
  INSERT INTO app.work_order_items (work_order_id, kind, product_id, description, qty, unit_price, total)
    VALUES (os, 'PECA', pid, 'Óleo 10W30 1L', 1, 38, 38);
  INSERT INTO app.work_order_items (work_order_id, kind, service_id, description, qty, unit_price, total)
    VALUES (os, 'SERVICO', sid, 'Troca de óleo', 1, 25, 25);
  PERFORM app.set_work_order_status(os, 'ORCAMENTO', 'orçamento enviado');
  PERFORM app.set_work_order_status(os, 'APROVADA', 'cliente aprovou por WhatsApp');
  PERFORM app.set_work_order_status(os, 'PRONTA', NULL);
  BEGIN
    PERFORM app.set_work_order_status(os, 'ENTREGUE', NULL);
    RAISE EXCEPTION 'FALHA: entregou sem passar pelo caixa';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM app.close_work_order(os, '[{"method":"PIX","amount":63}]');
    RAISE EXCEPTION 'FALHA: fechou OS sem caixa aberto';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FALHA%' THEN RAISE; END IF; END;

  PERFORM app.open_cash_session(0);
  st0 := (SELECT stock_qty FROM app.products WHERE id = pid);
  sale := app.close_work_order(os, '[{"method":"DINHEIRO","amount":70}]', 30, current_date + 180, 21500);
  ASSERT (SELECT stock_qty FROM app.products WHERE id = pid) = st0 - 1, 'peça não baixou do estoque';
  ASSERT (SELECT total FROM app.sales WHERE id = sale) = 63, 'total da OS errado';
  ASSERT (SELECT change_due FROM app.sales WHERE id = sale) = 7, 'troco errado';
  ASSERT (SELECT status FROM app.work_orders WHERE id = os) = 'ENTREGUE', 'OS não ficou entregue';
  ASSERT (SELECT count(*) FROM app.sale_items WHERE sale_id = sale AND product_id IS NULL) = 1, 'serviço não entrou na venda';
  v := app.cash_summary(app.current_cash_session());
  ASSERT (v->>'expectedCash')::numeric = 63, format('caixa esperado %s', v->>'expectedCash');
  -- cancelar a venda devolve só a peça e reabre a OS como PRONTA
  PERFORM app.cancel_sale(sale);
  ASSERT (SELECT stock_qty FROM app.products WHERE id = pid) = st0, 'cancelamento não devolveu a peça';
  ASSERT (SELECT status FROM app.work_orders WHERE id = os) = 'PRONTA', 'OS não voltou para PRONTA';
  ASSERT (SELECT count(*) FROM app.work_order_events WHERE work_order_id = os) >= 5, 'linha do tempo incompleta';
  RAISE NOTICE 'OK 11: OS completa (abre, orça, aprova, fecha no caixa = R$ 63, troco 7, peça baixa; cancelamento devolve)';
END $$;
ROLLBACK;

-- ---------------------------------------------------------------- 12. motos e fotos isoladas
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
SELECT set_config('app.tmp_b', (SELECT id::text FROM app.tenants WHERE cnpj = '45723174000110'), true);
DO $$ DECLARE cid uuid; pid uuid; BEGIN
  INSERT INTO app.partners (tenant_id, kind, name) VALUES (current_setting('app.tmp_b')::uuid, 'CLIENTE', 'Cliente da Outra') RETURNING id INTO cid;
  INSERT INTO app.vehicles (tenant_id, customer_id, plate, model) VALUES (current_setting('app.tmp_b')::uuid, cid, 'SEG1R23', 'Moto secreta');
  SELECT id INTO pid FROM app.products WHERE sku = 'SEGREDO-1';
  INSERT INTO app.product_images (product_id, tenant_id, content_type, data) VALUES (pid, current_setting('app.tmp_b')::uuid, 'image/png', '\x89504e47');
END $$;
SELECT set_config('app.role', 'ADMIN', true);
DO $$ BEGIN
  PERFORM set_config('app.tenant_id', (SELECT u.tenant_id::text FROM app.auth_lookup('11444777000161','admin') u), true);
  ASSERT (SELECT count(*) FROM app.vehicles) = 0, 'vazou moto de outra empresa';
  ASSERT (SELECT count(*) FROM app.product_images) = 0, 'vazou foto de outra empresa';
  ASSERT (SELECT count(*) FROM app.work_orders) = 0, 'vazou OS de outra empresa';
  RAISE NOTICE 'OK 12: motos, OS e fotos isoladas por empresa';
END $$;
ROLLBACK;

-- limpeza
BEGIN;
SELECT set_config('app.role', 'SUPER_ADMIN', true);
DELETE FROM app.tenants WHERE cnpj = '45723174000110';
COMMIT;
\echo 'Todos os testes de RLS passaram.'
