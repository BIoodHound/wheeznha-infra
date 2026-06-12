#!/bin/bash
# Runs automatically on FIRST postgres boot (empty data volume) via
# /docker-entrypoint-initdb.d. For an existing volume, run it manually:
#   docker compose exec postgres bash /docker-entrypoint-initdb.d/00-init.sh
#
# Creates one schema per service and one login role per service that owns
# only its own schema — services cannot read or write each other's data.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	CREATE SCHEMA IF NOT EXISTS auth;
	CREATE SCHEMA IF NOT EXISTS shoppinglist;
	CREATE SCHEMA IF NOT EXISTS wallet;
	CREATE SCHEMA IF NOT EXISTS palette;

	DO \$\$
	BEGIN
	    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'auth_service') THEN
	        CREATE ROLE auth_service LOGIN PASSWORD '${AUTH_DB_PASSWORD}';
	    END IF;
	    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'shoppinglist_service') THEN
	        CREATE ROLE shoppinglist_service LOGIN PASSWORD '${SHOPPINGLIST_DB_PASSWORD}';
	    END IF;
	    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'wallet_service') THEN
	        CREATE ROLE wallet_service LOGIN PASSWORD '${WALLET_DB_PASSWORD}';
	    END IF;
	    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'palette_service') THEN
	        CREATE ROLE palette_service LOGIN PASSWORD '${PALETTE_DB_PASSWORD}';
	    END IF;
	END
	\$\$;

	ALTER SCHEMA auth         OWNER TO auth_service;
	ALTER SCHEMA shoppinglist OWNER TO shoppinglist_service;
	ALTER SCHEMA wallet       OWNER TO wallet_service;
	ALTER SCHEMA palette      OWNER TO palette_service;

	-- Each role only ever sees its own schema.
	ALTER ROLE auth_service         IN DATABASE $POSTGRES_DB SET search_path = auth;
	ALTER ROLE shoppinglist_service IN DATABASE $POSTGRES_DB SET search_path = shoppinglist;
	ALTER ROLE wallet_service       IN DATABASE $POSTGRES_DB SET search_path = wallet;
	ALTER ROLE palette_service      IN DATABASE $POSTGRES_DB SET search_path = palette;

	-- For volumes that already contain tables created by the admin role:
	-- hand existing objects in each schema to the owning service role.
	GRANT ALL ON ALL TABLES    IN SCHEMA auth         TO auth_service;
	GRANT ALL ON ALL SEQUENCES IN SCHEMA auth         TO auth_service;
	GRANT ALL ON ALL TABLES    IN SCHEMA shoppinglist TO shoppinglist_service;
	GRANT ALL ON ALL SEQUENCES IN SCHEMA shoppinglist TO shoppinglist_service;
	GRANT ALL ON ALL TABLES    IN SCHEMA wallet       TO wallet_service;
	GRANT ALL ON ALL SEQUENCES IN SCHEMA wallet       TO wallet_service;
	GRANT ALL ON ALL TABLES    IN SCHEMA palette      TO palette_service;
	GRANT ALL ON ALL SEQUENCES IN SCHEMA palette      TO palette_service;
EOSQL

echo "weeznha schemas and service roles ready."
