package thro.client

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import thro.engine.BustReason
import thro.engine.BustRule
import thro.engine.Checkout
import thro.engine.Command
import thro.engine.Dart
import thro.engine.Darts
import thro.engine.Effect
import thro.engine.Engine
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId
import thro.engine.RejectionReason
import thro.journal.Journal
import thro.journal.MatchId
import thro.journal.MatchRecord
import thro.journal.NewMatch
import thro.journal.Seat
import thro.journal.Standing

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
///
/// **Read from the engine's `effect`, never inferred.** The first version called a leg won when the leg's visit
/// count went back to zero, which is also what a set win does — so a set came out as "Leg". The engine says
/// which of the five things a visit did, and the words follow what it said.
public sealed interface ThroMark {
    public data class Scored(val total: Int) : ThroMark

    /// A bust, with what the screen needs to say it honestly: the score the ENGINE left the thrower on (under
    /// keep-scored darts that is not the score the visit began on), the reason, and — when the visit was entered
    /// as darts — which dart did it.
    public data class Bust(
        val seat: Seat,
        val total: Int,
        val restored: Int,
        val reason: BustReason? = null,
        val bustAt: Int? = null,
        val darts: List<Dart>? = null,
        /// What stood before the busting dart, under keep-scored darts. Null under the standard rule.
        val kept: Int? = null,
    ) : ThroMark

    /// `shown` is what the player entered — the total typed, or what the darts add up to — for the words.
    public data class Refused(val reason: RejectionReason, val shown: Int = 0) : ThroMark
    public data class LegWon(val seat: Seat) : ThroMark
    public data class SetWon(val seat: Seat) : ThroMark
    public data object MatchWon : ThroMark

    /// A dart keyed after the visit was already finished or bust. Not taken; this says why.
    public data object AlreadyDecided : ThroMark
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

    /// Who stands behind this result, read back from the journal after every change (PD-011).
    public var standing: Standing by mutableStateOf(journal.standing(matchId))
        private set

    /// The last thing that happened, for the screen to say out loud. Null before anything has.
    public var mark: ThroMark? by mutableStateOf(null)
        private set

    public companion object {
        /// Starts a match: the journal creates the record, and the record's own initial state is what the
        /// engine is handed. Not a state built here — the journal's row is the truth about what the match
        /// IS, and building a second one would let the two disagree about a rule.
        public fun start(journal: Journal, match: NewMatch): ThroSession {
            val record = journal.createMatch(match)
            return ThroSession(journal, record.id, record.homeName, record.awayName, record.initialState)
        }

        public fun start(journal: Journal, home: String, away: String, legsTarget: Int = 5): ThroSession =
            start(journal, NewMatch(homeName = home, awayName = away, legsTarget = legsTarget))

        /// Picks a match back up, by **replaying it**. Not by loading a saved score — there is no saved
        /// score. The journal holds what was thrown and the engine works out where that leaves the match,
        /// which is the same path a fresh visit takes and therefore cannot disagree with it.
        public fun resume(journal: Journal, record: MatchRecord): ThroSession =
            ThroSession(journal, record.id, record.homeName, record.awayName, journal.replay(record.id))

        /// The match to offer back, or null. The most recently started one that nobody has won and nobody
        /// has ended.
        ///
        /// **Every candidate is replayed to find out**, because "unfinished" is not a column: a match is
        /// over when the engine says the visits add up to a win, and asking anything else would be a second
        /// opinion about the rules. That is O(matches) on launch and fine at the scale of one phone's
        /// evening; it is the first thing to reconsider if a season's worth ever piles up.
        public fun resumable(journal: Journal): MatchRecord? =
            journal.matches(archived = false).firstOrNull { record ->
                runCatching {
                    journal.ending(record.id) == null && journal.replay(record.id).winner == null
                }.getOrDefault(false)
            }
    }

    public val throwerSeat: Seat?
        get() = state.thrower?.let { if (it == state.home) Seat.HOME else Seat.AWAY }

    public fun name(seat: Seat): String = if (seat == Seat.HOME) homeName else awayName
    public fun remaining(seat: Seat): Int =
        state.remaining[if (seat == Seat.HOME) state.home else state.away] ?: 0
    public fun legs(seat: Seat): Int =
        state.legsWonTotal[if (seat == Seat.HOME) state.home else state.away] ?: 0

    public val format: MatchFormat get() = state.format
    public val bustRule: BustRule get() = state.format.bustRule

    // MARK: the darts in hand (OD-023)

    /// The darts entered so far this visit, in order. Local to the screen until Enter, like typed digits: nothing
    /// is written until the engine has read the whole visit.
    public var darts: List<Dart> by mutableStateOf(emptyList())
        private set

