// The scoring engine, Swift.
//
// One pure, total function: `(state, command) -> outcome`. Given the same inputs it returns the
// same output on every platform and at every time, which is what allows the server to revalidate a
// client's claim and allows a client to score with no network at all.
//
// The engine deals in state transitions only. Averages, checkout rates and every other statistic
// belong to a separate layer — which is why no floating point appears here.
//
// This file is a line-for-line counterpart of Engine.kt. Keeping the order of checks identical is
// not stylistic: the ORDER decides the answer in several places. A bust check moved above the
// impossible-total check would report the wrong reason, and the corpus would still pass if it only
// compared accept/reject.

public enum Engine {

    public static func apply(_ state: MatchState, _ command: Command) -> Outcome {
        switch command {
        case let .recordVisit(player, visitTotal, dartsUsed, dartsAtDouble):
            return recordVisit(state, player, visitTotal, dartsUsed, dartsAtDouble)
        }
    }

    private static func recordVisit(
        _ state: MatchState,
        _ player: PlayerId,
        _ visitTotal: Int,
        _ dartsUsed: Int?,
        _ dartsAtDouble: Int?
    ) -> Outcome {
        if state.isComplete { return .rejected(reason: .MATCH_COMPLETE) }
        if player != state.thrower { return .rejected(reason: .NOT_YOUR_TURN) }

        if visitTotal < 0 || visitTotal > RuleTables.maxVisitTotal {
            return .rejected(reason: .VISIT_TOTAL_OUT_OF_RANGE)
        }
        // A total inside 0...180 can still be unreachable with three darts. Checking the bound
        // alone is the single most-missed validation in X01 implementations.
        if RuleTables.impossibleVisitTotals.contains(visitTotal) {
            return .rejected(reason: .IMPOSSIBLE_VISIT_TOTAL)
        }
        if let d = dartsUsed, !(1...3).contains(d) {
            return .rejected(reason: .DARTS_USED_INVALID)
        }
        if let a = dartsAtDouble, !(0...3).contains(a) {
            return .rejected(reason: .DARTS_AT_DOUBLE_INVALID)
        }
        if let a = dartsAtDouble, let d = dartsUsed, a > d {
            return .rejected(reason: .DARTS_AT_DOUBLE_INVALID)
        }

        guard let before = state.remaining[player] else { return .rejected(reason: .NOT_YOUR_TURN) }
        let left = before - visitTotal
        let checkouts = RuleTables.checkouts(state.format.outRule)

        // A double can only be attempted from a remaining that is finishable within the visit —
        // verified by enumeration to be exactly the checkout set. Claiming attempts from anywhere
        // else is not a mis-key, it is evidence that cannot have happened.
        if (dartsAtDouble ?? 0) > 0 && !checkouts.contains(before) {
            return .rejected(reason: .DARTS_AT_DOUBLE_INVALID)
        }

        // Bust, in order. The third condition is the one implementations drop: reaching exactly
        // zero on a number the out-rule cannot finish.
        let bust: BustReason?
        if left < 0 {
            bust = .BELOW_ZERO
        } else if left == 1 && state.format.outRule == .double {
            bust = .REMAINDER_ONE
        } else if left == 0 && !checkouts.contains(before) {
            bust = .NOT_CHECKOUT_POSSIBLE
        } else {
            bust = nil
        }

        if let bustReason = bust {
            // The busted visit consumed three darts and contributed nothing. It is recorded, not
            // discarded: dropping it would inflate every average computed from the log.
            if let d = dartsUsed, d != 3 { return .rejected(reason: .DARTS_USED_INVALID) }
            var next = state
            // remaining reverts to the pre-visit total — not to a per-dart position
            next.thrower = state.opponentOf(player)
            next.visitsInLeg = state.visitsInLeg + 1
            return .accepted(state: next, effect: .bust, bustReason: bustReason)
        }

        if left > 0 {
            // Only a leg-winning visit can have used fewer than three darts.
            if let d = dartsUsed, d != 3 { return .rejected(reason: .DARTS_USED_INVALID) }
            var next = state
            next.remaining[player] = left
            next.thrower = state.opponentOf(player)
            next.visitsInLeg = state.visitsInLeg + 1
            return .accepted(state: next, effect: .scored, bustReason: nil)
        }

        // Under double-out the winning dart is by definition a double, so a finish that claims no
        // double attempt contradicts itself.
        if state.format.outRule == .double, let a = dartsAtDouble, a < 1 {
            return .rejected(reason: .DARTS_AT_DOUBLE_INVALID)
        }
        return winLeg(state, player)
    }

