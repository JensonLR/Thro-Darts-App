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

-- 2. The columns go. What they held is now derivable from nothing in this schema, which is the point.
ALTER TABLE evidence.match DROP COLUMN home_name, DROP COLUMN away_name;

COMMENT ON TABLE evidence.match IS
  'The authoritative participant set and ruleset for a match, fixed when it opens. The home seat is '
  'home_id and the away seat is away_id; the engine labels them ''home'' and ''away'' and evidence '
  'names the seat. No display name is stored here or in any payload (OD-024, V018).';

RESET ROLE;
