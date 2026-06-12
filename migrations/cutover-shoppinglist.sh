#!/bin/bash
# One-time Shoppinglist data migration: legacy standalone postgres
# (database "shoppinglist", public schema) -> family weeznha_db
# (auth + shoppinglist schemas).
#
# Safe to run on every deploy — it exits 0 without touching anything when:
#   * the new shoppinglist.users table already has rows (already migrated), or
#   * no trace of a legacy database exists on this host (fresh install).
#
# It REFUSES to continue (exit 1) if a legacy shoppinglist volume exists but
# the legacy DB container is not running — so a deploy can never silently
# come up empty while old data is still sitting on disk.
#
# Overridable env:
#   OLD_CONTAINER  legacy postgres container name (default: shoppinglist-db-prod)
#   OLD_DB         legacy database name           (default: shoppinglist)
#   OLD_USER       legacy postgres user           (default: postgres)
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

OLD_CONTAINER="${OLD_CONTAINER:-shoppinglist-db-prod}"
OLD_DB="${OLD_DB:-shoppinglist}"
OLD_USER="${OLD_USER:-postgres}"

log() { echo "[cutover] $*"; }

new_psql() {
    # psql against the family postgres as the admin role (env from container)
    docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" '"$1"
}

# ── 0. Already migrated? ─────────────────────────────────────────────────────
log "Starting family postgres (needed to check migration state)…"
docker compose up -d postgres
for i in $(seq 1 30); do
    docker compose exec -T postgres sh -c 'pg_isready -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' && break
    sleep 2
done

HAS_SCHEMA=$(new_psql "-tAc \"SELECT 1 FROM information_schema.tables WHERE table_schema='shoppinglist' AND table_name='users'\"" || true)
if [ "$HAS_SCHEMA" = "1" ]; then
    MIGRATED=$(new_psql "-tAc 'SELECT COUNT(*) FROM shoppinglist.users'" | tr -d '[:space:]')
    if [ "${MIGRATED:-0}" -gt 0 ]; then
        log "shoppinglist.users already has $MIGRATED rows — migration already done. Skipping."
        exit 0
    fi
fi

# ── 1. Is there anything to migrate on this host? ───────────────────────────
if ! docker ps --format '{{.Names}}' | grep -qx "$OLD_CONTAINER"; then
    if docker volume ls --format '{{.Name}}' | grep -qi shoppinglist; then
        log "ERROR: a legacy shoppinglist volume exists on this host but the"
        log "legacy DB container '$OLD_CONTAINER' is not running."
        log "Start it first (so data can be exported), e.g.:"
        log "  docker start $OLD_CONTAINER"
        log "or set OLD_CONTAINER=<name> if it is called something else."
        exit 1
    fi
    log "No legacy shoppinglist container or volume found — nothing to migrate."
    exit 0
fi

# ── 2. Full backup of the legacy DB (kept locally, gitignored) ───────────────
BACKUP_DIR="migrations/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/shoppinglist-legacy-$(date +%Y%m%d-%H%M%S).sql"
log "Backing up legacy DB to $BACKUP_FILE…"
docker exec "$OLD_CONTAINER" pg_dump -U "$OLD_USER" "$OLD_DB" > "$BACKUP_FILE"
log "Backup size: $(wc -c < "$BACKUP_FILE") bytes. Keep a copy off this host."

# ── 3. Export legacy tables as CSV (tolerating optional newer columns) ──────
old_psql() { docker exec "$OLD_CONTAINER" psql -U "$OLD_USER" -d "$OLD_DB" "$@"; }
has_col() {
    [ "$(old_psql -tAc "SELECT 1 FROM information_schema.columns WHERE table_name='$1' AND column_name='$2'")" = "1" ]
}

FRIEND_COL="NULL"; has_col users friend_code && FRIEND_COL="friend_code"
ROLE_COL="NULL";   has_col users role        && ROLE_COL="role"
DESC_COL="NULL";   has_col shopping_list_items description && DESC_COL="description"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
log "Exporting legacy tables…"
old_psql -c "\copy (SELECT id, username, password, name, qr_code, $ROLE_COL, $FRIEND_COL FROM users) TO STDOUT WITH (FORMAT csv)" > "$TMP_DIR/users.csv"
old_psql -c "\copy (SELECT id, name, owner_id FROM shopping_lists) TO STDOUT WITH (FORMAT csv)" > "$TMP_DIR/lists.csv"
old_psql -c "\copy (SELECT id, name, checked, image_url, $DESC_COL, shopping_list_id FROM shopping_list_items) TO STDOUT WITH (FORMAT csv)" > "$TMP_DIR/items.csv"
old_psql -c "\copy (SELECT shopping_list_id, user_id FROM shopping_list_members) TO STDOUT WITH (FORMAT csv)" > "$TMP_DIR/members.csv"

