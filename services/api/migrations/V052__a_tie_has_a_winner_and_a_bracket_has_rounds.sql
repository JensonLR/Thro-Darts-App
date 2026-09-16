-- A tie has a winner, and a bracket has rounds (PD-111).
--
-- V013 drew round one and stopped: a tie could name the match it was played in and nothing read who won it, so a
-- knockout on THRØ was a first round and a shrug. A tie now carries its winner and how it was decided — read from the
-- match's own record when one is cited, or declared by the organiser as a walkover or an award — and the event's
-- organiser advances a round once every tie in it is decided. A bye is still not a win: it is a tie with one side,
-- whose "winner" is that side by construction, and it produces no statistics and no match.
--
-- Nothing here touches evidence: a match's winner is derived from its record every time it is read (MatchRecords),
-- and what a tie stores is the derivation's answer with who accepted it and when.

SET ROLE thro_owner;

ALTER TABLE competition.bracket_tie
  ADD COLUMN winner_id  uuid,
  ADD COLUMN outcome    text CHECK (outcome IN ('played','walkover','awarded','bye')),
  ADD COLUMN decided_by uuid,
  ADD COLUMN decided_at timestamptz,
  ADD COLUMN note       text,
  ADD CONSTRAINT tie_winner_is_a_side CHECK (winner_id IS NULL OR winner_id = home_id OR winner_id = away_id),
  ADD CONSTRAINT tie_decision_is_complete CHECK ((winner_id IS NULL) = (outcome IS NULL) AND (winner_id IS NULL) = (decided_at IS NULL)),
  ADD CONSTRAINT tie_played_cites_its_match CHECK (outcome IS DISTINCT FROM 'played' OR match_id IS NOT NULL),
  ADD CONSTRAINT tie_bye_wins_by_construction CHECK (NOT is_bye OR outcome IS NULL OR outcome = 'bye');

COMMENT ON COLUMN competition.bracket_tie.winner_id IS
  'PD-111: who goes through. Read from the cited match''s record (played), or the organiser''s word (walkover, awarded), '
  'or the one side of a bye. Never a rating input on its own; the match record is.';

RESET ROLE;
