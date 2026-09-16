-- A screen signs in by the phone that holds the account (PD-114).
--
-- The web had one way in: a passkey, which most people have never made and which the site could not explain. The
-- phone already holds the account. So a screen asks THRØ for a short code, the person types it into the app they are
-- signed in on, and the app's word opens a session for that screen — a session family of its own, on the screen's
-- device id, bound to the credential the phone signed in with, revocable like any other.
--
-- A code is six characters from an alphabet with no look-alikes, lives five minutes, is spent once, and is never a
-- secret worth stealing: approving it needs a signed-in phone, and the session it opens goes only to the device that
-- asked for it (the claim names the device id the request named).

SET ROLE thro_owner;

CREATE TABLE identity.device_link (
  link_id       uuid        PRIMARY KEY,
  code          text        NOT NULL,
  device_id     uuid        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at    timestamptz NOT NULL,
  approved_account_id    uuid REFERENCES identity.account(account_id),
  approved_credential_id uuid REFERENCES identity.credential(credential_id),
  approved_at   timestamptz,
  claimed_at    timestamptz,
  CONSTRAINT device_link_code_shape CHECK (code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'),
  CONSTRAINT device_link_approval_is_whole
    CHECK ((approved_account_id IS NULL) = (approved_at IS NULL) AND (approved_account_id IS NULL) = (approved_credential_id IS NULL)),
  CONSTRAINT device_link_claimed_after_approval CHECK (claimed_at IS NULL OR approved_at IS NOT NULL)
);

-- One live code at a time: a code that has not expired and has not been claimed is unique among those.
CREATE UNIQUE INDEX device_link_live_code ON identity.device_link (code) WHERE claimed_at IS NULL;
CREATE INDEX device_link_expiry ON identity.device_link (expires_at);

COMMENT ON TABLE identity.device_link IS
  'PD-114: a short code a screen shows and a signed-in phone approves, opening a session for the screen. Spent once; expired rows are swept.';

GRANT SELECT, INSERT, UPDATE, DELETE ON identity.device_link TO app_competition;

RESET ROLE;
