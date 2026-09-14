-- THRØ V006 — the match aggregate.
--
-- ADR-008 names the highest-value attack in the product: post a leg event carrying a stranger's
-- match id and you move a stranger's rating. The defence is that every event is validated against
-- the aggregate's own participant set, LOADED FROM THE STORE — never against identifiers in the
-- request body. Without a stored aggregate there is nothing to validate against, so the control
-- cannot exist. This table is that aggregate.
--
-- It lives in the evidence schema because ADR-005 gives the match module ownership of the match
-- aggregate and its streams. That placement also makes it immutable for free: V001's append-only
-- default privileges grant SELECT and INSERT on future tables in this schema and revoke UPDATE,
-- DELETE and TRUNCATE. Who is playing is fixed when the match opens, which is exactly the property
-- the security control depends on — a participant set that could be edited later would let an
-- attacker write themselves into a match after the fact.

SET ROLE thro_owner;

CREATE TABLE evidence.match (
  match_id      uuid        PRIMARY KEY,
  event_id      uuid,                        -- NULL for a casual match outside a competition
  home_id       uuid        NOT NULL,
  away_id       uuid        NOT NULL,
  home_name     text        NOT NULL,
  away_name     text        NOT NULL,
  starting_score int        NOT NULL CHECK (starting_score > 1),
  in_rule       text        NOT NULL CHECK (in_rule  IN ('straight','double','master')),
  out_rule      text        NOT NULL CHECK (out_rule IN ('straight','double','master')),
  legs_mode     text        NOT NULL CHECK (legs_mode IN ('first_to','best_of')),
  legs_target   int         NOT NULL CHECK (legs_target > 0),
  throw_first   uuid        NOT NULL,
  opened_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT match_has_two_competitors CHECK (home_id <> away_id),
  CONSTRAINT match_thrower_is_a_competitor CHECK (throw_first IN (home_id, away_id))
);

CREATE INDEX match_by_event ON evidence.match (event_id) WHERE event_id IS NOT NULL;

COMMENT ON TABLE evidence.match IS
  'The authoritative participant set and ruleset for a match, fixed when it opens. Every visit is '
  'validated against this, never against identifiers supplied by the caller.';

-- Evidence may only reference a match that exists. Without this an attacker can append a stream
-- under an invented match id and it will sit in the log looking exactly like competitive truth.
--
-- Applied without a backfill because there is no production data: THRØ has never run. Against a
-- populated log this migration would need every existing match_id reconstructed into the aggregate
-- first, and it would be right to refuse rather than to drop the orphans — an event whose match
-- cannot be identified is the exact condition this constraint exists to make impossible.
ALTER TABLE evidence.event
  ADD CONSTRAINT event_belongs_to_a_real_match
  FOREIGN KEY (match_id) REFERENCES evidence.match(match_id);

RESET ROLE;
