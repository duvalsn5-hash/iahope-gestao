# IaHope Gestão — Operação, Logística e PDV

Sistema multiplataforma (**Android · Windows Desktop · Web**) com isolamento estrito por **CNPJ** (multi-tenant com Row Level Security no PostgreSQL), **Administração Master** de licenças e **White-Label** (logo e cor de cada empresa).

> **Desenvolvido por Edivaldo.Nascimento - IaHope-Technology**

### Publicar

- **De graça (GitHub + Neon + Render):** [`docs/DEPLOY_GRATIS.md`](docs/DEPLOY_GRATIS.md)
- **Depois, em hospedagem própria (VPS):** [`docs/MIGRAR_PARA_HOSTING.md`](docs/MIGRAR_PARA_HOSTING.md)

O mesmo código roda nos dois; só mudam variáveis de ambiente.

---

## 1. Visão geral da arquitetura

```
┌──────────────── Flutter (1 código) ────────────────┐
│  Android (toque + câmera) · Windows (F1–F12) · Web │
│  Clean Architecture feature-first + Riverpod       │
└───────────────┬────────────────────────────────────┘
                │ HTTPS + JWT (Bearer)
┌───────────────▼────────────────────────────────────┐
│  API Node.js 22 + TypeScript (Express 5)           │
│  • valida JWT e, a cada requisição, se a empresa   │
│    está ATIVA e com licença válida (session_check) │
│  • abre transação e define o contexto RLS:         │
│    app.tenant_id / app.user_id / app.role          │
└───────────────┬────────────────────────────────────┘
                │ papel app_api (sem BYPASSRLS)
┌───────────────▼────────────────────────────────────┐
│  PostgreSQL 14+  ·  ROW LEVEL SECURITY             │
│  tenant_id = contexto  OU  role = SUPER_ADMIN      │
└────────────────────────────────────────────────────┘
```

**Três camadas de segurança** (defesa em profundidade):

1. **Banco (RLS)** — mesmo que a API tenha um bug, uma consulta sem `WHERE tenant_id` só enxerga a própria empresa. Sem contexto definido, não enxerga nada.
2. **API** — `requireAuth` confere o status da empresa a cada chamada (bloqueio feito pelo Master derruba sessões já abertas na próxima ação) e `requireRole` restringe por perfil.
3. **App** — rotas e menus só aparecem para o perfil certo; se a API responder `EMPRESA_BLOQUEADA`/`LICENCA_EXPIRADA`, o app encerra a sessão e mostra o motivo no login.

### Perfis

| Perfil | Acesso |
|---|---|
| `SUPER_ADMIN` | Tudo, de todas as empresas. Só existe no tenant da plataforma IaHope. Não é bloqueado por licença. |
| `ADMIN` | Tudo da própria empresa, inclusive logo/marca. |
| `GERENTE` | PDV, produtividade, produtos, cancelamento de venda. |
| `OPERADOR` | Produtividade e cargas. |
| `CAIXA` | PDV. |

---

## 1.1 Módulos e planos

O Master liga e desliga módulos por empresa (painel Master → **Módulos**). O núcleo vem sempre incluído.

| Módulo | O que libera |
|---|---|
| **Núcleo** (sempre) | Produtos e estoque (entrada, ajuste, contagem, histórico), clientes e fornecedores, empresa e logo |
| `PDV` | Frente de caixa com abertura, sangria, suprimento e fechamento (sobra/falta), cliente na venda, cupom com logo |
| `FINANCEIRO` | Contas a pagar e a receber, parcelamento, baixa parcial, venda **a prazo** gerando conta a receber, histórico de caixas |
| `COMPRAS` | Entrada de mercadoria pelo **XML da NF-e**: cadastra o fornecedor, soma estoque com fator de conversão (CX→UN), atualiza custo, gera contas a pagar das duplicatas e aprende o código do fornecedor |
| `PRODUTIVIDADE` | Descarga hora a hora por doca e carga |
| `BALANCA` | Leitura de etiqueta de balança (EAN-13 com prefixo 2, preço ou peso) no PDV |

A API bloqueia rotas de módulos não contratados (`MODULO_INATIVO`) e o app esconde os menus.

## 2. Estrutura de pastas

