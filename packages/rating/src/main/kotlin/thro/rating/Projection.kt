package thro.rating

/**
 * Who may be published, and why almost nobody may.
 *
 * ADR-009's launch position is that **every player is provisional**. The approved design already
 * renders that as an em dash with a "Rating establishing" tag, so the whole flagship slice ships
 * with no rating integer published, candidates running in shadow, and the confidence surface
 * honestly saying the system is still learning. That is not a placeholder — it is the truthful
 * state of the world at launch.
 */
public object Publication {

    /** Refuses to publish anything a model has not earned the right to publish. */
    public fun check(model: RatingModel, publishedModels: Set<String>): Result {
        if (!model.validated) {
            return Result.Refused(
                "${model.id} is not validated. OD-001 is open: the rating model must be chosen " +
                    "from research-laboratory evidence, and publishing an unvalidated model is " +
                    "exactly the decision-by-implementation this register exists to prevent.",
            )
        }
        val others = publishedModels - model.id
        if (others.isNotEmpty()) {
            return Result.Refused(
                "${others.joinToString()} is already published. Exactly one model is published at " +
                    "a time; running two would make 'a player's rating' ambiguous.",
            )
        }
        return Result.Allowed
    }

    public sealed interface Result {
        public data object Allowed : Result
        public data class Refused(val why: String) : Result
    }
}

/**
 * Replays evidence into snapshots and a ledger.
 *
 * Rating is a **projection**, never an incrementally mutated number. That is not a stylistic
 * preference: the approved organiser dispute screen states "Ratings are recalculated from the
 * corrected result", and reversing one match must ripple to every opponent downstream of it. An
 * incremental store cannot honour that sentence; a projection is simply recomputed.
 */
public object Projection {

    /**
     * Replays every row at or below [asOf], in cross-device order.
     *
     * Materialised **as of a stated watermark**, never "as of now": the projections this evidence
     * is assembled from lag independently, so "now" is not a reproducible input.
     */
    public fun replay(
        evidence: List<EvidenceRow>,
        model: RatingModel,
        asOf: Watermark,
    ): Replay {
        val included = evidence.filter { it.at <= asOf }.sortedBy { it.at }
        val (snapshots, ledger) = model.rate(included)
        return Replay(
            asOf = asOf,
            model = model,
            snapshots = snapshots,
            ledger = ledger,
            evidenceCount = included.size,
        )
    }

    public data class Replay(
        val asOf: Watermark,
        val model: RatingModel,
        val snapshots: List<Snapshot>,
        val ledger: List<LedgerLine>,
        val evidenceCount: Int,
    ) {
        /**
         * The ledger invariant: per-player lines must sum exactly to that player's net change.
         *
         * Any adjustment that is not a match — a recomputation, a correction, decay, an eligibility
         * change — has to appear as its own line. Silently absorbing one into a match's delta is
         * how a rating becomes unauditable.
         */
        public fun ledgerReconciles(previous: Map<PlayerId, Double?>): Boolean =
            snapshots.all { snap ->
                val before = previous[snap.player] ?: 0.0
                val lines = ledger.filter { it.player == snap.player }.sumOf { it.delta }
                val after = snap.rating ?: 0.0
                kotlin.math.abs((before + lines) - after) < 1e-9
            }
    }
}

/**
 * The launch model: everybody provisional, nothing published.
 *
 * It computes no rating at all, which is the honest answer while OD-001 is open. It exists so the
 * whole pipeline — evidence, replay, snapshots, ledger, publication refusal — runs end to end
 * without anyone being shown a number that no evidence supports.
 *
 * Confidence still moves, because "how much has this player been observed" is answerable without a
 * model. It is reported as a fraction of the establishment threshold and never as a rating.
 */
public class ProvisionalModel(
    private val establishAfter: Int = 10,
) : RatingModel {
    override val id: String = "provisional"
    override val version: String = "1.0.0"
    override val parameterHash: String = "establishAfter=$establishAfter"
    override val validated: Boolean = false

    override fun rate(evidence: List<EvidenceRow>): Pair<List<Snapshot>, List<LedgerLine>> {
        val counted = mutableMapOf<PlayerId, Int>()
        for (row in evidence.filter { it.qualifying }) {
            counted[row.home] = (counted[row.home] ?: 0) + 1
            counted[row.away] = (counted[row.away] ?: 0) + 1
        }
        val asOf = evidence.maxOfOrNull { it.at } ?: Watermark(0, 0)
        val snapshots = counted.map { (player, n) ->
            Snapshot(
                player = player,
                modelId = id,
                modelVersion = version,
                parameterHash = parameterHash,
                scaleEpoch = 1,
                asOf = asOf,
                rating = null,                       // provisional: an em dash, not a number
                confidence = (n.toDouble() / establishAfter).coerceAtMost(1.0),
                matchesCounted = n,
                published = false,
            )
        }
        // No rating means no rating movement, so the ledger is empty and reconciles trivially.
        return snapshots to emptyList()
    }
}
