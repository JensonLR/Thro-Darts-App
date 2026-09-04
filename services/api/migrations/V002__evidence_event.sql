-- THRØ V002 — the competitive event log.
--
-- Keyed by (match_id, device_id, device_seq). A match has TWO independent authors and the
-- difference between their accounts is the product's most important signal, so the uniqueness key
-- must permit both devices to write their own gapless sequence. An earlier design keyed on
-- (stream_id, stream_seq) and rejected the second device outright.

CREATE TABLE evidence.event (
  event_id          uuid        PRIMARY KEY,
  match_id          uuid        NOT NULL,
  device_id         uuid        NOT NULL,
  device_seq        bigint      NOT NULL CHECK (device_seq > 0),
  commit_xid        xid8        NOT NULL DEFAULT pg_current_xact_id(),
  global_seq        bigint      GENERATED ALWAYS AS IDENTITY,
  event_type        text        NOT NULL,
  schema_version    int         NOT NULL CHECK (schema_version > 0),
  rules_version     text,
  engine_version    text,
  correlation_id    uuid        NOT NULL,
  actor_id          uuid        NOT NULL,
  actor_role        text        NOT NULL
                    CHECK (actor_role IN ('participant','official','venue_scorer','system')),
  occurred_at       timestamptz NOT NULL,          -- device clock: EVIDENCE ONLY
  occurred_tz       text        NOT NULL,          -- IANA zone id, kept beside the instant
  received_at       timestamptz NOT NULL DEFAULT clock_timestamp(),   -- arrival, NOT order
  corrects_event_id uuid        REFERENCES evidence.event(event_id),
  payload           jsonb       NOT NULL,
  CONSTRAINT event_device_stream_unique UNIQUE (match_id, device_id, device_seq)
);

-- Cross-device order is the PAIR (commit_xid, global_seq). global_seq alone is unsafe: it is
-- assigned at insert, not commit, so a reader polling above a high-water mark silently skips rows
-- from transactions that started earlier and committed later.
CREATE INDEX event_commit_order ON evidence.event (commit_xid, global_seq);
CREATE INDEX event_match        ON evidence.event (match_id, commit_xid, global_seq);
CREATE INDEX event_corrects     ON evidence.event (corrects_event_id) WHERE corrects_event_id IS NOT NULL;

-- Idempotency. Written in the SAME transaction as the append: a crash between two transactions
-- either double-applies a visit or loses the receipt, and both corrupt a match.
CREATE TABLE evidence.command_receipt (
  device_id         uuid  NOT NULL,
  client_command_id uuid  NOT NULL,
  match_id          uuid  NOT NULL,
  outcome           text  NOT NULL CHECK (outcome IN ('accepted','rejected')),
  reason_code       text,
  resulting_event_ids uuid[] NOT NULL DEFAULT '{}',
  response_body     jsonb NOT NULL,
  received_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (device_id, client_command_id)
);

GRANT SELECT, INSERT ON evidence.event, evidence.command_receipt
  TO app_match, app_trust, app_rating, app_read;
REVOKE UPDATE, DELETE, TRUNCATE ON evidence.event, evidence.command_receipt
  FROM app_match, app_trust, app_rating, app_read;
