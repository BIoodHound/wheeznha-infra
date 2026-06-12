# CLAUDE.md — weeznha-family

Instructions for any agent operating this repo (including the deployment
agent on the Raspberry Pi).

## Deploying / pulling changes

When asked to pull changes or deploy, ALWAYS do it in this order:

```bash
git pull
./deploy.sh
```

`deploy.sh` runs pending data migrations BEFORE restarting the stack and is
idempotent — never replace it with a bare `docker compose up -d --build`.

The current migration (`migrations/cutover-shoppinglist.sh`) moves the old
standalone Shoppinglist database into the shared `weeznha_db`. It backs up
the legacy DB to `migrations/backups/` first, skips automatically once the
data is migrated, and **fails on purpose** if a legacy shoppinglist volume
exists but the legacy DB container isn't running — start that container and
re-run rather than working around the error.

## Hard rules

- NEVER run `docker compose down -v` or `docker volume rm` on anything
  containing `postgres` or `shoppinglist` — that is user data.
- Do not delete the legacy shoppinglist container/volume after migration;
  the user retires them manually once they have verified the new stack.
- `keys/` holds the RS256 JWT keypair. Never regenerate it casually:
  rotating keys logs every user out of every app.
- First-time setup (env vars, key generation) is documented in README.md.

## Architecture in one line

One backend stack here (postgres + auth-service + one Spring Boot service
per app behind nginx on the shared `weeznha-net` network); each app frontend
deploys separately from its own repo as a frontend + Cloudflare Tunnel stack.
