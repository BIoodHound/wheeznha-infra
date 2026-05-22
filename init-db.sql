-- Creates all service schemas on first boot.
-- Each service manages its own tables via Flyway migrations.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS shoppinglist;
CREATE SCHEMA IF NOT EXISTS wallet;
CREATE SCHEMA IF NOT EXISTS palette;