```
gestao-iahope/
├── database/
│   ├── 00_roles.sql         # cria o usuário app_api (troque a senha)
│   ├── 01_schema.sql        # DDL completo, RLS, funções, triggers, permissões
│   ├── 02_seed.sql          # Super Admin + empresa demo + produtos
│   ├── 03_fase1.sql         # módulos, clientes/fornecedores, caixa, financeiro, compras XML, balança
│   └── 99_rls_tests.sql     # 13 testes de isolamento (rodar como app_api, em banco de teste)
├── docs/                    # DEPLOY_GRATIS.md · MIGRAR_PARA_HOSTING.md
├── deploy/vps/              # produção em VPS: Caddy (HTTPS) + API + Postgres
├── render.yaml              # API no Render (plano Free) em 1 clique
├── .github/workflows/       # builds grátis do APK/Windows/Web + testes do banco
├── backend/                 # API Node.js/TypeScript
│   └── src/
│       ├── config/env.ts
│       ├── db/pool.ts                 # withTenant(): transação + contexto RLS
│       ├── middleware/{auth,errors}.ts
│       ├── utils/cnpj.ts
│       ├── storage/logo-storage.ts    # logos: banco | disco | S3/R2
│       └── modules/
│           ├── auth/auth.routes.ts            # branding, login, me
│           ├── admin/admin.routes.ts          # Super Admin
│           ├── tenants/company.routes.ts      # logo / marca
│           ├── products/products.routes.ts
│           ├── productivity/productivity.routes.ts
│           ├── pos/pos.routes.ts
│           └── public/public.routes.ts        # serve a logo guardada no banco
├── app/                     # Flutter
│   └── lib/
│       ├── main.dart · app.dart
│       ├── core/
│       │   ├── config/app_config.dart     # API_URL via --dart-define + créditos
│       │   ├── network/                   # Dio + interceptor JWT/bloqueio
│       │   ├── router/app_router.dart     # go_router com guarda por perfil
│       │   ├── storage/ · theme/ · utils/
│       │   └── widgets/                   # AppShell (atalhos F), logo, rodapé
│       └── features/
│           ├── auth/          {data, domain, presentation} → LoginScreen
│           ├── master_admin/  {data, domain, presentation} → MasterAdminDashboard
│           ├── company/       {data, presentation}         → CompanySettingsScreen
│           ├── productivity/  {data, domain, presentation} → ProductivityDashboard
│           ├── products/      {data, domain}
│           ├── pos/           {data, domain, presentation} → PosScreen + cupom
│           └── about/                                       → AboutScreen
└── docker-compose.yml       # PostgreSQL + API prontos
```

Cada feature segue **data** (repositórios HTTP) → **domain** (entidades imutáveis, sem Flutter) → **presentation** (controllers Riverpod `Notifier`/`AsyncNotifier` + telas). Sem geração de código (`build_runner` não é necessário).

---

## 3. Banco de dados

### Subir localmente com Docker (desenvolvimento)

```bash
docker compose up -d --build
# Postgres em localhost:5432 · API em http://localhost:3000
```

### Ou manualmente

```bash
createdb gestao
# 00 → 01 → 02 com o DONO do banco (postgres na VPS, neondb_owner no Neon)
psql -U postgres -d gestao -f database/00_roles.sql   # troque a senha antes
psql -U postgres -d gestao -f database/01_schema.sql
psql -U postgres -d gestao -f database/02_seed.sql
psql -U postgres -d gestao -f database/03_fase1.sql
# testes de isolamento — SÓ em banco de teste (devem terminar em "Todos os testes de RLS passaram.")
psql -U app_api -d gestao -f database/99_rls_tests.sql
```

> Não precisa de superusuário: os scripts funcionam no Neon, Supabase e qualquer Postgres gerenciado.
> **A API deve sempre conectar como `app_api`.** O dono das tabelas ignora o RLS — por isso a API verifica o usuário ao iniciar e **se recusa a subir** se estiver conectada como dono, superusuário ou com BYPASSRLS.

### Como o RLS funciona

```sql
-- toda tabela operacional:
CREATE POLICY products_isolation ON app.products
  USING      (app.is_super_admin() OR tenant_id = app.current_tenant_id())
  WITH CHECK (app.is_super_admin() OR tenant_id = app.current_tenant_id());
```

