-- A game on a public screen (PD-088).
--
-- The founder's decision, 13 September 2026: *"If it's legal all games should be live shown."* The
-- conditional is the whole of the work. This migration is where the line goes, because a line that lives
-- in a request handler is a line one refactor away from moving.
--
-- **What is plainly lawful.** An adult who has said yes, playing in a league's own published competition,
-- shown on a screen in the pub they are standing in. That is the product. It needs a lawful basis and it
-- has the strongest one available: the person's own consent, given for this purpose, withdrawable.
--
-- **What is not.** A **child's** live game, named, on a screen in a room of strangers. Not because a
-- statute forbids it in terms, but because a live board publishes something a result never does: *where a
-- named person is, right now.* The ICO's Age appropriate design code puts the burden on the controller to
-- show that a use is in the best interests of the child, and Standard 1 is not satisfied by a guardian
-- ticking a box THRØ cannot verify (see the DPIA, R3 — THRØ has **no way to verify a guardian**). So the
-- guardian branch that `player_may_be_disclosed` allows is deliberately **absent** here.
--
-- **And an unknown age is not an adult**, which is the rule the rest of this system already turns on. It
-- is load-bearing precisely because it is what happens when nobody has said.
--
-- The consequence, said plainly so nobody reads this as caution rather than design: a pub wall showing a
-- league night will name most of the room and not all of it. A player who has not said yes appears as the
-- **team** they are playing for. Nothing is hidden; a person is simply not named until they say so.

SET ROLE thro_owner;

-- ---------------------------------------------------------------------------------------------
-- Consent gains a scope
-- ---------------------------------------------------------------------------------------------
--
-- **A defect found while writing this, and it is the important part of the migration.**
--
-- `identity.account_consent_starts_honest` (V016) writes a consent record on every self-created account,
-- and its own comment says exactly what it means: *"A person who creates their own account has, by that
-- act, consented to THRØ holding what they typed."* That is true, and it is consent to **holding**.
--
-- `player_may_be_disclosed` then read that same record as consent to being **named on a public page**.
-- Those are not the same thing. Creating an account is not agreeing to appear on a web page, and under
-- Art 4(11) consent has to be specific and informed — a record whose artefact is literally
-- `account_creation` cannot carry either. So an adult who signed in and claimed a THRØ ID was nameable
-- publicly having never been asked.
--
-- (The Standard 7 audit reported the opposite — that nothing writes a consent record, so nobody is ever
-- named. That was wrong: it traced `Secretary.recordConsent`, which indeed has no caller, and missed the
-- trigger. `docs/legal/DEFAULTS_AUDIT.md` is corrected.)
--
-- Adding a scope with a `listing` default would have **cemented** that: every account-creation record
-- would have backfilled into "yes, name me". So there are three scopes, and account creation gets the
-- one it actually means:
--
--   holding  THRØ may keep what I typed. Given by the act of making an account, and by nothing else.
--   listing  I may be named on my team's public page. Static, and about membership.
--   live     I may be named on a screen while I am playing. Real-time, and about presence.
--
-- Neither gate accepts `holding`. Nobody is named anywhere until they have said the specific thing.

ALTER TABLE identity.consent_record
  ADD COLUMN scope text NOT NULL DEFAULT 'holding' CHECK (scope IN ('holding','listing','live'));

-- Every row that exists today came from the account-creation trigger, because nothing else has ever
-- written one. Stated as a condition rather than assumed, so that if that stops being true the rows that
-- disagree keep the meaning they had.
UPDATE identity.consent_record SET scope = 'listing' WHERE artefact_ref <> 'account_creation';

COMMENT ON COLUMN identity.consent_record.scope IS
  'What was consented to. `holding` is THRO keeping what you typed, which making an account implies; '
  '`listing` is being named on a public page; `live` is being named on a screen while playing, which '
  'discloses where you are at the time. Only the last two let a name out, and neither is implied.';

