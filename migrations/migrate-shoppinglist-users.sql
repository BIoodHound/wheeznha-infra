-- Migrates existing Shoppinglist users to the shared auth.users table.
-- Run ONCE after:
--   1. The shared weeznha_db is up and auth schema is initialized
--   2. Shoppinglist data has been imported into the shoppinglist schema
--
-- UUIDs and BCrypt hashes are preserved — no password resets needed.
-- Users will need to log in once after the cutover (old JWTs are invalidated).

INSERT INTO auth.users (id, username, email, password, name, role, created_at, updated_at)
SELECT
    id,
    username,
    NULL                        AS email,
    password,
    name,
    COALESCE(role, 'USER')      AS role,
    NOW()                       AS created_at,
    NOW()                       AS updated_at
FROM shoppinglist.users
ON CONFLICT (id) DO NOTHING;
