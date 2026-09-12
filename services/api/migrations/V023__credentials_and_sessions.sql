-- THRØ V023 — credentials and sessions. PD-030: Sign in with Apple and Google first, passkeys as
-- the fallback; the session is THRØ's own.
--
-- A provider proves who is holding the phone. What THRØ keeps is:
--
--   credential      one (kind, subject) bound to one live account — an Apple or Google subject, or
--                   a passkey's credential id and public key. Revoked, never deleted; one live
--                   account per subject, so a subject cannot be bound twice.
--   session_family  one sign-in on one device. Revoked as a whole — by logout, or by the reuse of
--                   a refresh token, which is how a stolen refresh token gives itself away (ADR-008:
--                   rotation with reuse detection).
--   refresh_token   long-lived, single-use: using one marks it used and issues its successor.
--   access_token    short-lived, opaque, looked up per request. Identity in the token, never
--                   permissions: the token names an account; the account's live claim names the
--                   player; every decision is made per request against relationships.
--
-- No token secret is stored. Only its SHA-256 is, so a dump of these tables yields nothing a
-- caller can present. Nothing here is deletable by an application role; expiry is a timestamp,
-- and history is what an incident review reads.

SET ROLE thro_owner;

CREATE TABLE identity.credential (
  credential_id  uuid        PRIMARY KEY,
  account_id     uuid        NOT NULL REFERENCES identity.account(account_id),
  kind           text        NOT NULL CHECK (kind IN ('apple','google','passkey')),
  subject        text        NOT NULL,
  public_key     bytea,
  sign_count     bigint,
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_used_at   timestamptz,
  revoked_at     timestamptz,
  revoked_by     uuid,
  revoked_reason text,
  CONSTRAINT credential_revocation_is_complete CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL)),
  CONSTRAINT passkey_has_a_key CHECK (kind <> 'passkey' OR public_key IS NOT NULL),
  CONSTRAINT provider_credential_has_no_key CHECK (kind = 'passkey' OR (public_key IS NULL AND sign_count IS NULL))
);
CREATE UNIQUE INDEX credential_one_live_account_per_subject ON identity.credential (kind, subject) WHERE revoked_at IS NULL;
CREATE INDEX credential_by_account ON identity.credential (account_id) WHERE revoked_at IS NULL;

CREATE TABLE identity.session_family (
  family_id      uuid        PRIMARY KEY,
  account_id     uuid        NOT NULL REFERENCES identity.account(account_id),
  credential_id  uuid        NOT NULL REFERENCES identity.credential(credential_id),
  device_id      uuid        NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at     timestamptz,
  revoked_reason text,
  CONSTRAINT family_revocation_is_complete CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
CREATE INDEX session_family_by_account ON identity.session_family (account_id) WHERE revoked_at IS NULL;

CREATE TABLE identity.refresh_token (
  token_hash     bytea       PRIMARY KEY,
  family_id      uuid        NOT NULL REFERENCES identity.session_family(family_id),
  issued_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at     timestamptz NOT NULL,
  used_at        timestamptz,
  superseded_by  bytea       REFERENCES identity.refresh_token(token_hash),
  CONSTRAINT refresh_token_hash_is_sha256 CHECK (octet_length(token_hash) = 32),
  CONSTRAINT refresh_token_used_once CHECK ((used_at IS NULL) = (superseded_by IS NULL))
);
CREATE INDEX refresh_token_by_family ON identity.refresh_token (family_id);

CREATE TABLE identity.access_token (
  token_hash     bytea       PRIMARY KEY,
  family_id      uuid        NOT NULL REFERENCES identity.session_family(family_id),
  account_id     uuid        NOT NULL REFERENCES identity.account(account_id),
  issued_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at     timestamptz NOT NULL,
  CONSTRAINT access_token_hash_is_sha256 CHECK (octet_length(token_hash) = 32)
);
CREATE INDEX access_token_by_family ON identity.access_token (family_id);

-- Revocations are final; a used refresh token stays used; an access token never changes.
CREATE FUNCTION identity.revocation_is_final() RETURNS trigger AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL AND (NEW.revoked_at IS DISTINCT FROM OLD.revoked_at OR NEW.revoked_reason IS DISTINCT FROM OLD.revoked_reason) THEN
    RAISE EXCEPTION 'a revocation cannot be undone or reworded'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'revocation_is_final';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER credential_revocation_is_final BEFORE UPDATE ON identity.credential
  FOR EACH ROW EXECUTE FUNCTION identity.revocation_is_final();
CREATE TRIGGER session_family_revocation_is_final BEFORE UPDATE ON identity.session_family
  FOR EACH ROW EXECUTE FUNCTION identity.revocation_is_final();

CREATE FUNCTION identity.refresh_token_is_used_once() RETURNS trigger AS $$
BEGIN
  IF OLD.used_at IS NOT NULL THEN
    RAISE EXCEPTION 'a used refresh token is history'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'refresh_token_is_used_once';
  END IF;
  IF NEW.token_hash <> OLD.token_hash OR NEW.family_id <> OLD.family_id OR NEW.issued_at <> OLD.issued_at OR NEW.expires_at <> OLD.expires_at THEN
    RAISE EXCEPTION 'a refresh token is marked used, and nothing else about it changes'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'refresh_token_is_used_once';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER refresh_token_is_used_once BEFORE UPDATE ON identity.refresh_token
  FOR EACH ROW EXECUTE FUNCTION identity.refresh_token_is_used_once();

CREATE FUNCTION identity.access_token_is_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'an access token is issued and expires; it is never changed'
    USING ERRCODE = 'check_violation', CONSTRAINT = 'access_token_is_immutable';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER access_token_is_immutable BEFORE UPDATE ON identity.access_token
  FOR EACH ROW EXECUTE FUNCTION identity.access_token_is_immutable();

COMMENT ON TABLE identity.credential IS
  'A provider subject or passkey bound to one live account. Revoked, never deleted; one live account per (kind, subject).';
COMMENT ON TABLE identity.session_family IS
  'One sign-in on one device. Revoked as a whole by logout or by refresh-token reuse (ADR-008).';
COMMENT ON TABLE identity.refresh_token IS 'Single-use; using one marks it used and names its successor. Only the SHA-256 of the secret is stored.';
COMMENT ON TABLE identity.access_token IS 'Opaque, short-lived, looked up per request; names an account, never a permission. Only the SHA-256 is stored.';

GRANT SELECT ON identity.credential, identity.session_family, identity.refresh_token, identity.access_token TO app_read, app_competition;
GRANT INSERT ON identity.credential, identity.session_family, identity.refresh_token, identity.access_token TO app_competition;
GRANT UPDATE (last_used_at, revoked_at, revoked_by, revoked_reason, sign_count) ON identity.credential TO app_competition;
GRANT UPDATE (revoked_at, revoked_reason) ON identity.session_family TO app_competition;
GRANT UPDATE (used_at, superseded_by) ON identity.refresh_token TO app_competition;

RESET ROLE;
