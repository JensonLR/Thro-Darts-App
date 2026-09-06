package thro.engine

/**
 * The scoring engine.
 *
 * One pure, total function: `(state, command) -> outcome`. Given the same inputs it returns the
 * same output on every platform and at every time, which is what allows the server to revalidate a
 * client's claim and allows a client to score with no network at all.
 *
 * The engine deals in state transitions only. Averages, checkout rates and every other statistic
 * belong to a separate layer — which is why no floating point appears here.
 */
public object Engine {

    public fun apply(state: MatchState, command: Command): Outcome = when (command) {
        is Command.RecordVisit -> recordVisit(state, command)
    }

    private fun recordVisit(state: MatchState, cmd: Command.RecordVisit): Outcome {
        if (state.isComplete) return Outcome.Rejected(RejectionReason.MATCH_COMPLETE)
        if (cmd.player != state.thrower) return Outcome.Rejected(RejectionReason.NOT_YOUR_TURN)

        if (cmd.visitTotal < 0 || cmd.visitTotal > RuleTables.MAX_VISIT_TOTAL) {
            return Outcome.Rejected(RejectionReason.VISIT_TOTAL_OUT_OF_RANGE)
        }
        // A total inside 0..180 can still be unreachable with three darts. Checking the bound alone
        // is the single most-missed validation in X01 implementations.
        if (cmd.visitTotal in RuleTables.IMPOSSIBLE_VISIT_TOTALS) {
            return Outcome.Rejected(RejectionReason.IMPOSSIBLE_VISIT_TOTAL)
        }
        if (cmd.dartsUsed != null && cmd.dartsUsed !in 1..3) {
            return Outcome.Rejected(RejectionReason.DARTS_USED_INVALID)
        }
        if (cmd.dartsAtDouble != null && cmd.dartsAtDouble !in 0..3) {
            return Outcome.Rejected(RejectionReason.DARTS_AT_DOUBLE_INVALID)
        }
        if (cmd.dartsAtDouble != null && cmd.dartsUsed != null && cmd.dartsAtDouble > cmd.dartsUsed) {
            return Outcome.Rejected(RejectionReason.DARTS_AT_DOUBLE_INVALID)
        }

        val before = state.remaining.getValue(cmd.player)
        val left = before - cmd.visitTotal
        val checkouts = RuleTables.checkouts(state.format.outRule)

        // A double can only be attempted from a remaining that is finishable within the visit —
        // verified by enumeration to be exactly the checkout set. Claiming attempts from anywhere
        // else is not a mis-key, it is evidence that cannot have happened.
        if ((cmd.dartsAtDouble ?: 0) > 0 && before !in checkouts) {
            return Outcome.Rejected(RejectionReason.DARTS_AT_DOUBLE_INVALID)
        }

        // Bust, in order. The third condition is the one implementations drop: reaching exactly
        // zero on a number the out-rule cannot finish.
        val bust: BustReason? = when {
            left < 0 -> BustReason.BELOW_ZERO
            left == 1 && state.format.outRule == OutRule.DOUBLE -> BustReason.REMAINDER_ONE
            left == 0 && before !in checkouts -> BustReason.NOT_CHECKOUT_POSSIBLE
            else -> null
        }

        if (bust != null) {
            // The busted visit consumed three darts and contributed nothing. It is recorded, not
            // discarded: dropping it would inflate every average computed from the log.
            if (cmd.dartsUsed != null && cmd.dartsUsed != 3) {
                return Outcome.Rejected(RejectionReason.DARTS_USED_INVALID)
            }
            return Outcome.Accepted(
                state = state.copy(
                    // remaining reverts to the pre-visit total — not to a per-dart position
                    thrower = state.opponentOf(cmd.player),
                    visitsInLeg = state.visitsInLeg + 1,
                ),
                effect = Effect.BUST,
                bustReason = bust,
            )
        }

        if (left > 0) {
            // Only a leg-winning visit can have used fewer than three darts.
            if (cmd.dartsUsed != null && cmd.dartsUsed != 3) {
                return Outcome.Rejected(RejectionReason.DARTS_USED_INVALID)
            }
            return Outcome.Accepted(
                state = state.copy(
                    remaining = state.remaining + (cmd.player to left),
                    thrower = state.opponentOf(cmd.player),
                    visitsInLeg = state.visitsInLeg + 1,
                ),
                effect = Effect.SCORED,
            )
        }

        // Under double-out the winning dart is by definition a double, so a finish that claims no
        // double attempt contradicts itself.
        if (state.format.outRule == OutRule.DOUBLE &&
            cmd.dartsAtDouble != null && cmd.dartsAtDouble < 1
        ) {
            return Outcome.Rejected(RejectionReason.DARTS_AT_DOUBLE_INVALID)
        }
        return winLeg(state, cmd.player)
    }

