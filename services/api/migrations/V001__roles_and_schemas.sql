-- THRØ V001 — roles and schemas.
--
-- The separation below is load-bearing, not hygiene. A table's OWNER can TRUNCATE it whatever has
-- been revoked, so if the application role owned the evidence tables the append-only guarantee would
-- be decorative. Migrations therefore run as an owner role the application never holds.

CREATE ROLE thro_owner NOLOGIN;                 -- owns every object; used only by migrations
CREATE ROLE app_match  NOLOGIN;                 -- the match module
CREATE ROLE app_trust  NOLOGIN;                 -- attestations, disputes, quarantine
CREATE ROLE app_rating NOLOGIN;                 -- rating projections; downstream only
CREATE ROLE app_read   NOLOGIN;                 -- read models

-- The deploy user must be able to act as the owner. A superuser always can; a managed provider's
-- role (Neon, RDS) is not one, and PostgreSQL 16 no longer gives a role's creator the SET and
-- INHERIT options on the role it created. So the creator grants itself membership here, using the
-- ADMIN OPTION creation does confer, and every later `SET ROLE thro_owner` and
-- `AUTHORIZATION thro_owner` works on any PostgreSQL 16 the deploy user can create roles on.
DO $$
BEGIN
  IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    EXECUTE format('GRANT thro_owner TO %I WITH SET TRUE, INHERIT TRUE', current_user);
  END IF;
END $$;

CREATE SCHEMA evidence AUTHORIZATION thro_owner;   -- append-only competitive truth
CREATE SCHEMA trust     AUTHORIZATION thro_owner;
CREATE SCHEMA rating    AUTHORIZATION thro_owner;
CREATE SCHEMA read      AUTHORIZATION thro_owner;  -- projections, freely rebuildable

GRANT USAGE ON SCHEMA evidence, trust, rating, read
  TO app_match, app_trust, app_rating, app_read;

-- Default privileges are what make the guarantee survive the NEXT migration. Revoking on existing
-- tables alone leaves every future table mutable, which is the defect this replaces.
ALTER DEFAULT PRIVILEGES FOR ROLE thro_owner IN SCHEMA evidence
  GRANT SELECT, INSERT ON TABLES TO app_match, app_trust, app_rating, app_read;
ALTER DEFAULT PRIVILEGES FOR ROLE thro_owner IN SCHEMA evidence
  REVOKE UPDATE, DELETE, TRUNCATE ON TABLES FROM app_match, app_trust, app_rating, app_read;
