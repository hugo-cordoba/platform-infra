#!/usr/bin/env bash
#
# new-client.sh — da de alta un cliente nuevo de principio a fin:
#   1. clona el skeleton
#   2. provisiona su BBDD en el Postgres compartido
#   3. genera su .env
#   4. lo registra en clients.yaml
#
# Uso (ejecutar DESDE platform-infra/, con su .env ya exportado):
#   export $(grep -v '^#' .env | xargs)
#   ./scripts/new-client.sh cliente-x clientex.com git@github.com:tuorg/ecommerce-skeleton.git
#
# Argumento opcional 4: carpeta base donde viven los clientes
# (por defecto /srv/clients).
#
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Uso: $0 <client-slug> <client-domain> <skeleton-git-url> [clients-dir]" >&2
  exit 1
fi

CLIENT_SLUG="$1"
CLIENT_DOMAIN="$2"
SKELETON_URL="$3"
CLIENTS_DIR="${4:-/srv/clients}"
DEST="${CLIENTS_DIR}/${CLIENT_SLUG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$DEST" ]; then
  echo "Error: ${DEST} ya existe. Elige otro slug o borra la carpeta antes de reintentar." >&2
  exit 1
fi

echo "==> 1/4 Clonando skeleton en ${DEST}"
git clone "$SKELETON_URL" "$DEST"
cd "$DEST"
# Renombramos origin -> skeleton. Asi queda claro que ese remote es
# "de donde vienen las actualizaciones del skeleton", no el repo
# propio del cliente. El remote "origin" (su propio repo) se añade a
# mano en el paso 2 de ONBOARDING.md, cuando exista el repo remoto.
git remote rename origin skeleton

echo "==> 2/4 Provisionando base de datos"
PROVISION_OUTPUT="$("$SCRIPT_DIR"/provision-client-db.sh "$CLIENT_SLUG")"
eval "$PROVISION_OUTPUT"
# A partir de aqui: DB_USER, DB_NAME siempre; DB_PASSWORD solo si el
# role se ha creado ahora (ver provision-client-db.sh).

if [ -z "${DB_PASSWORD:-}" ]; then
  echo "Error: no se ha generado DB_PASSWORD (el role ya existia de antes)." >&2
  echo "Revisa si '${CLIENT_SLUG}' ya estaba dado de alta, o borra el role" >&2
  echo "manualmente si es un resto de un intento anterior fallido." >&2
  exit 1
fi

echo "==> 3/4 Generando .env del cliente"
cat > .env <<EOF
CLIENT_SLUG=${CLIENT_SLUG}
CLIENT_DOMAIN=${CLIENT_DOMAIN}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@pg-shared:5432/${DB_NAME}
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NEXTAUTH_URL=https://${CLIENT_DOMAIN}
EOF
chmod 600 .env
# Ya esta cubierto por el .gitignore del skeleton (.env), pero por si acaso.
echo ".env" >> .gitignore 2>/dev/null || true

echo "==> 4/4 Registrando en clients.yaml"
REGISTRY="${SCRIPT_DIR}/../clients.yaml"
touch "$REGISTRY"
cat >> "$REGISTRY" <<EOF
- slug: ${CLIENT_SLUG}
  domain: ${CLIENT_DOMAIN}
  db_name: ${DB_NAME}
  path: ${DEST}
  created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  status: provisioned
EOF

cat <<EOF

Cliente '${CLIENT_SLUG}' listo en ${DEST}.

Siguientes pasos manuales (ver ONBOARDING.md para el detalle):
  1. Personaliza site.config.ts, landing.config.ts y content.config.ts.
  2. Crea el repo remoto vacio para este cliente en tu git host, luego:
       cd ${DEST}
       git remote add origin <url-del-repo-del-cliente>
       git add -A && git commit -m "Personalizacion inicial" && git push -u origin main
  3. Apunta el DNS de ${CLIENT_DOMAIN} a la IP de este servidor.
  4. cd ${DEST} && docker compose up -d --build
     (el entrypoint aplica las migraciones de Prisma automaticamente)
  5. Revisa los logs de Traefik para confirmar que emite el certificado TLS.
EOF
