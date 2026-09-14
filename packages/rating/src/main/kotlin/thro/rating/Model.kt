package thro.rating

/**
 * Where a replay stands in the evidence log.
 *
 * **A pair, never a scalar.** `global_seq` alone is unsafe to order by — it is assigned at insert,
 * not at commit, so a reader polling above a high-water mark silently skips rows from transactions
 * that started earlier and committed later. Per-device sequences are not comparable across devices
 * at all. Cross-device order is `(commit_xid, global_seq)`, and reproducibility is the primary key
 * of the whole rating programme, so both are carried everywhere.
 */
public data class Watermark(val commitXid: Long, val globalSeq: Long) : Comparable<Watermark> {
    override fun compareTo(other: Watermark): Int =
        compareValuesBy(this, other, { it.commitXid }, { it.globalSeq })
}

public data class PlayerId(val value: String)

/** One eligible result, as the rating module sees it. Assembled from published projections. */
public data class EvidenceRow(
    val matchId: String,
    val at: Watermark,
    val home: PlayerId,
    val away: PlayerId,
    /** 1.0 home won, 0.0 away won. Draws do not exist in darts. */
    val homeScore: Double,
    val legsHome: Int,
    val legsAway: Int,
    val qualifying: Boolean,
)

/** A player's state under one model at one watermark. */
public data class Snapshot(
    val player: PlayerId,
    val modelId: String,
    val modelVersion: String,
    val parameterHash: String,
    val scaleEpoch: Int,
    val asOf: Watermark,
    /** Null while provisional. A provisional rating is an em dash, never a number nobody trusts. */
    val rating: Double?,
    val confidence: Double,
    val matchesCounted: Int,
    val published: Boolean,
)

/**
 * One visible line of change.
 *
 * **Ledger invariant:** the per-match lines must reconcile exactly to the net change over the same
 * period. Any non-match adjustment — recomputation, correction, decay, an eligibility change —
 * appears as its own line and is never silently absorbed into a match's delta.
 */
public data class LedgerLine(
    val player: PlayerId,
    val at: Watermark,
    val cause: Cause,
    val matchId: String?,
    val delta: Double,
    /**
     * Frozen at rating time, never reconstructed on read. Ratings drift, so a regenerated
     * explanation would quote a past opponent at their present rating and be false.
     */
    val explanation: Explanation?,
) {
    public enum class Cause { MATCH, RECOMPUTATION, CORRECTION, DECAY, ELIGIBILITY_CHANGE }
}

/** Everything needed to explain one change, captured at the instant it happened. */
public data class Explanation(
    val opponent: PlayerId,
    val opponentRatingAtTheTime: Double?,
    val opponentConfidenceAtTheTime: Double,
    val ownRatingAtTheTime: Double?,
    val predictedProbability: Double?,
    val realisedOutcome: Double,
    val modelVersion: String,
)

/**
 * A rating model.
 *
 * OD-001 is open and must be settled by evidence from the research laboratory, not by whichever
 * implementation shipped first. So a model declares whether it has been **validated**, and nothing
 * unvalidated can be published — see [Publication]. That is the mechanism that keeps the decision
 * genuinely open rather than merely nominally open.
 */
public interface RatingModel {
    public val id: String
    public val version: String
    public val parameterHash: String

    /**
     * Whether this model has passed the research laboratory's bar. **No model in this repository
     * sets this true**, and none should until Gate 8 produces the evidence.
     */
    public val validated: Boolean get() = false

    /** Rank is never an input. A rating computed from rank and a rank computed from rating is a loop. */
    public fun rate(evidence: List<EvidenceRow>): Pair<List<Snapshot>, List<LedgerLine>>
}
