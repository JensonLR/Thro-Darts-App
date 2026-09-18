-- A pair reads in the order it was typed (PD-133).
--
-- `competition.pair` has always normalised its two halves so that (a, b) and (b, a) are the same row and cannot both
-- exist: `CHECK (player_a < player_b)` plus `UNIQUE (player_a, player_b)`, compared as uuids. That is right, and it
-- stays. It is about *identity* — whether two entries are the same pair — and it is what stops a night holding the
-- same two people twice.
--
-- What it was also deciding, silently, was *presentation*. The one SQL that names a competitor reads `player_a` then
-- `player_b`, so "Little Dave & Big Dave" came out in whichever order two random uuids happened to sort in, and came
-- out differently on another night for the same two people. The organiser typed an order and THRØ ignored it.
--
-- So: one nullable column carrying which half was typed first. Identity stays normalised; order is display only, and
-- the two never argue because this column can only ever be one of the pair's own two players. Null means a pair made
-- before this migration, and those read as they always did — there is nothing to recover, because the order was never
-- written down.

SET ROLE thro_owner;

ALTER TABLE competition.pair
  ADD COLUMN typed_first uuid REFERENCES competition.player(player_id),
  ADD CONSTRAINT pair_typed_first_is_one_of_its_own_halves
    CHECK (typed_first IS NULL OR typed_first IN (player_a, player_b));

COMMENT ON COLUMN competition.pair.typed_first IS
  'Which half the organiser or the entering player named first. Display order only: identity is player_a/player_b, '
  'normalised by uuid. Null on a pair made before V057, which reads in the normalised order as it always did.';

RESET ROLE;