    /// What the darts so far have done, **read by the engine**. Null with nothing entered.
    ///
    /// Everything the screen says mid-visit — what is left, whether the visit is already decided, which route is
    /// still on — comes from this one reading, so it cannot disagree with what the engine records at Enter. A
    /// screen that worked it out for itself would be a second rulebook.
    public val throwerReading: Darts.Reading?
        get() {
            val player = state.thrower ?: return null
            if (darts.isEmpty()) return null
            return Darts.read(
                before = state.remaining[player] ?: 0, darts = darts, outRule = format.outRule,
                inRule = format.inRule, opened = state.opened[player] ?: true,
            )
        }

    /// What the thrower has left after the darts so far: the number a player checks as each dart lands.
    public val throwerLeft: Int?
        get() {
            val seat = throwerSeat ?: return null
            return throwerReading?.left ?: remaining(seat)
        }

    public val dartsLeftInHand: Int get() = throwerReading?.dartsLeft ?: Darts.HAND

    /// Whether the thrower still has to open. Nothing counts until they do.
    public val throwerMustOpen: Boolean
        get() {
            val player = state.thrower ?: return false
            return format.inRule.requiresOpening && !(throwerReading?.opened ?: state.opened[player] ?: true)
        }

    /// Whether a finish is on with the darts in hand — not "whether the score is under 171". After T20 from 100
    /// the thrower is on 40 with two darts; after two darts that leave 60, one dart cannot finish it.
    public val throwerOnAFinish: Boolean
        get() {
            val left = throwerLeft ?: return false
            if (throwerMustOpen || throwerReading?.settled != null) return false
            return Checkout.isPossible(left, dartsLeftInHand, format.outRule)
        }

    /// The route with the darts in hand, from the engine's one table. Empty when no finish is on — never a
    /// three-dart route for a player holding one dart.
    public val throwerRoute: List<String>
        get() {
            if (!throwerOnAFinish) return emptyList()
            val left = throwerLeft ?: return emptyList()
            return Checkout.route(left, dartsLeftInHand, format.outRule) ?: emptyList()
        }

    /// Whether the visit in hand is already finished or bust, so no further dart was thrown.
    public val visitDecided: Boolean
        get() = throwerReading?.settled.let { it != null && it != Darts.Settled.SCORED }

    /// Whether the darts may go to the engine: the hand is spent, or the visit is settled. A two-dart entry that
    /// neither finishes nor busts is a visit the engine refuses, and a refusal nobody can act on is a dead end.
    public val dartsMayBeEntered: Boolean get() = throwerReading?.settled != null

    /// A dart lands. **Refused once the visit is decided**: a dart after a checkout was never thrown, and taking
    /// it would turn the checkout into a bust on a stray tap — the costliest mis-key there is. The keypad closes
    /// its sectors too; this is the rule behind that.
    public fun dart(dart: Dart) {
        if (state.isComplete || state.thrower == null) return
        if (visitDecided || darts.size >= Darts.HAND) { mark = ThroMark.AlreadyDecided; return }
        mark = null
        darts = darts + dart
    }

    /// Takes back the dart at [index] and every dart after it. A player pointing at the middle dart means that
    /// one was wrong, and the one after it was entered on top of a wrong number.
    public fun takeBackDarts(from: Int) {
        if (from < 0 || from >= darts.size) return
        mark = null
        darts = darts.take(from)
    }

    public fun clearDarts() {
        darts = emptyList()
    }

    /// Puts half-entered darts back after the screen was rebuilt. Only onto an empty hand, and never more than a
    /// hand holds.
    public fun restoreDarts(restored: List<Dart>) {
        if (darts.isEmpty() && !state.isComplete) darts = restored.take(Darts.HAND)
    }

    /// Commits the darts in hand. The engine derives the total, the bust and where it happened, the darts used and
    /// the darts at a double — so the player is never asked what they have already shown.
    public fun enterDarts() {
        val player = state.thrower ?: return
        if (darts.isEmpty() || !dartsMayBeEntered) return
        submit(Command.RecordDarts(player = player, darts = darts), shown = darts.sumOf { it.value })
    }

    /// PD-001's two questions, asked when they apply and never otherwise — the same two iOS asks. A total
    /// cannot say how many darts went at a double, and without the answer every checkout percentage from
    /// an Android match was unknown. Darts at a double is asked on every visit that BEGAN on a finish,
    /// finished or not; darts used only on the visit that wins the leg, the one whose count is ambiguous.
    public sealed interface Prompt {
        public data class DartsUsed(val total: Int) : Prompt
        public data class DartsAtDouble(val total: Int, val dartsUsed: Int?, val finished: Boolean) : Prompt

        public val options: List<Int>
            get() = when (this) {
                is DartsUsed -> listOf(1, 2, 3)
                is DartsAtDouble -> if (!finished) listOf(0, 1, 2, 3) else (1..3).filter { dartsUsed == null || it <= dartsUsed }
            }
    }