- `tenant_id` é preenchido automaticamente por trigger a partir do contexto.
- Trigger impede cliente de alterar `status`, `license_expires_at`, `cnpj` da própria empresa (só Super Admin).
- Trigger impede alguém de se promover a `SUPER_ADMIN`.
- Acesso pré-login usa só 4 funções `SECURITY DEFINER` estreitas: `public_tenant_branding`, `auth_lookup`, `session_check`, `touch_last_login`.
- Venda no PDV: `app.close_sale()` roda como invocador (respeita RLS), trava a linha do produto (`FOR UPDATE`), valida estoque, grava itens/pagamentos, baixa o estoque e registra `stock_movements` — tudo numa transação.

### Credenciais de demonstração (troque!)

| Uso | CNPJ | Usuário | Senha |
|---|---|---|---|
| Administrador Master | 11.222.333/0001-81 | `master` | `Master@2026` |
| Empresa demo (admin) | 11.444.777/0001-61 | `admin` | `Admin@2026` |
| Empresa demo (caixa) | 11.444.777/0001-61 | `caixa1` | `Caixa@2026` |

---

## 4. API

```bash
cd backend
cp .env.example .env      # ajuste DATABASE_URL, JWT_SECRET, PUBLIC_BASE_URL
npm install
npm run dev               # desenvolvimento
npm run build && npm start  # produção
```

| Método | Rota | Perfil | Descrição |
|---|---|---|---|
| GET | `/auth/branding/:cnpj` | público | Logo/nome da empresa para a tela de login |
| POST | `/auth/login` | público | `{cnpj, username, password}` → JWT + empresa + créditos. Recusa empresa bloqueada/licença vencida |
| GET | `/auth/me` | logado | Recarrega sessão (status, logo) |
| GET | `/admin/tenants?q=&status=` | SUPER_ADMIN | Lista todas as empresas |
| GET | `/admin/stats` | SUPER_ADMIN | Ativos, bloqueados, vencidos, vencendo em 7 dias |
| POST | `/admin/tenants` | SUPER_ADMIN | Cria cliente + usuário ADMIN |
| PATCH | `/admin/tenants/:id/status` | SUPER_ADMIN | `{status: ATIVO\|BLOQUEADO, reason}` |
| PATCH | `/admin/tenants/:id` | SUPER_ADMIN | Renova licença, edita dados |
| GET | `/admin/audit` | SUPER_ADMIN | Últimas ações |
| GET / PATCH | `/company` | logado / ADMIN | Dados e marca da própria empresa |
| POST / DELETE | `/company/logo` | ADMIN | Upload multipart (campo `logo`, PNG/JPG/WEBP ≤ 2 MB) → `{logoUrl}` |
| GET | `/products?q=` · `/products/barcode/:code` | logado | Busca e leitura de código |
| POST | `/products` · `/products/:id/stock` | ADMIN/GERENTE | Cadastro e entrada de estoque |
| POST | `/productivity/hourly` | ADMIN/GERENTE/OPERADOR | Lança volumes da doca na hora (soma) |
| GET | `/productivity/dashboard?date=` | logado | Série 00h–23h, totais por doca, cargas abertas |
| POST / PATCH | `/productivity/orders` · `/:id/status` | ADMIN/GERENTE/OPERADOR | Cargas de descarga |
| POST | `/pos/sales` | ADMIN/GERENTE/CAIXA | Fecha venda com baixa de estoque → cupom com logo |
| GET | `/pos/sales/:id` · `/pos/summary` | logado | Reimpressão e resumo do dia |
| POST | `/pos/sales/:id/cancel` | ADMIN/GERENTE | Cancela e devolve estoque |

Onde a logo fica é escolhido por `STORAGE_DRIVER`:

| Driver | Onde | Uso |
|---|---|---|
| `db` (padrão) | tabela `app.tenant_assets`, servida em `GET /public/logos/:tenantId` | Hospedagem gratuita e VPS — sem serviço extra, entra no backup do banco |
| `local` | pasta `UPLOAD_DIR` (`/uploads/...`) | VPS com disco persistente |
| `s3` | Cloudflare R2, Supabase Storage, MinIO, AWS | Muitos clientes / CDN |

A URL muda a cada envio (`?v=` ou nome com timestamp), então apps e navegadores nunca mostram a logo antiga.

---

## 5. App Flutter

Requer **Flutter 3.27+** (Dart 3.6+).

### Primeira vez — gerar as pastas de plataforma

> Sem Flutter instalado? O GitHub Actions compila tudo — ver `docs/DEPLOY_GRATIS.md`.

```bash
cd app
bash tool/setup_platforms.sh   # gera android/windows/web + permissões de internet e câmera
flutter pub get
flutter test
```

