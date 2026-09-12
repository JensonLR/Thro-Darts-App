-- THRØ V024 — what hostile review of V023 found: a session family lived for ever, and the
-- application role could rewrite any column of an account.
--
-- 1. A family now has an absolute lifetime. Rotation refreshes the tokens, not the family: after
--    ninety days the person signs in again, whatever they did in between (ADR-008: re-authentication
--    is forced, not hoped for).
-- 2. V011 granted UPDATE on the whole account row to app_competition, which let the application set
--    created_via and consent_basis — the two columns V016 keeps honest by trigger. The grant is now
--    the columns the application legitimately writes and no other.

SET ROLE thro_owner;

ALTER TABLE identity.session_family
  ADD COLUMN expires_at timestamptz NOT NULL DEFAULT clock_timestamp() + interval '90 days';

COMMENT ON COLUMN identity.session_family.expires_at IS
  'Absolute lifetime. Refresh rotates tokens within it; past it the person signs in again.';

REVOKE UPDATE ON identity.account FROM app_competition;
GRANT UPDATE (display_name, age_band, age_assurance, deleted_at) ON identity.account TO app_competition;

RESET ROLE;
