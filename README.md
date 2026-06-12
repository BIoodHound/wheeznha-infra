# weeznha-family

Infrastructure for the Weeznha family of apps. One shared backend stack
(Postgres + auth-service + one Spring Boot service per app behind an nginx
gateway), with each app's frontend deployed from its own repo as a separate
frontend + Cloudflare Tunnel stack.

```
weeznha.com (Cloudflare Worker) ──▶ /auth/* ──▶ gateway nginx :80 ─▶ auth-service :8081
list.weeznha.com    (tunnel) ─▶ shoppinglist frontend ─▶ shoppinglist-service :8080 ─┐
wallet.weeznha.com  (tunnel) ─▶ wallet frontend       ─▶ wallet-service :8080       ─┼─▶ postgres
palette.weeznha.com (tunnel) ─▶ palette frontend      ─▶ palette-service :8080      ─┘
                 (frontends join the shared `weeznha-net` docker network)
```

## Setup

1. **Environment** — copy `.env.example` to `.env` and fill in the database
   passwords (admin + one per service).

2. **JWT keypair (RS256)** — auth-service signs tokens with the private key;
   app services verify with the public key:

   ```bash
   mkdir -p keys
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out keys/jwt-private.pem
   openssl rsa -in keys/jwt-private.pem -pubout -out keys/jwt-public.pem
   ```

   `keys/` is gitignored. Rotating the keypair logs everyone out.

3. **Start the backend stack** (creates the shared `weeznha-net` network):

   ```bash
   ./deploy.sh
   ```

   `deploy.sh` runs pending data migrations first, then
   `docker compose up -d --build`. Use it for every deploy — the migration
   steps are idempotent. The Shoppinglist cutover
   (`migrations/cutover-shoppinglist.sh`) backs up the legacy standalone DB
   to `migrations/backups/`, imports users (passwords preserved), lists,
   items and members into `weeznha_db`, and refuses to run if legacy data
   exists but its DB container is down — so a deploy can never silently
   come up empty.

4. **Start each frontend stack** from its own repo (`Shoppinglist/`,
   `weeznha wallet/`, `miniature-palette/`). Each needs a
   `CLOUDFLARE_TUNNEL_TOKEN` in its `.env`.

## Database layout

One Postgres database (`weeznha_db`), one schema per service: `auth`,
`shoppinglist`, `wallet`, `palette`. Each service connects with its own role
(`auth_service`, `shoppinglist_service`, …) that owns only its schema —
services cannot read or write each other's data. Tables are created by each
service's Flyway migrations; `init-db.sh` only creates schemas and roles.

**Existing volumes:** `init-db.sh` only runs automatically on a fresh data
volume. To upgrade a database created before per-service roles existed:

```bash
docker compose exec postgres bash /docker-entrypoint-initdb.d/00-init.sh
```

## Auth flow

1. User logs in at weeznha.com (`/auth/login`, proxied by the Cloudflare
   Worker to the gateway).
2. auth-service stores a 60-second one-time code and redirects to the app's
   `/auth/callback` with `code` + `state`.
3. The app backend exchanges the code at `http://auth-service:8081/auth/token`
   (internal only — the gateway returns 403 for it) and hands the SPA an
   RS256 access token.
4. App services verify tokens locally with `keys/jwt-public.pem`; on first
   sight of a user they create a local profile row keyed by the user's UUID,
   and keep its username in sync with the token claims.

## Notes

- Switching from the old HS256 shared secret to RS256 invalidates all
  previously issued tokens — users just log in again.
- The gateway only exposes port 80; TLS termination is Cloudflare's job.
- Public CORS preflight responses only echo origins on the whitelist in
  `nginx/nginx.conf` — add new app domains there *and* in `.env`.
