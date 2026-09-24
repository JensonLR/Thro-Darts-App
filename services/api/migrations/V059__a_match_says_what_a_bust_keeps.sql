-- A match says what a bust keeps (OD-023).
--
-- Some pub leagues play a local rule: the darts scored before the busting dart stand, and only the busting dart
-- counts for nothing. On 40, a 20 then a D15 leaves 20 there and 40 everywhere else. The engine (spec 1.4.0) now
-- plays both, and reads which from the match's format — so the match has to hold it, fixed when it opens, like every
-- other rule it is played under. A rule the server guessed at would replay one league's night under another's rules.
--
-- One column, with the standard rule as its default: every match already held was played under it, because until
-- now there was no other. Nothing in `evidence` is rewritten; a match opened before V059 reads as it always did.
--
-- The darts themselves need no column. A visit recorded dart by dart carries them in its event's payload
-- (`"darts":["T20","T20","D20"]`, schema_version 2), beside the total, the dart counts and the effect the engine
-- derived from them, so a reader that knows only totals still reads the visit.

SET ROLE thro_owner;

ALTER TABLE evidence.match
  ADD COLUMN bust_rule text NOT NULL DEFAULT 'restore_visit',
  ADD CONSTRAINT match_bust_rule_is_one_thro_plays
    CHECK (bust_rule IN ('restore_visit', 'keep_scored_darts'));

COMMENT ON COLUMN evidence.match.bust_rule IS
  'OD-023: what a bust does to the score. restore_visit (the standard rule) puts the whole visit back; '
  'keep_scored_darts (a local pub rule) stands the darts before the busting one. Fixed when the match opens, '
  'like the rest of its format. Every match opened before V059 was played under restore_visit.';

RESET ROLE;
