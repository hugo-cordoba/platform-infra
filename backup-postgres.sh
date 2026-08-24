#!/usr/bin/env bash
#
# backup-postgres.sh — punto de partida, aún sin cron configurado.
#
# Vuelca la BD de cada contenedor Postgres que lleve la label
# "platform.backup=true" en su docker-compose.yml (añádela al servicio
# "db" de cada cliente cuando quieras que entre en el backup).
#
# Uso manual:      ./backup-postgres.sh
# Uso con cron:     0 3 * * *  /ruta/a/platform-infra/backups/backup-postgres.sh
#
set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dumps"
mkdir -p "$BACKUP_DIR"
DATE="$(date +%Y-%m-%d_%H%M)"

CONTAINERS="$(docker ps --filter "label=platform.backup=true" --format '{{.Names}}')"

if [ -z "$CONTAINERS" ]; then
  echo "Ningún contenedor tiene la label platform.backup=true todavía."
  exit 0
fi

for container in $CONTAINERS; do
  echo "Volcando ${container}..."
  docker exec "$container" sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' \
    > "${BACKUP_DIR}/${container}_${DATE}.sql"
done

echo "Backups guardados en ${BACKUP_DIR}"

# TODO cuando lo actives en serio:
#  - subir los dumps a almacenamiento externo (OVH Object Storage, S3...)
#  - rotar/borrar dumps antiguos
#  - alertar si un pg_dump falla (set -e ya corta el script, falta el aviso)
