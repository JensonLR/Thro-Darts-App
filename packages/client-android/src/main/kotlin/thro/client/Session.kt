package thro.client

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import thro.engine.Command
import thro.engine.Engine
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId
import thro.engine.RejectionReason
import thro.journal.Journal
import thro.journal.MatchId
import thro.journal.NewMatch
import thro.journal.Seat

// A match being scored on this phone (PD-083).
//
// **Engine, then journal, then screen — never another order.** This is the iOS session's rule and it is not
// a style preference. The engine decides whether a visit is legal, because it is the only thing that knows;
// the journal is written next, because a visit the player can see and the phone has not recorded is a visit
// that vanishes when the battery does; and the screen is updated last, from what was actually written. Doing
// it in any other order produces a scoreboard that is ahead of the record, and the record is the product.
//
// The state is the engine's own, not a copy: `MatchState` carries the remainders, whose throw it is, the
// legs, and whether the match is decided. There is deliberately no second model of a leg here.

/// What the screen was told about the last thing that happened.
public sealed interface ThroMark {
    public data class Scored(val total: Int) : ThroMark
    public data class Bust(val total: Int) : ThroMark
    public data class Refused(val reason: RejectionReason) : ThroMark
    public data object LegWon : ThroMark
    public data object MatchWon : ThroMark
    public data class Trouble(val message: String) : ThroMark
}

public class ThroSession internal constructor(
    private val journal: Journal,
    public val matchId: MatchId,
    public val homeName: String,
    public val awayName: String,
    state: MatchState,
) {
    /// **Compose state, and the order is still the order.**
    ///
    /// The first version kept these as plain properties and had the screen bump a counter to force a
    /// redraw, on the reasoning that observable state would invite a screen that updates before the write.
    /// That was wrong twice over. It does not work — Compose skipped the side that reads the session,
    /// because its arguments had not changed, so two visits went into the journal and neither reached the
    /// screen — and the reasoning was confused: what keeps the order is the *code below*, which assigns
    /// this only after `journal.append` has returned. Observability has nothing to do with it.
    public var state: MatchState by mutableStateOf(state)
        private set

    /// The last thing that happened, for the screen to say out loud. Null before anything has.
    public var mark: ThroMark? by mutableStateOf(null)
        private set

    public companion object {
        /// Starts a match: the journal creates the record, and the record's own initial state is what the
        /// engine is handed. Not a state built here — the journal's row is the truth about what the match
        /// IS, and building a second one would let the two disagree about a rule.
        public fun start(journal: Journal, home: String, away: String, legsTarget: Int = 5): ThroSession {
            val record = journal.createMatch(NewMatch(homeName = home, awayName = away, legsTarget = legsTarget))
            return ThroSession(journal, record.id, record.homeName, record.awayName, record.initialState)
        }
    }

    public val throwerSeat: Seat?
        get() = state.thrower?.let { if (it == state.home) Seat.HOME else Seat.AWAY }

    public fun name(seat: Seat): String = if (seat == Seat.HOME) homeName else awayName
    public fun remaining(seat: Seat): Int =
        state.remaining[if (seat == Seat.HOME) state.home else state.away] ?: 0
    public fun legs(seat: Seat): Int =
        state.legsWonTotal[if (seat == Seat.HOME) state.home else state.away] ?: 0

    /// One visit. The engine first.
    public fun enter(total: Int) {
        val thrower: PlayerId = state.thrower ?: return
        val command = Command.RecordVisit(player = thrower, visitTotal = total)
        when (val outcome = Engine.apply(state, command)) {
            is Outcome.Rejected -> {
                // A rejection is part of the contract and not an exception: nothing is written and the
                // screen says why. This is the branch that keeps an impossible total off the record.
                mark = ThroMark.Refused(outcome.reason)
            }
            is Outcome.Accepted -> {
                // Written before it is shown. If this throws, the screen must not move.
                runCatching { journal.append(command, matchId) }
                    .onFailure { mark = ThroMark.Trouble(it.message ?: "not saved, so not recorded"); return }
                state = outcome.state
                mark = when {
                    state.winner != null -> ThroMark.MatchWon
                    outcome.bustReason != null -> ThroMark.Bust(total)
                    // A leg turns over when the remainders go back to the starting score.
                    state.visitsInLeg == 0 -> ThroMark.LegWon
                    else -> ThroMark.Scored(total)
                }
            }
        }
    }

    /// Takes the last visit back. **A retraction, not a delete**: the journal keeps what was written and
    /// records that it no longer stands, which is ADR-006's whole shape and why the screen is rebuilt by
    /// replaying rather than by subtracting.
    public fun undo() {
        runCatching {
            journal.retractLastVisit(matchId)
            state = journal.replay(matchId)
        }.onFailure { mark = ThroMark.Trouble(it.message ?: "nothing to take back") }
            .onSuccess { mark = null }
    }
}
