-- =============================================================================
--  IAHOPE GESTÃO — CAMADAS DE SEGURANÇA
--  Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
-- =============================================================================
--  Ordem: 00 → … → 06 → 07  (rode UMA vez, como dono do banco)
--   • bloqueio de usuário após tentativas de senha erradas
--   • verificação em duas etapas (TOTP) por usuário
--   • troca de senha obrigatória no 1º acesso
--   • versão do token: trocar senha / "sair de todos" derruba sessões abertas
--   • limite de desconto do caixa (acima disso, só com gerente)
--   • auditoria legível pelo administrador da própria empresa
--   • limites de tempo das consultas da API
-- =============================================================================
BEGIN;
SET search_path = app, public;
SELECT set_config('app.role', 'SUPER_ADMIN', true);

ALTER TABLE app.users
  ADD COLUMN failed_logins        int NOT NULL DEFAULT 0,
  ADD COLUMN locked_until         timestamptz,
  ADD COLUMN token_version        int NOT NULL DEFAULT 1,
  ADD COLUMN must_change_password boolean NOT NULL DEFAULT false,
  ADD COLUMN password_changed_at  timestamptz,
  ADD COLUMN totp_secret          text,          -- base32; só vale com totp_enabled
  ADD COLUMN totp_enabled         boolean NOT NULL DEFAULT false,
  ADD COLUMN totp_last_step       bigint;        -- impede reutilizar o mesmo código

-- Desconto máximo que o caixa dá sozinho (% do subtotal); acima disso pede gerente
ALTER TABLE app.tenants ADD COLUMN max_discount_pct numeric(5,2) NOT NULL DEFAULT 10
  CHECK (max_discount_pct >= 0 AND max_discount_pct <= 100);

-- Contas da demonstração continuam usáveis, mas pedem troca da senha padrão
UPDATE app.users SET must_change_password = true
 WHERE username::text IN ('admin', 'caixa1')
   AND tenant_id = (SELECT id FROM app.tenants WHERE cnpj = '11444777000161');

CREATE INDEX IF NOT EXISTS ix_audit_tenant_date ON app.audit_log(tenant_id, created_at DESC);

-- O administrador da empresa lê a auditoria da própria empresa (o Master lê tudo)
DROP POLICY audit_select ON app.audit_log;
CREATE POLICY audit_select ON app.audit_log FOR SELECT
  USING (app.is_super_admin() OR (tenant_id = app.current_tenant_id() AND current_setting('app.role', true) IN ('ADMIN', 'GERENTE')));

-- Ninguém altera nem apaga a auditoria (só o dono do banco)
REVOKE UPDATE, DELETE ON app.audit_log FROM app_api;

