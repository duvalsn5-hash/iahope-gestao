-- =============================================================================
--  Papel usado pela API — rode UMA vez, antes do 01_schema.sql
--  (no Neon: SQL Editor, logado como neondb_owner; numa VPS: como postgres)
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  TROQUE A SENHA. O Neon exige senha forte (≥ 60 bits de entropia):
--  12+ caracteres misturando maiúsculas, minúsculas, números e símbolos,
--  sem palavras de dicionário. Exemplo do formato: Kq7#vR2m!Lp9xW4z
--
--  Este papel NÃO é dono das tabelas e NÃO tem BYPASSRLS → toda consulta
--  da API passa pelas políticas de isolamento por CNPJ.
-- =============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_api') THEN
    CREATE ROLE app_api WITH LOGIN PASSWORD 'TROQUE-Kq7#vR2m!Lp9xW4z';
  END IF;
END $$;

-- Para trocar a senha depois:
-- ALTER ROLE app_api WITH PASSWORD 'nova-senha-forte';
