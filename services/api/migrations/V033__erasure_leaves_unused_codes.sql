-- THRØ V033 — erasing somebody who had made a friend code and not given it out yet.
--
-- **What broke.** V031's `identity.erase_account` spent every unused friend code against the account
-- being erased (`used_by = a`), so that a code nobody had typed could admit nobody later. V028's
-- trigger `friend_actor_is_adult` refuses exactly that row — *"a code is for somebody else"* — because
-- a code used by the account that made it is the thing the trigger exists to stop. So erasing anybody
-- who held a code they had made and not handed over raised inside the function, the whole erasure
-- rolled back as it should, and the server answered 500. The founder's own account was that account:
-- one code, made at 09:29 on 2026-09-11 and never used. ErasureTest only ever made a code somebody
-- then used, so it never met the case.
--
-- **Why dropping the step is the fix rather than a workaround.** The door it was closing is already
-- shut, twice. V028's trigger reads the maker's band `WHERE deleted_at IS NULL`, so any use of a code
-- whose maker has been erased raises; and `Friends.accept` now refuses one in words before the
-- trigger is reached. What stays is eight random letters and two timestamps, which name nobody.
-- Writing a use into the row would also have been a false record: nobody used it.
--
-- **And both SECURITY DEFINER functions now name their own search path.** Such a function runs with
-- its owner's rights under the caller's search_path, so a caller able to put a schema ahead of
-- pg_catalog could slip its own `clock_timestamp()` or `gen_random_uuid()` in front of the real one.
-- Every table in both bodies is already schema-qualified; pinning the path closes the rest.

SET ROLE thro_owner;

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

  -- 1. The ways in. The subject IS the identifier, so it is destroyed rather than only revoked.
  --    A credential revoked earlier keeps its revocation exactly as it was: `revocation_is_final`
  --    (V023) refuses a reworded one, and `credential_revocation_is_complete` guarantees it has a
  --    reason already, so `coalesce` leaves both alone.
  UPDATE identity.credential
     SET subject = '', public_key = NULL, sign_count = NULL,
         revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a;
  GET DIAGNOSTICS n_cred = ROW_COUNT;

  -- 2. Every session, everywhere, at once.
  UPDATE identity.session_family
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_fam = ROW_COUNT;

  -- 3. Devices. `label` is the one place a person's own words landed here.
  UPDATE identity.device
     SET label = NULL,
         revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a;
  GET DIAGNOSTICS n_dev = ROW_COUNT;

  -- 4. Friendships, both directions, ended rather than removed: the other person's side is theirs.
  --    Unused codes are left as they are — see the header for why that is already safe.
  UPDATE identity.friendship
     SET ended_at = coalesce(ended_at, clock_timestamp()), ended_by = coalesce(ended_by, a)
   WHERE (account_a = a OR account_b = a) AND ended_at IS NULL;
  GET DIAGNOSTICS n_friend = ROW_COUNT;

  -- 5. The claim on a competitor, revoked: the competitor row stays and carries no name (V018).
  UPDATE identity.player_claim
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_claim = ROW_COUNT;

  -- 6. Consent, withdrawn by the account that gave it.
  UPDATE identity.consent_record
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a)
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_consent = ROW_COUNT;

  -- 7. The account itself: no name, no band, marked.
  UPDATE identity.account
     SET display_name = '', age_band = 'unknown', age_assurance = 'none',
         deleted_at = clock_timestamp()
   WHERE account_id = a;

  INSERT INTO identity.erasure (account_id, credentials, sessions, devices, friendships, claims, consents)
  VALUES (a, n_cred, n_fam, n_dev, n_friend, n_claim, n_consent)
  RETURNING * INTO out;
  RETURN out;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp;

ALTER FUNCTION competition.mint_competitor(uuid) SET search_path = pg_catalog, pg_temp;

-- Restated rather than assumed: CREATE OR REPLACE keeps a function's grants, and this says so.
REVOKE ALL ON FUNCTION identity.erase_account(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION identity.erase_account(uuid) TO app_competition;

RESET ROLE;
