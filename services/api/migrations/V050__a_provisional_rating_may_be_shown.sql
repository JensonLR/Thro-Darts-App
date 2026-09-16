-- A provisional rating may be shown (PD-105).
--
-- V008 built the rating as a replayable projection and left `rating.published_model` empty on purpose: OD-001 was
-- open and nothing unvalidated could be shown. The founder revised the interim position on 16 September 2026 — a
-- rating may be shown **marked provisional**, as a range until it has earned a number — and the model carries what
-- that needs: how wide the range is, and how many players it is comparable with.
--
-- The rating role reads no personal data — a schema property holds that it cannot read `identity.account` at all, and
-- this keeps it so. An explanation names an opponent only after the request has switched to the read role, through the
-- same disclosure rule a roster uses; the rating tables hold player ids and numbers, never a name.

SET ROLE thro_owner;

ALTER TABLE rating.snapshot
  ADD COLUMN dispersion double precision CHECK (dispersion IS NULL OR dispersion >= 0),
  ADD COLUMN pool       int NOT NULL DEFAULT 0 CHECK (pool >= 0);

COMMENT ON COLUMN rating.snapshot.dispersion IS
  'PD-105: the 95% half-width in rating points. The display shows rating ± dispersion as a range while it is wide, '
  'and never a bare number under the threshold. NULL for a model that carries none.';
COMMENT ON COLUMN rating.snapshot.pool IS
  'PD-105: how many players this one is comparable with — the connected component of who has played whom. Two '
  'pools that never meet are two pools, and the display says the size rather than pretending one scale.';

RESET ROLE;
