#!/bin/bash
# Deploy the weeznha-family backend stack.
#
# ALWAYS use this instead of a bare `docker compose up` after pulling:
# it runs pending data migrations FIRST, then (re)starts the stack.
# All migration steps are idempotent — running this on every deploy is safe.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Step 1/2: data migrations"
bash migrations/cutover-shoppinglist.sh

echo "==> Step 2/2: (re)starting the family stack"
docker compose up -d --build

echo "==> Deploy complete."
echo "    Frontend stacks (Shoppinglist/, 'weeznha wallet/', miniature-palette/)"
echo "    are deployed separately from their own repos."