### Ajustes do Android

O `tool/setup_platforms.sh` já adiciona as permissões de internet e câmera. Só se a API estiver em `http://` (rede local, sem HTTPS), adicione na tag `<application>` de `android/app/src/main/AndroidManifest.xml`:

```xml
android:usesCleartextTraffic="true"
```

E em `android/app/build.gradle` garanta `minSdk = 21` (exigido pelo leitor por câmera).

### Rodar e compilar

A URL da API vai na compilação via `--dart-define` (sem mexer no código):

```bash
# Desenvolvimento
flutter run -d windows --dart-define=API_URL=http://localhost:3000
flutter run -d chrome  --dart-define=API_URL=http://localhost:3000
flutter run -d <android> --dart-define=API_URL=http://10.0.2.2:3000   # emulador

# Windows Desktop  → build/windows/x64/runner/Release/
flutter build windows --release --dart-define=API_URL=https://api.suaempresa.com.br

# Android APK      → build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --dart-define=API_URL=https://api.suaempresa.com.br

# Web              → build/web/  (publique em qualquer servidor estático)
flutter build web --release --dart-define=API_URL=https://api.suaempresa.com.br
```

> Para distribuir o Windows, copie a pasta `Release` inteira (o `.exe` precisa das DLLs ao lado).
> Na Web, a API precisa aceitar a origem do site em `CORS_ORIGIN`.

### Telas

| Tela | Destaques |
|---|---|
| **LoginScreen** | Máscara de CNPJ com validação dos dígitos; ao completar o CNPJ, mostra logo e nome da empresa; lembra o último CNPJ; mostra o motivo quando a empresa foi bloqueada; créditos no rodapé. |
| **MasterAdminDashboard** | KPIs (ativos, bloqueados, vencidos, vencendo em 7 dias), busca por CNPJ/nome, filtro por status, tabela no desktop / cards no celular, bloquear com motivo, reativar, renovar licença, novo cliente com admin inicial. |
| **CompanySettingsScreen** | Upload da logo (Android/Windows/Web via bytes), remover logo, nome fantasia, cor da marca — o tema do app inteiro muda na hora. |
| **ProductivityDashboard** | Atualização automática a cada 20 s, gráfico de colunas hora a hora com linha de meta (verde/âmbar/vermelho), totais por doca, cargas em aberto com progresso, lançamento rápido (F7) e nova carga (F8). |
| **PosScreen** | Campo de busca sempre focado para leitor USB/Bluetooth (modo teclado + Enter), fila para leituras rápidas em sequência, multiplicador `3*código`, câmera no Android, múltiplas formas de pagamento com troco, cupom 80 mm com logo (impressora térmica no Windows, compartilhar no Android, imprimir na Web). |
| **AboutScreen** | Créditos, empresa, licença, servidor e lista de atalhos. |

### Atalhos de teclado

| Tecla | Ação |
|---|---|
| F1 | Sobre / Ajuda |
| F2 | PDV (no PDV: foco na busca) |
| F3 / F4 / F6 | Produtividade / Empresa / Master |
| F7 | PDV: quantidade · Produtividade: lançar |
| F8 | PDV: remover item · Produtividade: nova carga |
| F9 | PDV: desconto · Cupom: imprimir |
| F10 | PDV: finalizar · Pagamento: concluir |
| F1–F4 (no pagamento) | Dinheiro / PIX / Débito / Crédito |
| ↑ ↓ · + − | Navegar itens · quantidade (teclado numérico) |
| Ctrl+Del | Cancelar venda |
| Esc | Limpar busca |

F5, F11 e F12 ficam livres de propósito (o navegador usa para recarregar, tela cheia e DevTools).

---

## 6. Checklist de produção

- [ ] Trocar as senhas dos seeds e do papel `app_api`; gerar `JWT_SECRET` aleatório (64+ caracteres).
- [ ] Publicar a API atrás de HTTPS (Nginx/Caddy) e definir `PUBLIC_BASE_URL` com o domínio real.
- [ ] Restringir `CORS_ORIGIN` ao domínio do app Web.
- [ ] Backup diário do PostgreSQL (`deploy/vps/backup.sh`; com `STORAGE_DRIVER=db` as logos já vão junto).
- [ ] Rodar `99_rls_tests.sql` após qualquer mudança no schema.

---

**Desenvolvido por Edivaldo.Nascimento - IaHope-Technology**
