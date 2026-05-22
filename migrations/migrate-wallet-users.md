# Wallet MongoDB → PostgreSQL Migration

## Overview

Weeznha Wallet previously used MongoDB. This documents how to migrate existing user data
into the PostgreSQL `wallet` schema.

## Step 1 — Export from MongoDB

```bash
mongoexport --uri="mongodb://localhost:27017/weeznha_wallet" \
  --collection=users --out=wallet_users.json

mongoexport --uri="mongodb://localhost:27017/weeznha_wallet" \
  --collection=balances --out=wallet_balances.json
```

## Step 2 — Match users to auth.users

Wallet users stored their own passwords; auth-service now owns credentials.
You MUST register each wallet user in auth-service first (or run the
shoppinglist migration which already imports users) so that auth.users.id
exists before inserting into wallet.users (FK constraint).

If users are already in auth.users (from the shoppinglist migration):

```sql
-- Insert wallet-specific profile for users already in auth.users.
-- Run after Flyway has created the wallet schema tables.
INSERT INTO wallet.users (id, username, role, sync_code)
SELECT au.id, au.username, 'USER', NULL
FROM   auth.users au
ON CONFLICT (id) DO NOTHING;

-- Create a balance row for every user that doesn't have one yet.
INSERT INTO wallet.balances (user_id, gold, silver, copper)
SELECT u.id, 0, 0, 0
FROM   wallet.users u
WHERE  NOT EXISTS (
    SELECT 1 FROM wallet.balances b WHERE b.user_id = u.id
);
```

## Step 3 — Import balances from MongoDB export

Parse `wallet_balances.json` and cross-reference with `wallet_users` by MongoDB
`_id` → `userId` (DBRef). Since MongoDB IDs are strings and PostgreSQL uses UUIDs,
the mapping must be done via username.

Example using psql's `\copy` after converting the export to CSV is recommended.
Adjust gold/silver/copper fields from the JSON export directly.

## Step 4 — Verify

```sql
SELECT COUNT(*) FROM wallet.users;
SELECT COUNT(*) FROM wallet.balances;
-- Should match your MongoDB counts.
```
