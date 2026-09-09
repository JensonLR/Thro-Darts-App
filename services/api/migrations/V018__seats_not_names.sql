-- THRØ V018 — the match aggregate binds seats to competitors; it never carries a name.
--
-- Closes OD-024. V006 gave `evidence.match` home_name and away_name, because the scoring engine
-- works in string labels and the labels were the names typed at the oche. Every VisitRecorded and
-- VisitCorrected payload then carried the same name in its `player` field. That put personal data —
-- a display name, possibly a child's — inside an append-only schema that no application role may
-- update or delete, which is exactly the place it can never be rectified or erased from. Hostile
-- review of ADR-017 named it; Phase C, which opens a match from a league fixture, could not proceed
-- with it standing.
--
-- The fix is that the engine's two labels are SEATS — the constants 'home' and 'away' — and the
-- aggregate binds each seat to a competitor identifier. A visit's evidence says which seat threw;
-- the aggregate, fixed when the match opened, says who sat there; a display name is joined from the
-- identity module at render time and never stored beside the evidence. The engine, the client's
-- journal and the server all speak the same two words, and nothing personal enters `evidence`.
--
-- Existing rows. THRØ has never run, so there are none in production — but this is written as if
-- there were, and it is the ONE deliberate rewrite of evidence in this repository: a pseudonymisation
-- the data-protection promise requires (ADR-011's pseudonymisation gate), performed once, by the
-- owner role, and recorded here. A name is replaced by the seat it labelled; nothing else in any
-- payload changes; the row count is unchanged. MigrationTest populates a V013 database with named
-- matches and visits and reads every one back as seats.

SET ROLE thro_owner;

-- APPROVED-EVIDENCE-REWRITE (pseudonymisation): the display name in every visit payload's `player` field is replaced by the seat it labelled ('home' or 'away'); no score, sequence, seat or row changes. A read-time upcast cannot do this because the name would still be stored, and OD-024's point is that it must not be (ADR-013 amendment, 2026-09-09).
-- APPROVED-DESTRUCTIVE: evidence.match.home_name and away_name are personal data; what they held is intentionally derivable from nothing in this schema after this migration. The two seats are bound to home_id and away_id, which stay.

-- 0. Refuse to guess. A match whose two names are the same cannot say which seat a name meant;
--    if such a match has visits, a person resolves it before this runs. (The handler never
--    accepted one — the engine refuses two equal labels — so this guards rows written some other way.)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM evidence.match m
     WHERE m.home_name = m.away_name
       AND EXISTS (SELECT 1 FROM evidence.event e WHERE e.match_id = m.match_id
                    AND e.event_type IN ('VisitRecorded','VisitCorrected'))
  ) THEN
    RAISE EXCEPTION 'V018: a match has identical names for both seats and has visits; the seat each name meant cannot be derived. Resolve it by hand before migrating.';
  END IF;
END $$;

-- 1. Payloads: the name that labelled a seat becomes the seat. Matched per match against that
--    match's own two names, never by a global lookup, so a name shared by two people in two
--    matches cannot cross between them.
UPDATE evidence.event e
   SET payload = jsonb_set(e.payload, '{player}',
                           to_jsonb(CASE WHEN e.payload->>'player' = m.home_name THEN 'home' ELSE 'away' END))
  FROM evidence.match m
 WHERE m.match_id = e.match_id
   AND e.event_type IN ('VisitRecorded','VisitCorrected')
   AND e.payload ? 'player'
   AND e.payload->>'player' IN (m.home_name, m.away_name);

-- 2. Refuse to leave a name behind. A payload whose player is not one of its match's two names —
--    a spelling variant, a name from before the aggregate check, anything — is exactly the personal
--    data this migration exists to remove, and quietly keeping it would make the header above a lie.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM evidence.event
   WHERE event_type IN ('VisitRecorded','VisitCorrected') AND payload ? 'player'
     AND (jsonb_typeof(payload->'player') <> 'string' OR payload->>'player' NOT IN ('home','away'));
  IF n > 0 THEN
    RAISE EXCEPTION 'V018: % visit payload(s) name something that is neither seat of their match; they must be resolved by hand before the names can go', n;
  END IF;
END $$;

-- 3. The columns go. What they held is now derivable from nothing in this schema, which is the point.
ALTER TABLE evidence.match DROP COLUMN home_name, DROP COLUMN away_name;

-- 4. And the database keeps it so: from here on a visit's player field, when present, is a seat.
ALTER TABLE evidence.event ADD CONSTRAINT visit_names_a_seat CHECK (
  event_type NOT IN ('VisitRecorded','VisitCorrected')
  OR NOT (payload ? 'player')
  OR payload->>'player' IN ('home','away')
);

COMMENT ON TABLE evidence.match IS
  'The authoritative participant set and ruleset for a match, fixed when it opens. The home seat is '
  'home_id and the away seat is away_id; the engine labels them ''home'' and ''away'' and evidence '
  'names the seat. No display name is stored here or in any payload (OD-024, V018).';

RESET ROLE;
