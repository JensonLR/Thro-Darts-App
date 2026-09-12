-- THRØ V008 — rating snapshots.
--
-- ADR-009: rating is a versioned, replayable projection over eligible evidence. It is never an
-- incrementally mutated number, and the rating module never writes to match or trust.
--
-- The approved organiser dispute screen states "Ratings are recalculated from the corrected
-- result". An incrementally updated store cannot honour that sentence, because reversing one match
-- must ripple to every opponent downstream of it. A projection is simply recomputed.

SET ROLE thro_owner;

-- Exactly one model is published at a time. Enforced structurally rather than by convention,
-- because "a player's rating" becomes ambiguous the moment two are live.
CREATE TABLE rating.published_model (
  singleton     boolean     PRIMARY KEY DEFAULT true CHECK (singleton),
  model_id      text        NOT NULL UNIQUE,
  model_version text        NOT NULL,
  scale_epoch   int         NOT NULL,
  published_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  published_by  uuid        NOT NULL
);

COMMENT ON TABLE rating.published_model IS
  'At most one row, ever. OD-001 is open, so at launch this table is EMPTY: every player is '
  'provisional, candidates run in shadow, and no rating integer is shown to anyone. That is the '
  'truthful state of the world, not a placeholder.';

CREATE TABLE rating.snapshot (
  player_id         uuid        NOT NULL,
  model_id          text        NOT NULL,
  model_version     text        NOT NULL,
  parameter_hash    text        NOT NULL,
  scale_epoch       int         NOT NULL,
  -- The evidence watermark is a PAIR. global_seq alone is unsafe to order by: it is assigned at
  -- insert, not commit, so a reader above a high-water mark silently skips rows from transactions
  -- that started earlier and committed later. Per-device sequences are not comparable at all.
  as_of_commit_xid  xid8        NOT NULL,
  as_of_global_seq  bigint      NOT NULL,
  rating            double precision,      -- NULL while provisional: an em dash, not a guess
  confidence        double precision NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  matches_counted   int         NOT NULL CHECK (matches_counted >= 0),
  computed_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  published         boolean     NOT NULL DEFAULT false,
  -- Null unless published, so the foreign key below constrains only published rows.
  published_model_id text GENERATED ALWAYS AS (CASE WHEN published THEN model_id END) STORED,
  PRIMARY KEY (player_id, model_id, model_version, as_of_commit_xid, as_of_global_seq),
  -- A published snapshot must belong to the one published model. Nothing else can be shown.
  FOREIGN KEY (published_model_id) REFERENCES rating.published_model(model_id),
  -- A provisional rating has no number. A published one must have both a number and a scale.
  CONSTRAINT snapshot_published_has_a_rating CHECK (NOT published OR rating IS NOT NULL)
);

CREATE INDEX snapshot_by_player ON rating.snapshot (player_id, computed_at DESC);
CREATE INDEX snapshot_published ON rating.snapshot (player_id) WHERE published;

-- The visible ledger. Any adjustment that is not a match — a recomputation, a correction, decay,
-- an eligibility change — appears as its own line and is never absorbed into a match's delta.
CREATE TABLE rating.ledger (
  ledger_id        uuid        PRIMARY KEY,
  player_id        uuid        NOT NULL,
  model_id         text        NOT NULL,
  at_commit_xid    xid8        NOT NULL,
  at_global_seq    bigint      NOT NULL,
  cause            text        NOT NULL
                   CHECK (cause IN ('match','recomputation','correction','decay','eligibility_change')),
  match_id         uuid,
  delta            double precision NOT NULL,
  -- Frozen at rating time, never reconstructed on read: ratings drift, so a regenerated
  -- explanation would quote a past opponent at their present rating and be false.
  explanation      jsonb,
  CONSTRAINT ledger_match_line_names_its_match
    CHECK ((cause = 'match') = (match_id IS NOT NULL))
);

CREATE INDEX ledger_by_player ON rating.ledger (player_id, at_commit_xid, at_global_seq);

-- rating is a pure downstream consumer: it never writes to match or trust, and that one-way
-- dependency is what makes it safely re-runnable.
GRANT SELECT, INSERT, UPDATE, DELETE ON rating.snapshot, rating.ledger TO app_rating;
GRANT SELECT, INSERT, UPDATE, DELETE ON rating.published_model TO app_rating;
GRANT SELECT ON rating.snapshot TO app_read;
REVOKE ALL ON rating.snapshot, rating.ledger, rating.published_model FROM app_match, app_trust;

RESET ROLE;
