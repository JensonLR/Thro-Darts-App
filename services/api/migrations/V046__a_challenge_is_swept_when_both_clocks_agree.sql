-- THRØ V046 — a challenge is swept only when both clocks agree it has gone.
--
-- **What broke.** Two clocks judged the same challenge. The application issues it with an expiry read
-- from its own clock (`Accounts.newChallenge`, `now() + CHALLENGE_TTL`) and refuses it by the same clock
-- (`takeChallenge`). V026's sweep read only the database's: it removed every challenge whose expiry was
-- more than a day before `clock_timestamp()`. In production the two agree to within seconds and the day's
-- grace hides the join. In a test they do not: `PasskeyTest` fixes its clock at 2026-09-12T10:00Z, and at
-- 10:05Z on 13 September — a day and five minutes later, with no change to any code — the second request
-- for options swept the first challenge before the test spent it. The check that a registration from
-- another origin is refused answered "unknown, expired or already used challenge" instead, and failed.
--
-- **The fix is one rule for both clocks, not a moved test date.** The application tells the sweep its
-- time, and the sweep removes only what is a day expired by the earlier of that time and the database's.
-- A challenge the application still holds is never swept from under it; and because the database's clock
-- still bounds it, an application that claimed a later time could not sweep a live challenge early. A
-- ceremony can only be made to fail by that, never to succeed, but a function that deletes should not
-- take its caller's word for when "now" is.
--
-- **And the path is pinned.** V026's function was SECURITY DEFINER with the caller's search path —
-- V033 names why that is wrong and fixed the two functions it found, and this one was missed. Its body
-- is already schema-qualified; pinning the path closes the rest, the same way.

SET ROLE thro_owner;

CREATE FUNCTION identity.sweep_challenges(at timestamptz) RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH gone AS (
    DELETE FROM identity.webauthn_challenge
    WHERE expires_at < least(at, clock_timestamp()) - interval '1 day'
    RETURNING 1
  )
  SELECT count(*)::int FROM gone
$$;
REVOKE ALL ON FUNCTION identity.sweep_challenges(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION identity.sweep_challenges(timestamptz) TO app_competition;

COMMENT ON FUNCTION identity.sweep_challenges(timestamptz) IS
  'Removes challenges a day expired by the earlier of the caller''s clock and the database''s. Nothing either still holds.';

-- The one-clock version goes, so there is no second way to sweep.
-- APPROVED-DESTRUCTIVE: the zero-argument `identity.sweep_challenges()` is replaced by `sweep_challenges(timestamptz)` in this same migration, its one caller (`Accounts.newChallenge`) moves with it, and no table or row is touched — a function holds nothing.
DROP FUNCTION identity.sweep_challenges();

RESET ROLE;
