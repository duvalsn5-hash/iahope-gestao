#!/usr/bin/env bash
# Backup diário do banco (inclui as logos, se STORAGE_DRIVER=db).
# Agende no crontab da VPS:  0 3 * * *  /caminho/deploy/vps/backup.sh
# Mantém os últimos 14 dias.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups
F="backups/gestao-$(date +%F).dump"
docker compose exec -T db pg_dump -U postgres -d gestao -Fc > "$F"
find backups -name 'gestao-*.dump' -mtime +14 -delete
echo "Backup salvo em $F"