    private static func winLeg(_ state: MatchState, _ winner: PlayerId) -> Outcome {
        let f = state.format
        let opponent = state.opponentOf(winner)
        var legsInSet = state.legsWonInSet
        legsInSet[winner] = (legsInSet[winner] ?? 0) + 1
        var legsTotal = state.legsWonTotal
        legsTotal[winner] = (legsTotal[winner] ?? 0) + 1

        let tookLegUnit = unitTaken(f.legs, legsInSet[winner] ?? 0, legsInSet[opponent] ?? 0)

        // Legs alone decide the match.
        if f.sets == nil {
            if tookLegUnit {
                return complete(state, winner, legsInSet, state.setsWon, legsTotal, .match_won)
            }
            return .accepted(
                state: nextLeg(state, legsInSet, state.setsWon, legsTotal),
                effect: .leg_won,
                bustReason: nil
            )
        }

        if !tookLegUnit {
            return .accepted(
                state: nextLeg(state, legsInSet, state.setsWon, legsTotal),
                effect: .leg_won,
                bustReason: nil
            )
        }

        var setsWon = state.setsWon
        setsWon[winner] = (setsWon[winner] ?? 0) + 1
        if unitTaken(f.sets!, setsWon[winner] ?? 0, setsWon[opponent] ?? 0) {
            return complete(state, winner, legsInSet, setsWon, legsTotal, .match_won)
        }
        return .accepted(state: nextSet(state, setsWon, legsTotal), effect: .set_won, bustReason: nil)
    }

    /// A competitor takes the unit on reaching the required wins with the required margin, or on
    /// reaching the cap where a two-clear format would otherwise continue indefinitely.
    private static func unitTaken(_ s: Structure, _ mine: Int, _ theirs: Int) -> Bool {
        if let cap = s.cap, mine >= cap { return true }
        return mine >= s.winsRequired && (mine - theirs) >= s.clearBy
    }

    private static func nextLeg(
        _ state: MatchState,
        _ legsInSet: [PlayerId: Int],
        _ setsWon: [PlayerId: Int],
        _ legsTotal: [PlayerId: Int]
    ) -> MatchState {
        // Under per-leg alternation the right to start changes hands every leg, so in a best-of-9
        // the player who started leg 1 also starts the decider. Under per-set alternation the set's
        // starter opens every leg within it.
        let starter: PlayerId
        switch state.format.alternation {
        case .perLeg: starter = state.opponentOf(state.legStarter)
        case .perSet: starter = state.setStarter
        }
        var next = state
        next.remaining = [
            state.home: state.format.startingScore,
            state.away: state.format.startingScore,
        ]
        next.legsWonInSet = legsInSet
        next.setsWon = setsWon
        next.legsWonTotal = legsTotal
        next.currentLeg = state.currentLeg + 1
        next.legStarter = starter
        next.thrower = starter
        next.visitsInLeg = 0
        return next
    }

    private static func nextSet(
        _ state: MatchState,
        _ setsWon: [PlayerId: Int],
        _ legsTotal: [PlayerId: Int]
    ) -> MatchState {
        let starter = state.opponentOf(state.setStarter)
        var next = state
        next.remaining = [
            state.home: state.format.startingScore,
            state.away: state.format.startingScore,
        ]
        next.legsWonInSet = [state.home: 0, state.away: 0]
        next.setsWon = setsWon
        next.legsWonTotal = legsTotal
        next.currentSet = state.currentSet + 1
        next.currentLeg = 1
        next.legStarter = starter
        next.setStarter = starter
        next.thrower = starter
        next.visitsInLeg = 0
        return next
    }

    private static func complete(
        _ state: MatchState,
        _ winner: PlayerId,
        _ legsInSet: [PlayerId: Int],
        _ setsWon: [PlayerId: Int],
        _ legsTotal: [PlayerId: Int],
        _ effect: Effect
    ) -> Outcome {
        var next = state
        next.remaining[winner] = 0
        next.legsWonInSet = legsInSet
        next.setsWon = setsWon
        next.legsWonTotal = legsTotal
        next.thrower = nil
        next.winner = winner
        next.visitsInLeg = state.visitsInLeg + 1
        return .accepted(state: next, effect: effect, bustReason: nil)
    }
}