    private fun winLeg(state: MatchState, winner: PlayerId): Outcome {
        val f = state.format
        val opponent = state.opponentOf(winner)
        val legsInSet = state.legsWonInSet + (winner to state.legsWonInSet.getValue(winner) + 1)
        val legsTotal = state.legsWonTotal + (winner to state.legsWonTotal.getValue(winner) + 1)

        val tookLegUnit = unitTaken(f.legs, legsInSet.getValue(winner), legsInSet.getValue(opponent))

        // Legs alone decide the match.
        if (f.sets == null) {
            if (tookLegUnit) {
                return complete(state, winner, legsInSet, state.setsWon, legsTotal, Effect.MATCH_WON)
            }
            return Outcome.Accepted(
                state = nextLeg(state, legsInSet, state.setsWon, legsTotal),
                effect = Effect.LEG_WON,
            )
        }

        if (!tookLegUnit) {
            return Outcome.Accepted(
                state = nextLeg(state, legsInSet, state.setsWon, legsTotal),
                effect = Effect.LEG_WON,
            )
        }

        val setsWon = state.setsWon + (winner to state.setsWon.getValue(winner) + 1)
        if (unitTaken(f.sets, setsWon.getValue(winner), setsWon.getValue(opponent))) {
            return complete(state, winner, legsInSet, setsWon, legsTotal, Effect.MATCH_WON)
        }
        return Outcome.Accepted(state = nextSet(state, setsWon, legsTotal), effect = Effect.SET_WON)
    }

    /**
     * A competitor takes the unit on reaching the required wins with the required margin, or on
     * reaching the cap where a two-clear format would otherwise continue indefinitely.
     */
    private fun unitTaken(s: Structure, mine: Int, theirs: Int): Boolean {
        if (s.cap != null && mine >= s.cap) return true
        return mine >= s.winsRequired && (mine - theirs) >= s.clearBy
    }

    private fun nextLeg(
        state: MatchState,
        legsInSet: Map<PlayerId, Int>,
        setsWon: Map<PlayerId, Int>,
        legsTotal: Map<PlayerId, Int>,
    ): MatchState {
        // Under per-leg alternation the right to start changes hands every leg, so in a best-of-9
        // the player who started leg 1 also starts the decider. Under per-set alternation the set's
        // starter opens every leg within it.
        val starter = when (state.format.alternation) {
            Alternation.PER_LEG -> state.opponentOf(state.legStarter)
            Alternation.PER_SET -> state.setStarter
        }
        return state.copy(
            remaining = mapOf(
                state.home to state.format.startingScore,
                state.away to state.format.startingScore,
            ),
            legsWonInSet = legsInSet,
            setsWon = setsWon,
            legsWonTotal = legsTotal,
            currentLeg = state.currentLeg + 1,
            legStarter = starter,
            thrower = starter,
            visitsInLeg = 0,
        )
    }

    private fun nextSet(
        state: MatchState,
        setsWon: Map<PlayerId, Int>,
        legsTotal: Map<PlayerId, Int>,
    ): MatchState {
        val starter = state.opponentOf(state.setStarter)
        return state.copy(
            remaining = mapOf(
                state.home to state.format.startingScore,
                state.away to state.format.startingScore,
            ),
            legsWonInSet = mapOf(state.home to 0, state.away to 0),
            setsWon = setsWon,
            legsWonTotal = legsTotal,
            currentSet = state.currentSet + 1,
            currentLeg = 1,
            legStarter = starter,
            setStarter = starter,
            thrower = starter,
            visitsInLeg = 0,
        )
    }

    private fun complete(
        state: MatchState,
        winner: PlayerId,
        legsInSet: Map<PlayerId, Int>,
        setsWon: Map<PlayerId, Int>,
        legsTotal: Map<PlayerId, Int>,
        effect: Effect,
    ): Outcome = Outcome.Accepted(
        state = state.copy(
            remaining = state.remaining + (winner to 0),
            legsWonInSet = legsInSet,
            setsWon = setsWon,
            legsWonTotal = legsTotal,
            thrower = null,
            winner = winner,
            visitsInLeg = state.visitsInLeg + 1,
        ),
        effect = effect,
    )
}
