#!/usr/bin/env bash
#
# backup-postgres.sh — vuelca CADA base de datos de cada contenedor
# marcado con la label "platform.backup=true".
#
# Requiere que POSTGRES_SUPERUSER esté disponible en el entorno donde
# corre este script (o expórtalo antes: export $(grep -v '^#' .env | xargs)).
#
# Uso manual:      ./backup-postgres.sh
# Uso con cron:     0 3 * * *  /ruta/a/platform-infra/backup-postgres.sh
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
  # Postgres compartido: puede haber varias bases (una por cliente),
  # así que las volcamos una a una en vez de asumir una sola.
  DATABASES="$(docker exec "$container" psql -U "$POSTGRES_SUPERUSER" -tAc \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';")"

  for db in $DATABASES; do
    echo "Volcando ${container}/${db}..."
    docker exec "$container" pg_dump -U "$POSTGRES_SUPERUSER" "$db" \
      > "${BACKUP_DIR}/${container}_${db}_${DATE}.sql"
  done
done

echo "Backups guardados en ${BACKUP_DIR}"

# TODO cuando lo actives en serio:
#  - subir los dumps a almacenamiento externo (OVH Object Storage, S3...)
#  - rotar/borrar dumps antiguos
#  - alertar si un pg_dump falla (set -e ya corta el script, falta el aviso)