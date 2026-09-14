-- THRØ V031 — a person can take themselves out of THRØ, and what is left names nobody.
--
-- **Why this is redaction and not DELETE.** ADR-013 revokes DELETE from every application role, and
-- that is not an obstacle to erasure — it is the reason erasure can be trusted. A row that can be
-- removed by the running service can be removed by a bug, and a match is two people's record rather
-- than one person's property: erasing a player by deleting rows would silently rewrite the other
-- player's leg, a league's table and a tournament's bracket. So the shape here is V018's, which
-- pseudonymised the names out of match evidence and left the seats: **what identifies a person is
-- destroyed; what belongs to other people is kept, carrying nothing that points back.**
--
-- After this function runs, the rows that remain for that account hold: a random uuid nobody can
-- resolve to a person, timestamps, and structure. No name, no Apple or Google subject, no passkey,
-- no device label, no age, no live friendship, no live claim on a competitor. UK GDPR Article 17 is
-- satisfied by data that can no longer identify anybody (Recital 26), and Article 17(3) is why the
-- match record survives at all: it is another party's record and the basis on which a league's
-- results stand. The app says all of this in words before it asks.
--
-- **Why a SECURITY DEFINER function rather than new grants.** Blanking a credential's subject and a
-- device's label needs UPDATE on columns no app role has, and handing the service those columns
-- permanently — so it could rewrite anybody's sign-in at any time — to enable one rare operation is
-- the wrong trade. One narrow function, owned by thro_owner, doing the whole thing atomically, is
-- the smaller grant: the service may erase an account and may do nothing else to those columns.

SET ROLE thro_owner;

-- APPROVED-DESTRUCTIVE: `passkey_has_a_key` is replaced by `passkey_has_a_key_until_it_is_revoked`, which is the same rule for every live passkey and stops applying once one is revoked. Nothing is dropped but the constraint itself; no row changes, and no row that satisfied the old one fails the new one. It is widened because an erasure has to be able to destroy a public key, and a key that no longer exists cannot be required to (ADR-013).
-- A passkey that has been revoked does not need its public key any more, and after an erasure it
-- must not have one: a public key is bound to a person's device or keychain and would re-identify.
-- The original CHECK said every passkey has a key, which was true while every passkey was live.
ALTER TABLE identity.credential DROP CONSTRAINT passkey_has_a_key;
ALTER TABLE identity.credential ADD CONSTRAINT passkey_has_a_key_until_it_is_revoked
  CHECK (kind <> 'passkey' OR public_key IS NOT NULL OR revoked_at IS NOT NULL);

-- That an erasure happened is itself a fact THRØ has to be able to show — a right exercised, and
-- the answer to "why is this account blank". It names nobody: the account id it carries stopped
-- identifying a person at the moment the row was written.
CREATE TABLE identity.erasure (
  account_id     uuid        PRIMARY KEY REFERENCES identity.account(account_id),
  erased_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- What went, for the record and for the test that holds this honest.
  credentials    int         NOT NULL DEFAULT 0,
  sessions       int         NOT NULL DEFAULT 0,
  devices        int         NOT NULL DEFAULT 0,
  friendships    int         NOT NULL DEFAULT 0,
  claims         int         NOT NULL DEFAULT 0,
  consents       int         NOT NULL DEFAULT 0
);

-- The whole erasure, atomically, as the owner.
CREATE FUNCTION identity.erase_account(a uuid) RETURNS identity.erasure AS $$
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

  -- 1. The ways in. The subject IS the identifier — an Apple or Google user id, or a passkey's
  --    public key — so revoking is not enough and the value is destroyed. The unique index on a
  --    live (kind, subject) is partial, so blanked subjects on revoked rows cannot collide.
  UPDATE identity.credential
     SET subject = '', public_key = NULL, sign_count = NULL,
         revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a;
  GET DIAGNOSTICS n_cred = ROW_COUNT;

  -- 2. Every session, everywhere, at once. A phone still holding a token is signed out on its next
  --    breath rather than at the end of the token's life.
  UPDATE identity.session_family
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_fam = ROW_COUNT;

  -- 3. Devices. `label` is the one place a person's own words landed here — "Jenson's iPhone".
  UPDATE identity.device
     SET label = NULL,
         revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a;
  GET DIAGNOSTICS n_dev = ROW_COUNT;

  -- 4. Friendships, both directions. Ended rather than removed: the other person's side of it is
  --    their record too, and an ended friendship carrying an anonymous id tells nobody anything.
  UPDATE identity.friendship
     SET ended_at = coalesce(ended_at, clock_timestamp()), ended_by = coalesce(ended_by, a)
   WHERE (account_a = a OR account_b = a) AND ended_at IS NULL;
  GET DIAGNOSTICS n_friend = ROW_COUNT;

  -- An unused invite is a code somebody could still type. Spend it against the erased account so it
  -- admits nobody, rather than leaving a live door into a friendship with a person who has gone.
  UPDATE identity.friend_invite
     SET used_by = a, used_at = clock_timestamp()
   WHERE account_id = a AND used_at IS NULL;

  -- 5. The claim on a competitor. Revoked, not deleted: the competitor row stays, because a match
  --    played against somebody else is that person's record too — and it carries no name, so what
  --    remains is a seat in a leg, which is what V018 established a competitor is.
  UPDATE identity.player_claim
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         revoked_by = coalesce(revoked_by, a),
         revoked_reason = coalesce(revoked_reason, 'the account was erased at its owner''s request')
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_claim = ROW_COUNT;

  -- 6. Consent. Withdrawn, so `identity.player_may_be_disclosed` answers false from here on and
  --    nothing about this person can leave THRØ again.
  UPDATE identity.consent_record
     SET revoked_at = coalesce(revoked_at, clock_timestamp()),
         -- `consent_revocation_is_complete`: a withdrawal with nobody withdrawing it is not a
         -- record. It is their own account that withdrew it, which is exactly what happened.
         revoked_by = coalesce(revoked_by, a)
   WHERE account_id = a AND revoked_at IS NULL;
  GET DIAGNOSTICS n_consent = ROW_COUNT;

  -- 7. The account itself. An empty name rather than a tombstone word: "Deleted player" is still a
  --    sentence about somebody, and nothing should render it — every roster is already gated on
  --    `player_may_be_disclosed`, which is false the moment `deleted_at` is set.
  UPDATE identity.account
     SET display_name = '', age_band = 'unknown', age_assurance = 'none',
         deleted_at = clock_timestamp()
   WHERE account_id = a;

  INSERT INTO identity.erasure (account_id, credentials, sessions, devices, friendships, claims, consents)
  VALUES (a, n_cred, n_fam, n_dev, n_friend, n_claim, n_consent)
  RETURNING * INTO out;
  RETURN out;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION identity.erase_account(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION identity.erase_account(uuid) TO app_competition;
GRANT SELECT ON identity.erasure TO app_read, app_competition;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON identity.erasure FROM app_competition, app_read, app_match, app_trust, app_rating;

RESET ROLE;
