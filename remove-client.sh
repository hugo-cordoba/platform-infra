#!/usr/bin/env bash
#
# remove-client.sh — da de baja un cliente: para sus contenedores y
# borra su BBDD/role. NO borra la carpeta del repo ni la entrada en
# clients.yaml (hazlo a mano tras confirmar que todo ha ido bien).
#
# Uso:
#   export $(grep -v '^#' .env | xargs)
#   ./scripts/remove-client.sh cliente-x [clients-dir]
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Uso: $0 <client-slug> [clients-dir]" >&2
  exit 1
fi

CLIENT_SLUG="$1"
CLIENTS_DIR="${2:-/srv/clients}"
DEST="${CLIENTS_DIR}/${CLIENT_SLUG}"

: "${POSTGRES_SUPERUSER:?Falta POSTGRES_SUPERUSER en el entorno (exporta el .env de platform-infra)}"

NORMALIZED="${CLIENT_SLUG//-/_}"
DB_USER="${NORMALIZED}_user"
DB_NAME="${NORMALIZED}_db"
PG_CONTAINER="pg-shared"

read -rp "Esto borrara la base de datos '${DB_NAME}' y el role '${DB_USER}'. Escribe el slug para confirmar: " CONFIRM
if [ "$CONFIRM" != "$CLIENT_SLUG" ]; then
  echo "Cancelado." >&2
  exit 1
fi

if [ -d "$DEST" ]; then
  echo "==> Parando contenedores del cliente"
  (cd "$DEST" && docker compose down) || echo "Aviso: 'docker compose down' fallo (¿ya estaba parado?)" >&2
else
  echo "Aviso: no existe ${DEST}, salto el 'docker compose down'." >&2
fi

echo "==> Borrando base de datos y role"
docker exec -i "$PG_CONTAINER" psql -U "$POSTGRES_SUPERUSER" -v ON_ERROR_STOP=1 <<-SQL
  DROP DATABASE IF EXISTS ${DB_NAME};
  DROP ROLE IF EXISTS ${DB_USER};
SQL

cat <<EOF

Baja de '${CLIENT_SLUG}' completada (contenedores parados + BBDD borrada).

Pendiente a mano:
  - Quitar la entrada de '${CLIENT_SLUG}' en clients.yaml.
  - Borrar la carpeta si ya no la necesitas: rm -rf ${DEST}
  - Quitar las labels/router de Traefik si quedara algo huerfano (no deberia,
    Traefik las descubre solo mientras el contenedor esta vivo).
EOF
