-- THRØ V025 — passkeys (WebAuthn), the fallback sign-in PD-030 names.
--
-- A passkey is a credential row already (V023: kind 'passkey', public_key, sign_count). What
-- WebAuthn adds is a challenge: 32 random bytes THRØ hands to the authenticator, which must sign
-- them back within five minutes, once. The challenge is what stops a captured registration or
-- assertion being replayed. It is stored, not signed into a cookie, so a used challenge stays used
-- across every instance of the server.

SET ROLE thro_owner;

CREATE TABLE identity.webauthn_challenge (
  challenge_id  uuid        PRIMARY KEY,
  kind          text        NOT NULL CHECK (kind IN ('register','assert')),
  challenge     bytea       NOT NULL CHECK (octet_length(challenge) = 32),
  -- register: the account the passkey is added to, or NULL when the registration creates one, in
  -- which case user_handle is the id the authenticator will remember for the new account.
  account_id    uuid        REFERENCES identity.account(account_id),
  user_handle   bytea,
  device_id     uuid        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at    timestamptz NOT NULL,
  used_at       timestamptz,
  CONSTRAINT challenge_register_names_who CHECK (kind <> 'register' OR (account_id IS NOT NULL) <> (user_handle IS NOT NULL))
);

CREATE FUNCTION identity.challenge_is_used_once() RETURNS trigger AS $$
BEGIN
  IF OLD.used_at IS NOT NULL THEN
    RAISE EXCEPTION 'a used challenge is history'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'challenge_is_used_once';
  END IF;
  IF to_jsonb(NEW) - 'used_at' IS DISTINCT FROM to_jsonb(OLD) - 'used_at' THEN
    RAISE EXCEPTION 'a challenge is marked used, and nothing else about it changes'
      USING ERRCODE = 'check_violation', CONSTRAINT = 'challenge_is_used_once';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER challenge_is_used_once BEFORE UPDATE ON identity.webauthn_challenge
  FOR EACH ROW EXECUTE FUNCTION identity.challenge_is_used_once();

COMMENT ON TABLE identity.webauthn_challenge IS
  'One WebAuthn ceremony: 32 random bytes the authenticator must sign back within five minutes, once.';

GRANT SELECT, INSERT ON identity.webauthn_challenge TO app_competition;
GRANT UPDATE (used_at) ON identity.webauthn_challenge TO app_competition;

RESET ROLE;
