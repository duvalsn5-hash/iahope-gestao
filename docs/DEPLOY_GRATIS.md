# Publicar de graça — passo a passo

> Desenvolvido por Edivaldo.Nascimento - IaHope-Technology

Tudo abaixo usa planos gratuitos. Tempo total: ~1 hora na primeira vez.
Você **não precisa instalar o Flutter**: o GitHub compila o APK, o Windows e o Web.

| Parte | Serviço gratuito | Limite que importa |
|---|---|---|
| Código + builds do app | **GitHub** + GitHub Actions | Repositório público: builds à vontade. Privado: cota mensal de minutos (o build Windows consome em dobro). |
| App Web | **GitHub Pages** | Site estático, sem "dormir". |
| Banco PostgreSQL | **Neon** (Free) | 1 GB por projeto; 100 CU-hora/mês; suspende após 5 min parado e acorda sozinho em segundos. |
| API Node.js | **Render** (Free) | Dorme após 15 min sem acesso; o primeiro acesso depois disso leva ~1 min. 750 h/mês por conta. |
| Logos das empresas | dentro do **Neon** (`STORAGE_DRIVER=db`) | Sem serviço extra, sem cartão. |
| APK e .exe | **GitHub Releases** | Download direto pelo link. |

---

## 1. GitHub — subir o código

1. Crie uma conta em github.com e um repositório (ex.: `iahope-gestao`).
2. Envie o conteúdo da pasta `gestao-iahope` para ele (pelo GitHub Desktop ou `git push`).
3. Em **Settings → Pages → Source**, escolha **GitHub Actions**.

O workflow **"API e banco"** já roda sozinho e confirma que o banco e o isolamento por CNPJ funcionam.

## 2. Neon — banco de dados

1. Crie conta em neon.com → **New Project**.
   - Região: **AWS US East (N. Virginia)** — a mesma do Render, para a API conversar rápido com o banco.
   - Postgres 16 ou 17.
2. **Economize horas:** em *Branches → main → Compute → Edit*, fixe o tamanho em **0.25 CU**. Assim as 100 CU-hora rendem ~400 horas de banco ligado por mês — sobra para uma operação de horário comercial.
3. Abra o **SQL Editor** (você está como `neondb_owner`) e rode, nesta ordem, colando o conteúdo de cada arquivo:
   1. `database/00_roles.sql` — **antes, troque a senha** do `app_api` por uma forte (12+ caracteres, maiúsculas, minúsculas, números e símbolos; o Neon recusa senha fraca).
   2. `database/01_schema.sql`
   3. `database/02_seed.sql`
   4. `database/03_fase1.sql` — módulos, clientes/fornecedores, caixa, financeiro, compras e balança
4. Troque as senhas de demonstração (ainda no SQL Editor):
   ```sql
   UPDATE app.users SET password_hash = crypt('SuaSenhaForte!2026', gen_salt('bf', 10))
    WHERE username = 'master';
   -- apague a empresa demo se não quiser usá-la:
   -- DELETE FROM app.tenants WHERE cnpj = '11444777000161';
   ```
5. Em **Dashboard → Connect**, escolha o usuário **`app_api`** (não o `neondb_owner`!), marque **Connection pooling** e copie a string. Fica assim:
   ```
   postgres://app_api:SENHA@ep-xxxx-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require
   ```
   Se a senha tiver `#` ou `@`, troque por `%23` e `%40` na string.

> Se você colar a string do `neondb_owner` por engano, a API **se recusa a iniciar** e mostra "INSEGURO" no log — de propósito, porque esse usuário ignora o isolamento entre empresas.

## 3. Render — API

1. Crie conta em render.com (pode entrar com o GitHub).
2. **New → Blueprint** → selecione o repositório. O arquivo `render.yaml` já configura tudo (Docker, plano Free, região Virginia, `/health`, segredo JWT gerado automaticamente).
3. Quando pedir, cole o `DATABASE_URL` do passo 2.5.
4. Aguarde o deploy e abra `https://iahope-gestao-api.onrender.com/health` (o nome pode variar). Deve responder `{"ok":true,...}`.

**Evitar a espera de 1 minuto (opcional):** crie um monitor grátis em cron-job.org ou UptimeRobot chamando `https://SUA-API.onrender.com/health` a cada 10 minutos. O `/health` não acessa o banco, então o Neon continua economizando horas. Um único serviço ligado o mês todo cabe nas 750 h do Render.

## 4. App — Web, Android e Windows

1. No GitHub: **Settings → Secrets and variables → Actions → Variables → New variable**
   - Nome: `API_URL` · Valor: `https://iahope-gestao-api.onrender.com` (sua URL do Render)
2. Em **Actions → App Flutter → Run workflow**.
3. Ao terminar:
   - **Web:** publicado em `https://SEU-USUARIO.github.io/iahope-gestao/`
   - **APK e Windows:** na execução do workflow, seção *Artifacts*.
4. Para uma versão "oficial" com link de download fixo, crie uma tag:
   ```bash
   git tag v1.0.0 && git push --tags
   ```
   Em *Releases* aparecem `iahope-gestao.apk` e `iahope-gestao-windows.zip`.
5. No Render, troque `CORS_ORIGIN` de `*` para `https://SEU-USUARIO.github.io`.

O workflow também roda `flutter analyze` e `flutter test`: se algo no código Flutter precisar de ajuste, o erro aparece ali.

## 5. Checklist final

- [ ] Login do Master funciona com a senha nova.
- [ ] Criar uma empresa pelo painel Master e entrar com o admin dela.
- [ ] Enviar a logo em *Empresa* e ver a logo na tela de login ao digitar o CNPJ.
- [ ] Fazer uma venda no PDV e imprimir/compartilhar o cupom.
- [ ] Bloquear a empresa no Master e conferir que o usuário dela é desconectado.

## Quando o gratuito deixa de bastar

- **Primeira venda do dia demorando** → plano pago do Render que não dorme, ou migrar para VPS.
- **Neon avisando limite de horas** → a operação está passando de ~400 h/mês de banco ativo.
- **Banco chegando a 1 GB** → muitas vendas acumuladas; hora de plano pago ou VPS.

Veja `docs/MIGRAR_PARA_HOSTING.md` — a migração não exige mudar código.
