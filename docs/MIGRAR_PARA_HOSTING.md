# Migrar do gratuito para uma hospedagem própria

> Desenvolvido por Edivaldo.Nascimento - IaHope-Technology

O mesmo código roda nos dois cenários; só mudam variáveis de ambiente.

## Qual tipo de hospedagem contratar

| Tipo | Serve para | Observação |
|---|---|---|
| **Hospedagem compartilhada** (cPanel, "plano de site") | Só o **app Web** (arquivos estáticos) | Normalmente não oferece PostgreSQL nem processos Node.js/Docker contínuos, então não roda a API nem o banco. |
| **VPS** (servidor virtual Linux) | **Tudo**: app Web + API + banco | Recomendado. 2 GB de RAM e 1–2 vCPU atendem bem várias empresas pequenas. Precisa ter acesso root e suportar Docker. |
| Render/Neon pagos | API e banco, sem administrar servidor | Mais caro por recurso, zero manutenção. |

Ao escolher a VPS, prefira data center no Brasil (menor latência para os caixas) e confirme Ubuntu 22.04/24.04 com acesso SSH.

---

## Caminho recomendado: VPS com Docker

Tudo está pronto em `deploy/vps/`: **Caddy** (HTTPS automático com Let's Encrypt), **API** e **PostgreSQL**, num único `docker compose`.

### 1. Preparar a VPS

```bash
# na VPS (Ubuntu), como root
curl -fsSL https://get.docker.com | sh
git clone https://github.com/SEU-USUARIO/iahope-gestao.git /opt/iahope
cd /opt/iahope/deploy/vps
cp .env.example .env && nano .env      # domínios, senhas, JWT_SECRET
```

No seu provedor de domínio, crie dois registros **A** apontando para o IP da VPS:
`app.suaempresa.com.br` e `api.suaempresa.com.br`.

Em `database/00_roles.sql`, troque a senha do `app_api` pela mesma que você pôs (codificada) em `APP_API_PASSWORD_URLENCODED`.

### 2. Colocar o app Web

Baixe o build Web gerado pelo GitHub Actions (ou rode `flutter build web --dart-define=API_URL=https://api.suaempresa.com.br`) e copie o conteúdo de `build/web` para `deploy/vps/web/`.

> Na VPS o app fica na raiz do domínio, então gere o build **sem** `--base-href` (o padrão `/`).

### 3a. Instalação nova

```bash
docker compose up -d --build
docker compose logs -f api     # deve aparecer "API em http://0.0.0.0:3000 · logos: db"
```

### 3b. Vindo do Neon (levando todos os dados)

Como as logos estão no banco (`STORAGE_DRIVER=db`), **um único dump leva tudo**: empresas, usuários, produtos, vendas, produtividade e logos.

```bash
# 1) em deploy/vps/docker-compose.yml, comente a linha do 02_seed.sql
# 2) suba só o banco (cria app_api + schema vazio)
docker compose up -d db

# 3) exporte os DADOS do Neon (use a string do neondb_owner, SEM "-pooler")
docker compose exec -T db pg_dump \
  "postgres://neondb_owner:SENHA@ep-xxxx.us-east-1.aws.neon.tech/neondb?sslmode=require" \
  --data-only --schema=app -Fc > backups/neon.dump

# 4) importe na VPS (desliga gatilhos só durante a carga)
docker compose exec -T db pg_restore -U postgres -d gestao \
  --data-only --disable-triggers < backups/neon.dump

# 5) suba o resto
docker compose up -d --build
```

### 4. Apontar os apps para o novo endereço

- **GitHub → Variables → `API_URL`** = `https://api.suaempresa.com.br` e rode o workflow de novo (gera novo APK/Windows/Web).
- Instale o novo APK/Windows nos caixas. A versão antiga continuará apontando para o Render até ser substituída — mantenha o Render ligado por alguns dias, ou já desligue para forçar a troca.

### 5. Backup

```bash
crontab -e
# backup todo dia às 3h, mantém 14 dias
0 3 * * * /opt/iahope/deploy/vps/backup.sh >> /var/log/iahope-backup.log 2>&1
```

Copie a pasta `backups/` periodicamente para fora da VPS (Google Drive, outro servidor).

### Atualizar o sistema depois

```bash
cd /opt/iahope && git pull
cd deploy/vps && docker compose up -d --build
```

---

## Trocar onde ficam as logos (opcional)

| `STORAGE_DRIVER` | Quando usar |
|---|---|
| `db` (padrão) | Gratuito e VPS. Backup único, migração simples. |
| `local` | VPS com disco persistente, se preferir arquivos. Novas logos vão para o volume `uploads`. |
| `s3` | Muitos clientes / CDN: Cloudflare R2, Supabase Storage ou MinIO. Preencha as variáveis `S3_*`. |

Trocar o driver não move as logos já enviadas: cada empresa reenviar a logo resolve.
