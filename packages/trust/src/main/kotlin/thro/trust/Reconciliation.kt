package thro.trust

import java.util.UUID
import thro.engine.Command
import thro.engine.Effect
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId

/**
 * One visit as a single device recorded it.
 *
 * [correctsSeq] is what makes this more than a list of numbers: a scorer who mis-keys a visit and
 * fixes it leaves *two* rows in that device's journal for one throw. The correction supersedes the
 * original rather than deleting it, because deleting evidence is never an option.
 */
public data class AccountedVisit(
    val seq: Long,
    val player: PlayerId,
    val visitTotal: Int,
    val dartsUsed: Int? = null,
    val dartsAtDouble: Int? = null,
    val correctsSeq: Long? = null,
)

/** One device's whole account of a match. */
public data class DeviceAccount(
    val deviceId: UUID,
    val visits: List<AccountedVisit>,
) {
    /**
     * The visits as they finally stood, with corrections applied.
     *
     * Superseded rows are dropped *here*, for the purpose of deriving an outcome. They remain in
     * the account itself, which is what an investigator reads.
     */
    public val effective: List<AccountedVisit>
        get() {
            val superseded = visits.mapNotNull { it.correctsSeq }.toSet()
            return visits.filter { it.seq !in superseded }.sortedBy { it.seq }
        }

    /**
     * A digest over this device's raw journal.
     *
     * Present only to be *demonstrated wrong*: two devices that agree completely about a match will
     * produce different digests the moment one of them corrected a mis-key. See
     * [Reconciliation] and the test that pins this.
     */
    public val journalDigest: Int
        get() = visits.sortedBy { it.seq }
            .joinToString("|") { "${it.seq}:${it.player.value}:${it.visitTotal}" }
            .hashCode()
}

/** What a match came to, at the only level two independent accounts can be compared on. */
public data class MatchOutcome(
    val winner: PlayerId?,
    val legsWon: Map<PlayerId, Int>,
)

/** A place where two accounts differ, used to *explain* a mismatch and never to detect one. */
public data class VisitDifference(
    val ordinal: Int,
    val left: AccountedVisit?,
    val right: AccountedVisit?,
)

public sealed interface Reconciliation {

    /** Both devices derive the same outcome. Two accounts agreeing is the strongest evidence THRØ has. */
    public data class Corroborated(
        public val outcome: MatchOutcome,
        public val devices: Set<UUID>,
    ) : Reconciliation

    /** Only one device has an account. Not corroborated — but not contested either. */
    public data class Uncorroborated(
        public val outcome: MatchOutcome,
        public val deviceId: UUID,
    ) : Reconciliation

    /**
     * The devices disagree about what happened.
     *
     * This is the whole-match-contested state ADR-006 predicted and the approved design does not
     * currently draw. It carries every account and a visit-level explanation, because an organiser
     * settling this needs to see where the two stories parted, not merely that they did.
     */
    public data class Contested(
        public val outcomes: Map<UUID, MatchOutcome>,
        public val explanation: List<VisitDifference>,
    ) : Reconciliation
}

/**
 * Reconciles independent device accounts of one match.
 *
 * **At outcome level — winner and per-player leg scores — never by digest equality.** A digest over
 * a leg's events makes a single mis-keyed-then-corrected visit mismatch on a leg both players agree
 * about, which would manufacture disputes out of ordinary scorer fumbles. The visit-level diff is
 * produced only to explain a mismatch that the outcome comparison already found.
 *
 * Accounts are never merged. The difference between two accounts is the product's most important
 * signal, so each is replayed on its own and the outcomes are compared.
 */
public object Reconcile {

    public fun outcomeOf(account: DeviceAccount, format: MatchFormat, home: PlayerId, away: PlayerId): MatchOutcome {
        var state = MatchState.start(format, home, away)
        val legs = mutableMapOf(home to 0, away to 0)
        for (v in account.effective) {
            val outcome = Engine_apply(state, v)
            if (outcome !is Outcome.Accepted) continue
            if (outcome.effect in setOf(Effect.LEG_WON, Effect.SET_WON, Effect.MATCH_WON)) {
                legs[v.player] = (legs[v.player] ?: 0) + 1
            }
            state = outcome.state
        }
        return MatchOutcome(winner = state.winner, legsWon = legs.toMap())
    }

    private fun Engine_apply(state: MatchState, v: AccountedVisit): Outcome =
        thro.engine.Engine.apply(
            state,
            Command.RecordVisit(v.player, v.visitTotal, v.dartsUsed, v.dartsAtDouble),
        )

    public fun reconcile(
        accounts: List<DeviceAccount>,
        format: MatchFormat,
        home: PlayerId,
        away: PlayerId,
    ): Reconciliation {
        require(accounts.isNotEmpty()) { "there is nothing to reconcile" }
        val outcomes = accounts.associate { it.deviceId to outcomeOf(it, format, home, away) }
        if (accounts.size == 1) {
            return Reconciliation.Uncorroborated(outcomes.values.first(), accounts.first().deviceId)
        }
        val distinct = outcomes.values.distinct()
        if (distinct.size == 1) {
            return Reconciliation.Corroborated(distinct.first(), outcomes.keys)
        }
        return Reconciliation.Contested(outcomes, explain(accounts[0], accounts[1]))
    }

    /**
     * Where two accounts parted, by position in each device's effective visit list.
     *
     * Deliberately simple: this is an explanation for a person, not a merge algorithm. Guessing at
     * an alignment between two disagreeing stories is how a reconciliation starts inventing a third.
     */
    public fun explain(left: DeviceAccount, right: DeviceAccount): List<VisitDifference> {
        val a = left.effective
        val b = right.effective
        return (0 until maxOf(a.size, b.size)).mapNotNull { i ->
            val l = a.getOrNull(i)
            val r = b.getOrNull(i)
            val same = l != null && r != null &&
                l.player == r.player && l.visitTotal == r.visitTotal
            if (same) null else VisitDifference(i + 1, l, r)
        }
    }
}
