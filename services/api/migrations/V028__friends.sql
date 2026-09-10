-- THRØ V028 — friends, by consent and in person.
--
-- A friend is somebody you chose, both ways. There is no directory to search — a search is how a
-- stranger finds a child — so a friendship starts with a CODE: one person makes one, says it or
-- shows it to the other across a table, and the other enters it. The code is short-lived, single
-- use, and says nothing about who made it until it is used. Only an account that has said it is an
-- adult may make or use one; an account whose age is unknown is treated as the most restrictive
-- case, as identity.account promises, and a minor's friends are a guardian's business (OD-010).
--
-- A friendship ends by either side, and its ending is recorded, not deleted.

SET ROLE thro_owner;

CREATE TABLE identity.friend_invite (
  code        text        PRIMARY KEY CHECK (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  account_id  uuid        NOT NULL REFERENCES identity.account(account_id),
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at  timestamptz NOT NULL,
  used_by     uuid        REFERENCES identity.account(account_id),
  used_at     timestamptz,
  CONSTRAINT invite_use_is_complete CHECK ((used_by IS NULL) = (used_at IS NULL)),
  CONSTRAINT invite_lasts_a_while CHECK (expires_at > created_at AND expires_at <= created_at + interval '30 days')
);
CREATE INDEX friend_invite_by_account ON identity.friend_invite (account_id);

CREATE TABLE identity.friendship (
  friendship_id uuid      PRIMARY KEY,
  -- Ordered, so one pair is one row whichever side made the invite.
  account_a   uuid        NOT NULL REFERENCES identity.account(account_id),
  account_b   uuid        NOT NULL REFERENCES identity.account(account_id),
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  invite_code text        REFERENCES identity.friend_invite(code),
  ended_at    timestamptz,
  ended_by    uuid        REFERENCES identity.account(account_id),
  CONSTRAINT friendship_is_between_two_people CHECK (account_a < account_b),
  CONSTRAINT friendship_end_is_attributed CHECK ((ended_at IS NULL) = (ended_by IS NULL))
);
CREATE UNIQUE INDEX friendship_one_live_per_pair ON identity.friendship (account_a, account_b) WHERE ended_at IS NULL;
CREATE INDEX friendship_by_a ON identity.friendship (account_a) WHERE ended_at IS NULL;
CREATE INDEX friendship_by_b ON identity.friendship (account_b) WHERE ended_at IS NULL;

-- Only an adult makes or uses a code. Enforced here, so no route can forget it.
CREATE FUNCTION identity.friend_actor_is_adult() RETURNS trigger AS $$
DECLARE band text;
BEGIN
  SELECT age_band INTO band FROM identity.account WHERE account_id = NEW.account_id AND deleted_at IS NULL;
  IF band IS DISTINCT FROM 'adult' THEN
    RAISE EXCEPTION 'friends need an account that has said it is an adult (account % is %)', NEW.account_id, coalesce(band, 'gone');
  END IF;
  IF NEW.used_by IS NOT NULL THEN
    SELECT age_band INTO band FROM identity.account WHERE account_id = NEW.used_by AND deleted_at IS NULL;
    IF band IS DISTINCT FROM 'adult' THEN
      RAISE EXCEPTION 'friends need an account that has said it is an adult (account % is %)', NEW.used_by, coalesce(band, 'gone');
    END IF;
    IF NEW.used_by = NEW.account_id THEN RAISE EXCEPTION 'a code is for somebody else'; END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER friend_actor_is_adult BEFORE INSERT OR UPDATE ON identity.friend_invite
  FOR EACH ROW EXECUTE FUNCTION identity.friend_actor_is_adult();

-- A code is used once, and an ended friendship stays ended.
CREATE FUNCTION identity.friend_rows_are_kept() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'friend_invite' THEN
    IF OLD.used_at IS NOT NULL THEN RAISE EXCEPTION 'a friend code is used once'; END IF;
    IF NEW.account_id <> OLD.account_id OR NEW.code <> OLD.code OR NEW.expires_at <> OLD.expires_at THEN
      RAISE EXCEPTION 'a friend code is not rewritten';
    END IF;
  ELSE
    IF OLD.ended_at IS NOT NULL THEN RAISE EXCEPTION 'an ended friendship stays ended'; END IF;
    IF NEW.account_a <> OLD.account_a OR NEW.account_b <> OLD.account_b THEN RAISE EXCEPTION 'a friendship is between the two it was between'; END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER friend_invite_is_kept BEFORE UPDATE ON identity.friend_invite
  FOR EACH ROW EXECUTE FUNCTION identity.friend_rows_are_kept();
CREATE TRIGGER friendship_is_kept BEFORE UPDATE ON identity.friendship
  FOR EACH ROW EXECUTE FUNCTION identity.friend_rows_are_kept();

GRANT SELECT ON identity.friend_invite, identity.friendship TO app_read, app_competition;
GRANT INSERT ON identity.friend_invite, identity.friendship TO app_competition;
GRANT UPDATE (used_by, used_at) ON identity.friend_invite TO app_competition;
GRANT UPDATE (ended_at, ended_by) ON identity.friendship TO app_competition;

-- An account says its own age band once it is asked: adult, self-declared, is what unlocks
-- friends. The column and its check exist since V011; the application may now write them.
GRANT UPDATE (age_band, age_assurance) ON identity.account TO app_competition;

RESET ROLE;
