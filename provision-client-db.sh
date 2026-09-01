#!/usr/bin/env bash
#
# provision-client-db.sh — crea el ROLE + DATABASE de un cliente nuevo
# en el Postgres compartido (contenedor "pg-shared"), o los deja tal
# cual si ya existen (idempotente en ese sentido).
#
# Uso:
#   export $(grep -v '^#' .env | xargs)   # .env de platform-infra
#   ./scripts/provision-client-db.sh cliente-x
#
# Salida por stdout en formato KEY=VALUE, pensada para capturarse con:
#   eval "$(./scripts/provision-client-db.sh cliente-x)"
#
# Notas:
# - Sigue el mismo patrón de acceso que backup-postgres.sh: docker exec
#   contra el contenedor, sin pasar contraseña por la CLI (el postgres
#   oficial confía en las conexiones locales vía socket).
# - Si el role YA existe, NO se le toca la contraseña (Postgres no
#   permite leerla de vuelta; sobrescribirla a ciegas rompería el
#   cliente existente). En ese caso no se imprime DB_PASSWORD.
#
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Uso: $0 <client-slug>" >&2
  exit 1
fi

CLIENT_SLUG="$1"
: "${POSTGRES_SUPERUSER:?Falta POSTGRES_SUPERUSER en el entorno (exporta el .env de platform-infra)}"

PG_CONTAINER="pg-shared"

# Postgres no admite guiones en identificadores sin comillas -> los
# normalizamos a guion bajo para el nombre de role/db.
NORMALIZED="${CLIENT_SLUG//-/_}"
DB_USER="${NORMALIZED}_user"
DB_NAME="${NORMALIZED}_db"

echo "Provisionando BBDD para '${CLIENT_SLUG}' (role=${DB_USER}, db=${DB_NAME})..." >&2

ROLE_EXISTS="$(docker exec -i "$PG_CONTAINER" psql -U "$POSTGRES_SUPERUSER" -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}'")"

if [ "$ROLE_EXISTS" = "1" ]; then
  echo "Aviso: el role ${DB_USER} ya existe. No se ha tocado su contraseña." >&2
  echo "Si es un alta nueva, usa un CLIENT_SLUG distinto. Si es un cliente" >&2
  echo "existente, recupera las credenciales de su propio .env." >&2
else
  DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)"
  docker exec -i "$PG_CONTAINER" psql -U "$POSTGRES_SUPERUSER" -v ON_ERROR_STOP=1 <<-SQL
    CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
SQL
  echo "DB_PASSWORD=${DB_PASSWORD}"
fi

# La database sí es seguro crearla condicionalmente sin tocar nada existente.
docker exec -i "$PG_CONTAINER" psql -U "$POSTGRES_SUPERUSER" -v ON_ERROR_STOP=1 <<-SQL
  SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
SQL

echo "Listo." >&2

echo "DB_USER=${DB_USER}"
echo "DB_NAME=${DB_NAME}"
