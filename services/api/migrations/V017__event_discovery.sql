-- THRØ V017 — what discovery needs to answer "what can I play next?" honestly.
--
-- Two facts an event must state before it can be discovered as something to enter: when entries
-- close, and how many places there are. Without the first, "closing soon" is a guess; without the
-- second, "spots remaining" is a lie. Both are nullable — an organiser who has not said is shown
-- as not having said, never as unlimited.
--
-- Entry fees are deliberately absent: money is OD-009, and a discovery card that quotes a fee THRØ
-- cannot take is a promise the product cannot keep yet.

SET ROLE thro_owner;

ALTER TABLE competition.event
  ADD COLUMN entries_close_at timestamptz,
  ADD COLUMN capacity int CHECK (capacity IS NULL OR capacity > 0),
  ADD CONSTRAINT event_entries_close_before_it_starts
    CHECK (entries_close_at IS NULL OR entries_close_at <= starts_at);

COMMENT ON COLUMN competition.event.capacity IS
  'Places available. NULL means the organiser has not said, which discovery shows as such — never as unlimited.';

RESET ROLE;
