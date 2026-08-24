# platform-infra

Servicios de plataforma, compartidos por todos los ecommerce del servidor.
Se despliega **una sola vez** en el OVHcloud y queda siempre corriendo:

- **Traefik** — proxy inverso: enruta cada dominio al contenedor `web` del
  cliente correcto y gestiona los certificados TLS (Let's Encrypt) automáticamente.
- **pgAdmin** — administración de todas las bases de datos, sin exponerse a Internet.
- **backups/** — punto de partida para los volcados de Postgres (de momento manual).
- Monitorización: pendiente, ver "Próximos pasos" al final.

## 1. Primer despliegue en el servidor

```bash
# Una sola vez por servidor: la red que conecta esta plataforma
# con cada stack de cliente.
docker network create edge

cp ..env.example .env
# edita .env con tus valores reales

mkdir -p letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json   # Traefik rechaza el archivo si los permisos son más abiertos

docker compose up -d
```

## 2. Cómo se conecta cada repo de cliente

Cada `cliente-x-shop` (clonado del skeleton) debe:

1. Unir sus servicios `web` y `db` a la red externa `edge`:

   ```yaml
   services:
     web:
       # ...
       networks:
         - edge
       labels:
         - traefik.enable=true
         - traefik.http.routers.cliente-x.rule=Host(`clientex.com`)
         - traefik.http.routers.cliente-x.entrypoints=websecure
         - traefik.http.routers.cliente-x.tls.certresolver=le
         - traefik.http.services.cliente-x.loadbalancer.server.port=3000

     db:
       # ...
       networks:
         - edge
       labels:
         - platform.backup=true   # opcional: lo incluye en backup-postgres.sh

   networks:
     edge:
       external: true
   ```

2. **No publicar puertos al host** (`ports:`) en `web` ni en `db` — Traefik
   es el único punto de entrada del servidor, en el 80/443.

Con eso, Traefik detecta el contenedor automáticamente (vía el socket de
Docker) en cuanto el stack del cliente arranca — no hay que tocar nada en
`platform-infra` para dar de alta un cliente nuevo.

## 3. Acceder a pgAdmin

pgAdmin no está expuesto a Internet — solo escucha en `127.0.0.1:5050` del
propio servidor. Se accede por túnel SSH:

```bash
ssh -L 5050:127.0.0.1:5050 usuario@tu-servidor-ovh
```

Y abres `http://localhost:5050` en tu navegador. Dentro, añade una conexión
por cada base de datos de cliente: host = nombre del contenedor `db` de ese
cliente (p. ej. `cliente-x-shop-db-1`, el nombre que le da Docker Compose),
puerto 5432, usuario/contraseña de su `.env`.

Si en vez de túnel SSH prefieres entrar por navegador con un dominio propio,
se puede añadir a pgAdmin las mismas labels de Traefik que usa `web`, más un
middleware de `basicauth`. No lo he montado por defecto porque el túnel SSH
es más simple y no añade superficie de ataque.

## Próximos pasos

- **Backups**: `backups/backup-postgres.sh` ya vuelca cualquier `db` marcada
  con `platform.backup=true`. Falta programarlo (cron en el host) y subir los
  dumps a almacenamiento externo (OVH Object Storage, por ejemplo).
- **Monitorización**: aún sin decidir. Opciones típicas para este tamaño:
  Uptime Kuma (uptime/alertas, muy ligero) o Grafana + Prometheus (más
  completo, más overhead). Se añadiría como un servicio más en este mismo
  `docker-compose.yml`, en la red `edge`.