-- -----------------------------------------------------------------------------
--  Login: devolve também os campos de segurança
-- -----------------------------------------------------------------------------
DROP FUNCTION app.auth_lookup(text, text);
CREATE FUNCTION app.auth_lookup(p_cnpj text, p_username text)
RETURNS TABLE (user_id uuid, tenant_id uuid, username text, full_name text,
               password_hash text, role app.user_role, user_active boolean,
               tenant_status app.tenant_status, license_expires_at date,
               nome_fantasia text, razao_social text, logo_url text,
               primary_color text, cnpj text, modules text[], business_category text,
               failed_logins int, locked_until timestamptz, token_version int,
               must_change_password boolean, totp_enabled boolean, max_discount_pct numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT u.id, t.id, u.username::text, u.full_name, u.password_hash, u.role, u.is_active,
         t.status, t.license_expires_at, t.nome_fantasia, t.razao_social, t.logo_url,
         t.primary_color, t.cnpj, t.modules, t.business_category,
         u.failed_logins, u.locked_until, u.token_version, u.must_change_password, u.totp_enabled,
         t.max_discount_pct
    FROM app.users u
    JOIN app.tenants t ON t.id = u.tenant_id
   WHERE t.cnpj = regexp_replace(p_cnpj, '\D', '', 'g')
     AND lower(u.username::text) = lower(p_username)
$$;
REVOKE ALL ON FUNCTION app.auth_lookup(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.auth_lookup(text, text) TO app_api;

-- A cada requisição: empresa ativa, licença, usuário ativo E versão do token
DROP FUNCTION app.session_check(uuid, uuid);
CREATE FUNCTION app.session_check(p_user_id uuid, p_tenant_id uuid)
RETURNS TABLE (ok boolean, reason text, modules text[], token_version int, must_change_password boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
DECLARE r record;
BEGIN
  SELECT u.is_active, u.role, u.token_version AS tv, u.must_change_password AS mcp,
         t.status, t.license_expires_at, t.modules
    INTO r
    FROM app.users u JOIN app.tenants t ON t.id = u.tenant_id
   WHERE u.id = p_user_id AND t.id = p_tenant_id;
  IF NOT FOUND THEN RETURN QUERY SELECT false, 'USUARIO_INEXISTENTE', NULL::text[], 0, false; RETURN; END IF;
  IF NOT r.is_active THEN RETURN QUERY SELECT false, 'USUARIO_INATIVO', NULL::text[], 0, false; RETURN; END IF;
  IF r.role <> 'SUPER_ADMIN' THEN
    IF r.status = 'BLOQUEADO' THEN RETURN QUERY SELECT false, 'EMPRESA_BLOQUEADA', NULL::text[], 0, false; RETURN; END IF;
    IF r.license_expires_at < current_date THEN RETURN QUERY SELECT false, 'LICENCA_EXPIRADA', NULL::text[], 0, false; RETURN; END IF;
  END IF;
  RETURN QUERY SELECT true, NULL::text, r.modules, r.tv, r.mcp;
END $$;
REVOKE ALL ON FUNCTION app.session_check(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.session_check(uuid, uuid) TO app_api;

-- Mesmo retorno do auth_lookup, pelo id (2º passo do login com 2 etapas)
CREATE FUNCTION app.auth_lookup_id(p_user_id uuid)
RETURNS TABLE (user_id uuid, tenant_id uuid, username text, full_name text,
               password_hash text, role app.user_role, user_active boolean,
               tenant_status app.tenant_status, license_expires_at date,
               nome_fantasia text, razao_social text, logo_url text,
               primary_color text, cnpj text, modules text[], business_category text,
               failed_logins int, locked_until timestamptz, token_version int,
               must_change_password boolean, totp_enabled boolean, max_discount_pct numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT a.* FROM app.users u JOIN app.tenants t ON t.id = u.tenant_id,
         LATERAL app.auth_lookup(t.cnpj, u.username::text) a
   WHERE u.id = p_user_id
$$;
REVOKE ALL ON FUNCTION app.auth_lookup_id(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.auth_lookup_id(uuid) TO app_api;

-- Resultado da senha antes do login (sem contexto de empresa): conta erros,
-- bloqueia por 15 min a partir da 5ª tentativa e grava na auditoria.
CREATE OR REPLACE FUNCTION app.login_attempt(p_user_id uuid, p_ok boolean, p_ip text)
RETURNS TABLE (fails int, locked timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = app, pg_temp AS $$
DECLARE u app.users%ROWTYPE;
BEGIN
  IF p_ok THEN
    UPDATE app.users SET failed_logins = 0, locked_until = NULL, last_login_at = now()
     WHERE id = p_user_id RETURNING * INTO u;
  ELSE
    UPDATE app.users
       SET failed_logins = app.users.failed_logins + 1,
           locked_until = CASE WHEN app.users.failed_logins + 1 >= 5 THEN now() + interval '15 minutes' ELSE app.users.locked_until END
     WHERE id = p_user_id RETURNING * INTO u;
  END IF;
  IF FOUND THEN
    INSERT INTO app.audit_log (tenant_id, user_id, action, details)
    VALUES (u.tenant_id, u.id, CASE WHEN p_ok THEN 'LOGIN_OK' ELSE 'LOGIN_FALHA' END,
            jsonb_build_object('ip', p_ip, 'tentativas', u.failed_logins,
                               'bloqueado_ate', u.locked_until));
  END IF;
  RETURN QUERY SELECT u.failed_logins, u.locked_until;
END $$;
REVOKE ALL ON FUNCTION app.login_attempt(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.login_attempt(uuid, boolean, text) TO app_api;

-- Segundo passo do login: lê o segredo TOTP e marca o passo usado (anti-reuso)
CREATE OR REPLACE FUNCTION app.totp_secret_for(p_user_id uuid) RETURNS TABLE (secret text, last_step bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  SELECT totp_secret, totp_last_step FROM app.users WHERE id = p_user_id AND totp_enabled
$$;
CREATE OR REPLACE FUNCTION app.totp_mark_step(p_user_id uuid, p_step bigint) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = app, pg_temp AS $$
  UPDATE app.users SET totp_last_step = p_step
   WHERE id = p_user_id AND (totp_last_step IS NULL OR totp_last_step < p_step)
  RETURNING true
$$;
REVOKE ALL ON FUNCTION app.totp_secret_for(uuid), app.totp_mark_step(uuid, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.totp_secret_for(uuid), app.totp_mark_step(uuid, bigint) TO app_api;

-- Trocar senha/perfil/ativo de alguém derruba as sessões abertas dessa pessoa
CREATE OR REPLACE FUNCTION app.bump_token_version() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.password_hash IS DISTINCT FROM OLD.password_hash THEN
    NEW.password_changed_at := now();
    NEW.token_version := OLD.token_version + 1;
  ELSIF NEW.is_active IS DISTINCT FROM OLD.is_active OR NEW.role IS DISTINCT FROM OLD.role
        OR NEW.totp_enabled IS DISTINCT FROM OLD.totp_enabled THEN
    NEW.token_version := OLD.token_version + 1;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_users_token_version BEFORE UPDATE ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.bump_token_version();

-- -----------------------------------------------------------------------------
--  Limites de tempo da API (consulta travada não segura o banco)
-- -----------------------------------------------------------------------------
ALTER ROLE app_api SET statement_timeout = '20s';
ALTER ROLE app_api SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE app_api SET lock_timeout = '10s';

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO app_api;
COMMIT;
