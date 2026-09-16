-- An organiser may be reached (PD-104).
--
-- THRØ has held no email address for anybody, on purpose, and the privacy notice says so. That stays true for
-- players and for every child. It stops being true for one kind of person: an adult who runs a league or a team,
-- who may give an email so the teams in their league can reach them and so a league can one day be handed on
-- (OD-025). Optional, theirs to remove, never public, and gone with the rest on erasure.
--
-- Who may set it is the application's rule (an adult; a live admin relation on a league season or a team), because
-- the relation lives in `authz` and a trigger reaching across schemas for a policy is the wrong place for one. What
-- the column will hold is the database's: one address, lower-case, of a plausible shape, no longer than the RFC
-- allows.

SET ROLE thro_owner;

ALTER TABLE identity.account
  ADD COLUMN contact_email        text,
  ADD COLUMN contact_email_set_at timestamptz,
  ADD CONSTRAINT contact_email_is_one_address
    CHECK (contact_email IS NULL OR (contact_email = lower(contact_email) AND length(contact_email) <= 254
                                     AND contact_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  ADD CONSTRAINT contact_email_is_dated CHECK ((contact_email IS NULL) = (contact_email_set_at IS NULL));
GRANT UPDATE (contact_email, contact_email_set_at) ON identity.account TO app_competition;

-- Erasure takes the email with the name. The function is V033's, with step 7 one line longer; everything else in it
-- is as it was, because a function that redacts is one nobody should have to re-read for a new column.
CREATE OR REPLACE FUNCTION identity.erase_account(a uuid) RETURNS identity.erasure AS $$
DECLARE
  out identity.erasure;
  n_cred int; n_fam int; n_dev int; n_friend int; n_claim int; n_consent int;
BEGIN
  PERFORM 1 FROM identity.account WHERE account_id = a FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such account';
  END IF;
  IF EXISTS (SELECT 1 FROM identity.account WHERE account_id = a AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'this account was already erased';
  END IF;

  UPDATE identity.credential
     SET subject = '', public_key = NULL, sign_count = NULL,
         revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a;
  GET DIAGNOSTICS n_cred = ROW_COUNT;

  UPDATE identity.session_family
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_fam = ROW_COUNT;

  UPDATE identity.device
     SET label = NULL,
         revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a;
  GET DIAGNOSTICS n_dev = ROW_COUNT;

  UPDATE identity.friendship
     SET ended_at = coalesce(ended_at, clock_timestamp()), ended_by = coalesce(ended_by, a)
   WHERE (account_a = a OR account_b = a) AND ended_at IS NULL;
  GET DIAGNOSTICS n_friend = ROW_COUNT;

  UPDATE identity.player_claim
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_claim = ROW_COUNT;

  UPDATE identity.consent_record
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a)
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_consent = ROW_COUNT;

  -- 7. The account itself: no name, no band, no email, marked.
  UPDATE identity.account
     SET display_name = '', age_band = 'unknown', age_assurance = 'none',
         contact_email = NULL, contact_email_set_at = NULL,
         deleted_at = clock_timestamp()
   WHERE account_id = a;

  INSERT INTO identity.erasure (account_id, credentials, sessions, devices, friendships, claims, consents)
  VALUES (a, n_cred, n_fam, n_dev, n_friend, n_claim, n_consent)
  RETURNING * INTO out;
  RETURN out;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

RESET ROLE;
