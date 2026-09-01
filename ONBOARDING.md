# Alta de un cliente nuevo (Fase 0)

Esta guía asume que `platform-infra` ya está desplegado una vez en el
servidor OVH (Traefik + Postgres compartido + pgAdmin corriendo, ver
el README principal). Documenta cómo dar de alta un cliente nuevo de
forma repetible, y cómo traer actualizaciones del skeleton a un
cliente que ya lleva tiempo personalizado.

## 0. Requisitos previos

- Estar en el servidor (o con acceso SSH a él).
- Tener el `.env` de `platform-infra` exportado en la sesión:
  ```bash
  cd platform-infra
  export $(grep -v '^#' .env | xargs)
  ```
- Los scripts en `scripts/` con permiso de ejecución:
  ```bash
  chmod +x scripts/*.sh
  ```

## 1. Alta automática

```bash
./scripts/new-client.sh cliente-x clientex.com git@github.com:tuorg/ecommerce-skeleton.git
```

Esto:
1. Clona el skeleton en `/srv/clients/cliente-x`.
2. Renombra el remote `origin` → `skeleton` (para poder traer
   actualizaciones más adelante sin confundirlo con el repo propio
   del cliente).
3. Crea el `ROLE` + `DATABASE` del cliente en el Postgres compartido
   (sin tocar nada si ya existían — ver `provision-client-db.sh`).
4. Genera el `.env` del cliente con credenciales de BBDD y
   `NEXTAUTH_SECRET` generados al azar.
5. Añade una entrada en `clients.yaml`.

Si necesitas hacerlo en dos pasos (por ejemplo, provisionar la BBDD de
un cliente sin clonar nada, o al revés), usa `provision-client-db.sh`
suelto — está pensado para poder reutilizarse solo.

## 2. Personalización obligatoria antes del primer commit

Dentro de `/srv/clients/cliente-x`:

1. **`src/config/site.config.ts`** — nombre de marca y paleta de colores.
2. **`src/config/landing.config.ts`** — contenido de la home (secciones,
   textos, productos destacados) y `siteNavLinks`/`footerContent`.
3. **`src/config/content.config.ts`** — páginas legales, FAQ y contacto
   (hoy tienen texto placeholder marcado explícitamente como tal).
4. Imágenes: sustituye las URLs de `placehold.co` por las reales
   (súbelas a `public/images/` o a tu Object Storage — ver nota en
   Fase 1 sobre imágenes).
5. **`next.config.mjs`** — si vas a servir imágenes desde un dominio
   propio (CDN/Object Storage), añádelo a `remotePatterns`.

No hace falta tocar ningún componente de `components/` — ese es
justo el punto del patrón config-driven que ya tienes montado.

## 3. Publicar el repo del cliente y desplegar

```bash
cd /srv/clients/cliente-x

# Crea antes el repo vacío en tu git host (GitHub/GitLab) para este cliente
git remote add origin git@github.com:tuorg/cliente-x-shop.git
git add -A
git commit -m "Personalizacion inicial: marca, contenido, imagenes"
git push -u origin main

# DNS: apunta clientex.com (A record) a la IP de este servidor, y espera propagación

docker compose up -d --build
```

El `entrypoint.sh` de la imagen aplica `prisma migrate deploy`
automáticamente antes de arrancar `server.js`, así que la BBDD recién
creada queda con el esquema al día en el primer arranque — no hace
falta ningún paso manual de migración.

Verifica en los logs de Traefik (`docker logs -f <container_traefik>`)
que emite el certificado Let's Encrypt para `clientex.com` sin errores
de ACME challenge (el DNS tiene que estar ya propagado para esto).

## 4. Sembrar datos de ejemplo (opcional)

`prisma:seed` usa `tsx`, que no está en la imagen final de producción
(la imagen `runner` del `Dockerfile` es deliberadamente mínima). Para
sembrar un cliente en producción, la forma más simple es ejecutar el
seed puntualmente contra su `DATABASE_URL` desde tu máquina o desde el
propio servidor con Node/tsx instalados fuera de Docker:

```bash
cd /srv/clients/cliente-x
DATABASE_URL="postgresql://<user>:<pass>@localhost:5432/<db>" npx tsx prisma/seed.ts
```

(Ajusta el host si te conectas desde fuera del servidor — necesitarás
exponer temporalmente el puerto de Postgres o hacerlo por túnel SSH,
igual que con pgAdmin.)

## 5. Traer actualizaciones del skeleton a un cliente ya personalizado

Como el remote `skeleton` queda apuntando al repo base:

```bash
cd /srv/clients/cliente-x
git fetch skeleton
git merge skeleton/main
```

Para que esto no genere conflictos constantes, la regla de oro es:
**los ficheros de `config/` son solo datos, no lógica**. Si un
cliente necesita lógica distinta de verdad (no solo distinto
contenido), es una señal de que esa pieza debería ser una prop/config
nueva en el componente compartido, no un fork silencioso del
componente. Así casi todos los merges del skeleton entran limpios,
porque tocan `components/`, `lib/`, `types/` — no `config/`.

Si un merge sí trae conflicto en algún fichero de config (poco
frecuente, pero pasa si el skeleton añade un campo nuevo a un tipo
que el cliente ya había editado), resuélvelo a mano conservando el
contenido del cliente y adoptando la nueva forma del tipo.

Tras el merge, si hay migraciones de Prisma nuevas, se aplican solas
en el siguiente `docker compose up -d --build` (vía `entrypoint.sh`).

## 6. Baja de un cliente

```bash
export $(grep -v '^#' .env | xargs)   # .env de platform-infra
./scripts/remove-client.sh cliente-x
```

Para y borra contenedores + BBDD/role, con confirmación explícita
(hay que teclear el slug para confirmar). No borra la carpeta del
repo ni la entrada en `clients.yaml` — eso se hace a mano una vez
confirmado que todo ha ido bien.

## 7. Notas de seguridad

- Cada `.env` de cliente tiene permisos `600` y está en `.gitignore`
  — nunca debería acabar en el repo. Si en algún momento migras a
  gestionar esto con un secret manager (Vault, OVH Secret Manager,
  variables de entorno de CI), este es el punto natural para
  sustituir la generación de `.env` por una llamada a ese sistema.
- El role de cada cliente es dueño (`OWNER`) solo de su propia
  database — no tiene privilegios de superusuario ni ve las bases de
  datos de otros clientes.
- `clients.yaml` no contiene secretos (solo slugs, dominios y rutas),
  así que sí puedes versionarlo si quieres llevar `platform-infra`
  en git.