-- Account creation says what it means. The behaviour is unchanged — the row, the actor and the artefact
-- are identical — and only the scope is now written rather than defaulted, so nobody reading this table
-- has to know what the default was on the day the row was inserted.
CREATE OR REPLACE FUNCTION identity.account_consent_starts_honest() RETURNS trigger AS $$
BEGIN
  IF NEW.created_via = 'self' THEN
    INSERT INTO identity.consent_record (account_id, basis, scope, given_by, artefact_ref)
      VALUES (NEW.account_id, 'self', 'holding', NEW.account_id, 'account_creation');
  ELSE
    UPDATE identity.account SET consent_basis = 'none' WHERE account_id = NEW.account_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- One live record per account per scope per basis, so "say yes twice" is idempotent rather than a pile.
CREATE UNIQUE INDEX consent_one_live_per_scope
  ON identity.consent_record (account_id, scope, basis) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------------------------
-- The two gates
-- ---------------------------------------------------------------------------------------------

-- **Changed in behaviour, deliberately.** Before this it read every consent record, which meant it read
-- the account-creation one, which meant an adult who had merely signed in could be named on a public
-- page. It now requires a consent whose scope actually says `listing` — a thing somebody has to have
-- been asked for. Nobody is named until they answer.
CREATE OR REPLACE FUNCTION identity.player_may_be_disclosed(p uuid) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
      FROM identity.player_claim c
      JOIN identity.account a ON a.account_id = c.account_id
     WHERE c.player_id = p AND c.revoked_at IS NULL AND a.deleted_at IS NULL
       AND (
         EXISTS (SELECT 1 FROM identity.consent_record r
                  WHERE r.account_id = a.account_id AND r.revoked_at IS NULL
                    AND r.scope = 'listing' AND r.basis = 'guardian')
         OR (a.age_band = 'adult' AND EXISTS (
             SELECT 1 FROM identity.consent_record r
              WHERE r.account_id = a.account_id AND r.revoked_at IS NULL
                AND r.scope = 'listing' AND r.basis = 'self'))
       )
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Stricter than disclosure, in exactly one way that matters: **there is no guardian branch.**
--
-- Read the difference against `player_may_be_disclosed` above. There, a guardian's consent is enough to
-- put a minor's name on a team page — a static list, of a fact (this person is in this team) that a
-- league publishes anyway. Here it is not enough, because what is published is not a fact about
-- membership but a fact about presence, in real time, to whoever is in the room.
--
-- A minor therefore cannot be shown live, and neither can anybody whose age nobody has established.
CREATE OR REPLACE FUNCTION identity.player_may_be_shown_live(p uuid) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
      FROM identity.player_claim c
      JOIN identity.account a ON a.account_id = c.account_id
     WHERE c.player_id = p AND c.revoked_at IS NULL AND a.deleted_at IS NULL
       AND a.age_band = 'adult'
       AND EXISTS (SELECT 1 FROM identity.consent_record r
                    WHERE r.account_id = a.account_id AND r.revoked_at IS NULL
                      AND r.scope = 'live' AND r.basis = 'self')
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION identity.player_may_be_shown_live IS
  'Whether this player may be NAMED on a public live screen. Adults who have said so themselves, and '
  'nobody else: no guardian branch, because a live board discloses where a named person is at the time '
  'and THRO cannot verify a guardian. An unknown age is not an adult.';

-- ---------------------------------------------------------------------------------------------
-- Reading it back
-- ---------------------------------------------------------------------------------------------

-- The live board stands as **`app_read`**, which is the narrowest role there is and cannot see a single
-- column of `identity`. Both gates are SECURITY DEFINER for exactly that reason: the *answer* crosses the
-- boundary and the data does not, so a screen that asks "may I name this person" never gets the chance to
-- read anything else about them while it is there.
--
-- `app_competition` already holds INSERT and UPDATE on `identity.consent_record` from V016, which is what
-- the consent route needs; nothing new is granted for writing.
GRANT EXECUTE ON FUNCTION identity.player_may_be_shown_live(uuid) TO app_read, app_competition;
GRANT EXECUTE ON FUNCTION identity.player_may_be_disclosed(uuid) TO app_read, app_competition;

-- And the board reads the league's own tables as the read role, which V014 did not have to grant because
-- until now nothing public read a fixture's match.
GRANT SELECT ON competition.league_fixture, competition.league_fixture_outcome,
                competition.team, competition.venue, evidence.match TO app_read;

RESET ROLE;
