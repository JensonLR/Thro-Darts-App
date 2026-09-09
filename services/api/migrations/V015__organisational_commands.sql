-- THRØ V015 — receipts for organisational commands (ADR-017).
--
-- Organisational state — a team's name, a fixture's date — is a server-authoritative row with a
-- version. A command that changes one carries the version its author last saw; a stale version is
-- REFUSED with the current row, never merged and never overwritten. That rule is enforced by the
-- triggers V014 put on the rows. What was missing is the other half of ADR-006's discipline applied
-- to this kind of state: a command replayed after a dropped connection must return what it
-- returned the first time, including a refusal, and must never be applied twice. Hence a receipt,
-- written in the same transaction as the change.
--
-- Deliberately a separate table from evidence.command_receipt: that one is keyed to a match and
-- lives in the append-only evidence schema, and an organisational command has no match.

SET ROLE thro_owner;

CREATE TABLE competition.command_receipt (
  device_id         uuid        NOT NULL,
  client_command_id uuid        NOT NULL,
  command_type      text        NOT NULL,
  outcome           text        NOT NULL CHECK (outcome IN ('applied','refused','stale')),
  reason_code       text,
  response_body     jsonb       NOT NULL,
  received_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (device_id, client_command_id)
);

COMMENT ON TABLE competition.command_receipt IS
  'Idempotency for organisational commands. A replay returns response_body verbatim — including a '
  'refusal or a stale-version response — and applies nothing. Written in the same transaction as '
  'the change it records, or the change is not made.';

GRANT SELECT, INSERT ON competition.command_receipt TO app_competition;
GRANT SELECT ON competition.command_receipt TO app_read;
REVOKE UPDATE, DELETE, TRUNCATE ON competition.command_receipt
  FROM app_match, app_trust, app_rating, app_read, app_competition;

RESET ROLE;
