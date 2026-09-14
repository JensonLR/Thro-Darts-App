-- THRØ V035 — an ending that leaves out how, or who, is refused after all.
--
-- **What was wrong with V034.** Its CHECK read `ending = 'abandoned' OR (ending = 'retired' AND seat IN
-- ('home','away'))`. For a retirement with no seat, `seat IN (...)` is NULL, so the whole expression is
-- NULL — and a CHECK passes on NULL. The table therefore took a retirement that named nobody, which is
-- the one thing the constraint was added to refuse; an ending with no `ending` key at all passed the
-- same way. The schema properties caught it the first time they ran; the upload never sends such a row,
-- because it checks the seat itself, which is why no Kotlin test could see it. V034 had already reached
-- staging, holding no ending rows, so the constraint is replaced forward rather than edited in place.
--
-- The new one cannot be NULL: `IS NOT DISTINCT FROM` answers true or false, and a missing seat is false.

SET ROLE thro_owner;

-- APPROVED-DESTRUCTIVE: `an_ending_says_how` is replaced by `an_ending_says_how_and_who` in this same migration; it is dropped only because it let NULL through, no row on any database carries a MatchEndedShort it would judge differently, and nothing but the constraint changes.
ALTER TABLE evidence.event DROP CONSTRAINT an_ending_says_how;
ALTER TABLE evidence.event ADD CONSTRAINT an_ending_says_how_and_who CHECK (
  event_type <> 'MatchEndedShort'
  OR payload->>'ending' IS NOT DISTINCT FROM 'abandoned'
  OR (payload->>'ending' IS NOT DISTINCT FROM 'retired'
      AND coalesce(payload->>'seat' IN ('home', 'away'), false))
);

RESET ROLE;