# ── 4. Bring up auth + shoppinglist services so Flyway creates the tables ───
log "Starting auth-service and shoppinglist-service (Flyway migrations)…"
docker compose up -d --build auth-service shoppinglist-service
log "Waiting for auth.users and shoppinglist.users tables…"
for i in $(seq 1 60); do
    A=$(new_psql "-tAc \"SELECT 1 FROM information_schema.tables WHERE table_schema='auth' AND table_name='users'\"" || true)
    S=$(new_psql "-tAc \"SELECT 1 FROM information_schema.tables WHERE table_schema='shoppinglist' AND table_name='users'\"" || true)
    [ "$A" = "1" ] && [ "$S" = "1" ] && break
    [ "$i" = "60" ] && { log "ERROR: Flyway tables never appeared."; exit 1; }
    sleep 5
done

# ── 5. Stage CSVs and run the cutover SQL ────────────────────────────────────
log "Loading staging tables…"
new_psql "-c \"
    DROP SCHEMA IF EXISTS legacy CASCADE;
    CREATE SCHEMA legacy;
    CREATE TABLE legacy.users (id UUID, username TEXT, password TEXT, name TEXT, qr_code TEXT, role TEXT, friend_code TEXT);
    CREATE TABLE legacy.shopping_lists (id UUID, name TEXT, owner_id UUID);
    CREATE TABLE legacy.shopping_list_items (id UUID, name TEXT, checked BOOLEAN, image_url TEXT, description TEXT, shopping_list_id UUID);
    CREATE TABLE legacy.shopping_list_members (shopping_list_id UUID, user_id UUID);
\""
PG_CONTAINER=$(docker compose ps -q postgres)
docker exec -i "$PG_CONTAINER" sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\copy legacy.users FROM STDIN WITH (FORMAT csv)"' < "$TMP_DIR/users.csv"
docker exec -i "$PG_CONTAINER" sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\copy legacy.shopping_lists FROM STDIN WITH (FORMAT csv)"' < "$TMP_DIR/lists.csv"
docker exec -i "$PG_CONTAINER" sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\copy legacy.shopping_list_items FROM STDIN WITH (FORMAT csv)"' < "$TMP_DIR/items.csv"
docker exec -i "$PG_CONTAINER" sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\copy legacy.shopping_list_members FROM STDIN WITH (FORMAT csv)"' < "$TMP_DIR/members.csv"

log "Running cutover SQL…"
docker exec -i "$PG_CONTAINER" sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < migrations/cutover-shoppinglist.sql

# ── 6. Verify, then drop staging ─────────────────────────────────────────────
log "Verification (legacy -> migrated):"
new_psql "-c \"
    SELECT 'users'   AS tbl, (SELECT COUNT(*) FROM legacy.users)                 AS legacy, (SELECT COUNT(*) FROM shoppinglist.users)                 AS migrated
    UNION ALL SELECT 'auth_users',   (SELECT COUNT(*) FROM legacy.users),                  (SELECT COUNT(*) FROM auth.users)
    UNION ALL SELECT 'lists',        (SELECT COUNT(*) FROM legacy.shopping_lists),         (SELECT COUNT(*) FROM shoppinglist.shopping_lists)
    UNION ALL SELECT 'items',        (SELECT COUNT(*) FROM legacy.shopping_list_items),    (SELECT COUNT(*) FROM shoppinglist.shopping_list_items)
    UNION ALL SELECT 'members',      (SELECT COUNT(*) FROM legacy.shopping_list_members),  (SELECT COUNT(*) FROM shoppinglist.shopping_list_members);
\""
new_psql "-c 'DROP SCHEMA legacy CASCADE'"

log "Done. The legacy container/volume were NOT touched — keep them until"
log "you have verified logins and lists, then retire them manually."
