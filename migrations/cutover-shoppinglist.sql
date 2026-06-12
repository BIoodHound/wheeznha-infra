-- Shoppinglist cutover: legacy standalone DB -> weeznha_db schemas.
-- Expects staging tables in the "legacy" schema (created and filled by
-- cutover-shoppinglist.sh). Idempotent: re-running inserts nothing new.

BEGIN;

-- 1. Credentials move to auth-service. UUIDs and BCrypt hashes are
--    preserved, so everyone keeps their username and password.
INSERT INTO auth.users (id, username, email, password, name, role, created_at, updated_at)
SELECT
    id,
    username,
    NULL                   AS email,
    password,
    name,
    COALESCE(role, 'USER') AS role,
    NOW(),
    NOW()
FROM legacy.users
ON CONFLICT (id) DO NOTHING;

-- 2. Shoppinglist-specific profile (no credentials). Friend codes are kept
--    if the legacy DB had them, otherwise generated.
INSERT INTO shoppinglist.users (id, username, name, qr_code, friend_code)
SELECT
    id,
    username,
    name,
    qr_code,
    COALESCE(friend_code, UPPER(SUBSTR(MD5(id::TEXT || RANDOM()::TEXT), 1, 8)))
FROM legacy.users
ON CONFLICT (id) DO NOTHING;

-- 3. Lists, items, memberships.
INSERT INTO shoppinglist.shopping_lists (id, name, owner_id)
SELECT id, name, owner_id
FROM legacy.shopping_lists
ON CONFLICT (id) DO NOTHING;

INSERT INTO shoppinglist.shopping_list_items (id, name, checked, image_url, description, shopping_list_id)
SELECT id, name, COALESCE(checked, FALSE), image_url, description, shopping_list_id
FROM legacy.shopping_list_items
ON CONFLICT (id) DO NOTHING;

INSERT INTO shoppinglist.shopping_list_members (shopping_list_id, user_id)
SELECT shopping_list_id, user_id
FROM legacy.shopping_list_members
ON CONFLICT DO NOTHING;

COMMIT;