    public var prompt: Prompt? by mutableStateOf(null)
        private set

    /// One visit, as a total. When it began on a finish the questions come first; otherwise the engine.
    public fun enter(total: Int) {
        val player = state.thrower ?: return
        val before = state.remaining[player] ?: return
        val openedAlready = state.opened[player] ?: true
        val onAFinish = openedAlready && before in thro.engine.RuleTables.checkouts(state.format.outRule)
        prompt = when {
            onAFinish && before - total == 0 -> Prompt.DartsUsed(total)
            onAFinish -> Prompt.DartsAtDouble(total, null, finished = false)
            else -> { submit(Command.RecordVisit(player = player, visitTotal = total), shown = total); null }
        }
    }

    /// Answers the question on screen. Null is "not sure", recorded as unknown and never as zero.
    public fun answer(value: Int?) {
        val player = state.thrower ?: return
        when (val p = prompt ?: return) {
            is Prompt.DartsUsed -> prompt = Prompt.DartsAtDouble(p.total, value, finished = true)
            is Prompt.DartsAtDouble -> {
                prompt = null
                submit(Command.RecordVisit(player, p.total, dartsUsed = p.dartsUsed, dartsAtDouble = value), shown = p.total)
            }
        }
    }

    /// Puts the question away. Nothing was written.
    public fun cancelPrompt() { prompt = null }

    private fun submit(command: Command, shown: Int) {
        val thrower: PlayerId = state.thrower ?: return
        val seat = Seat.of(thrower) ?: return
        when (val outcome = Engine.apply(state, command)) {
            is Outcome.Rejected -> {
                // A rejection is part of the contract and not an exception: nothing is written and the
                // screen says why. This is the branch that keeps an impossible total off the record.
                mark = ThroMark.Refused(outcome.reason, shown)
            }
            is Outcome.Accepted -> {
                // Written before it is shown, with the engine's reading beside the darts — the journal stores
                // what the engine made of them and does not work it out again. If this throws, the screen must
                // not move.
                runCatching { journal.append(command, matchId, reading = outcome.reading) }
                    .onFailure { mark = ThroMark.Trouble(it.message ?: "not saved, so not recorded"); return }
                state = outcome.state
                darts = emptyList()
                // A visit after an attestation makes that attestation stale, and the journal knows it. The
                // label is read back rather than kept, so it cannot go on claiming an agreement nobody gave
                // to this version of the result.
                standing = journal.standing(matchId)
                val reading = outcome.reading
                mark = when (outcome.effect) {
                    Effect.MATCH_WON -> ThroMark.MatchWon
                    Effect.SET_WON -> ThroMark.SetWon(seat)
                    Effect.LEG_WON -> ThroMark.LegWon(seat)
                    // The score from the engine's state, not the one the visit began on: under keep-scored darts
                    // the darts before the bust stand.
                    Effect.BUST -> ThroMark.Bust(
                        seat = seat,
                        total = reading?.visitTotal ?: shown,
                        restored = state.remaining[thrower] ?: 0,
                        reason = outcome.bustReason,
                        bustAt = reading?.bustAt,
                        darts = reading?.darts,
                        kept = if (bustRule == BustRule.KEEP_SCORED_DARTS) reading?.scored else null,
                    )
                    Effect.SCORED -> ThroMark.Scored(reading?.visitTotal ?: shown)
                }
            }
        }
    }

    /// One competitor says whether they accept the result (PD-011).
    ///
    /// Written to the journal like everything else, and the label is then **read back** rather than
    /// assumed — the journal decides whether an agreement still describes what is recorded, and a screen
    /// that remembered its own answer would go on claiming an agreement a later visit had overtaken.
    public fun attest(seat: Seat, agrees: Boolean) {
        runCatching {
            journal.attest(matchId, seat, agrees)
            standing = journal.standing(matchId)
        }.onFailure { mark = ThroMark.Trouble(it.message ?: "not recorded") }
    }

    /// Whether there is a result for anybody to stand behind. An abandoned match has none (PD-016), so
    /// there is nothing to confirm and nothing to dispute.
    public val hasResult: Boolean get() = state.winner != null

    /// Takes the last visit back. **A retraction, not a delete**: the journal keeps what was written and
    /// records that it no longer stands, which is ADR-006's whole shape and why the screen is rebuilt by
    /// replaying rather than by subtracting.
    public fun undo() {
        runCatching {
            journal.retractLastVisit(matchId)
            state = journal.replay(matchId)
            standing = journal.standing(matchId)
            darts = emptyList()
        }.onFailure { mark = ThroMark.Trouble(it.message ?: "nothing to take back") }
            .onSuccess { mark = null }
    }
}
