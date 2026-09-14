-- THRØ V026 — what hostile review of V025 found.
--
-- 1. A WebAuthn user handle must be the same for every passkey an account ever creates: Apple
--    replaces a passkey in iCloud Keychain when a new one is created for the same relying party
--    and user id, and the server must know which credentials to exclude. The handle lives on the
--    account, once, for its whole life. Existing accounts are given one.
-- 2. Challenges are ceremony bookkeeping, not history: an unauthenticated route creates one per
--    call and nothing removed them. Expired challenges older than a day are swept by a function
--    the owner defines and the application may call; no application role gains DELETE.

SET ROLE thro_owner;

ALTER TABLE identity.account
  ADD COLUMN user_handle bytea NOT NULL DEFAULT decode(md5(random()::text) || md5(random()::text), 'hex')
  CHECK (octet_length(user_handle) = 32);
CREATE UNIQUE INDEX account_user_handle ON identity.account (user_handle);

CREATE INDEX webauthn_challenge_by_expiry ON identity.webauthn_challenge (expires_at);

CREATE FUNCTION identity.sweep_challenges() RETURNS int
LANGUAGE sql SECURITY DEFINER AS $$
  WITH gone AS (DELETE FROM identity.webauthn_challenge WHERE expires_at < clock_timestamp() - interval '1 day' RETURNING 1)
  SELECT count(*)::int FROM gone
$$;
REVOKE ALL ON FUNCTION identity.sweep_challenges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION identity.sweep_challenges() TO app_competition;

COMMENT ON COLUMN identity.account.user_handle IS
  'The WebAuthn user id for every passkey this account creates, fixed for the account''s life.';

RESET ROLE;
