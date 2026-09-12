-- THRØ V011 — identity, and age as an authorization dimension.
--
-- ADR-005 confines ALL personal data to this module. That is not tidiness: it is what makes the
-- design's export and deletion promises tractable, because "everything we hold about this person"
-- has a single answer rather than a survey of every schema.
--
-- ADR-008 calls the age dimension the retrofit-killer. Visibility rules written without it mean
-- re-auditing every endpoint and every public page later, so the field and the dimension exist from
-- the first account. The POLICY — declared date of birth, self-declared band, or verified
-- assurance, and what each unlocks — remains a founder decision and is open as OD-010. Nothing here
-- decides it, and nothing here is a legal conclusion.

CREATE SCHEMA identity AUTHORIZATION thro_owner;

SET ROLE thro_owner;

CREATE TABLE identity.account (
  account_id    uuid        PRIMARY KEY,
  display_name  text        NOT NULL,
  -- NOT NULL on purpose, with 'unknown' as a value rather than an absence. A nullable band is a
  -- band that gets forgotten in a WHERE clause; an explicit 'unknown' has to be handled, and is
  -- treated as the most restrictive case wherever it is read.
  age_band      text        NOT NULL DEFAULT 'unknown'
                CHECK (age_band IN ('unknown','minor','adult')),
  -- How the band came to be believed. An assurance level is evidence quality, not permission:
  -- what each level unlocks is OD-010's to decide.
  age_assurance text        NOT NULL DEFAULT 'none'
                CHECK (age_assurance IN ('none','self_declared','guardian_declared','verified')),
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  deleted_at    timestamptz,
  CONSTRAINT band_unknown_has_no_assurance
    CHECK (age_band <> 'unknown' OR age_assurance = 'none')
);

COMMENT ON COLUMN identity.account.age_band IS
  'A dimension, not a policy. Only the minor/adult distinction is modelled, because that is the '
  'one every safeguarding regime shares; the thresholds, what evidence establishes them, and what '
  'each unlocks are OD-010 and are not decided here.';

-- Registered devices, with per-device revocation. ADR-008 makes platform attestation a PROVENANCE
-- input and never a gate: an attested device produces stronger evidence, but attestation is
-- bypassable and fails legitimate users, so it must not decide whether someone may play.
CREATE TABLE identity.device (
  device_id     uuid        PRIMARY KEY,
  account_id    uuid        NOT NULL REFERENCES identity.account(account_id),
  label         text,
  attested      boolean     NOT NULL DEFAULT false,
  registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at    timestamptz,
  revoked_reason text
);

CREATE INDEX device_by_account ON identity.device (account_id) WHERE revoked_at IS NULL;

-- A device registration cannot be un-revoked, for the same reason a scoring grant cannot: it would
-- rewrite what was true at a moment that has already passed.
CREATE FUNCTION identity.device_revocation_is_final() RETURNS trigger AS $$
BEGIN
  IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
    RAISE EXCEPTION 'a device revocation cannot be undone (device %)', OLD.device_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER device_revocation_is_final BEFORE UPDATE ON identity.device
  FOR EACH ROW EXECUTE FUNCTION identity.device_revocation_is_final();

-- Personal data is readable only by the module that owns it and the read models it publishes.
-- The match, trust and rating modules never need a display name to do their work.
GRANT USAGE ON SCHEMA identity TO app_read, app_competition;
GRANT SELECT ON identity.account, identity.device TO app_read, app_competition;
GRANT INSERT, UPDATE ON identity.account, identity.device TO app_competition;
REVOKE ALL ON identity.account, identity.device FROM app_match, app_trust, app_rating;

RESET ROLE;
