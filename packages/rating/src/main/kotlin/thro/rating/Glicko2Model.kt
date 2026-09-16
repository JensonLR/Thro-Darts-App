package thro.rating

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * The provisional rating (PD-105): Glicko-2, one match at a time, in evidence order.
 *
 * **Why this shape.** OD-001 says match outcome is the primary competitive anchor and that a model must carry its
 * own uncertainty; the harness names Glicko-2 as "the natural fit for the inactivity semantics the design requires".
 * A rating here is a mean with a deviation, and the deviation is what the display projection turns into a range —
 * so a player with two matches is shown a wide range rather than a number nobody should trust. It is
 * **provisional** in the model's own stage: it may be published as such, and nothing about it is validated.
 *
 * **What it reads.** Outcome only — who won. Legs, visits and darts are in the evidence row and ignored on purpose:
 * the harness's baselines and hybrids exist to test whether they help, and until that is run, a rating that reads
 * them would be a decision by implementation.
 *
 * **What it does not do.** No rating period: each match is its own, with each player's update computed against the
 * opponent's state *before* the match, so the two updates are symmetric and the order of two matches in one
 * transaction is the watermark's to fix. No decay for inactivity yet — a deviation that widens with time is the next
 * thing the harness would ask for, and it is a visible ledger line when it comes, never a silent drift.
 *
 * Every number is from Glickman's paper: the scale, the `g` and `E` functions, the volatility iteration with its
 * convergence tolerance. The one choice is [tau], the system constant, at 0.5 — the paper's middle of the range —
 * because nothing has been measured yet to move it.
 */
public class Glicko2Model(
    private val tau: Double = 0.5,
) : RatingModel {
    override val id: String = "glicko2"
    override val version: String = "1.0.0"
    override val parameterHash: String = "tau=$tau;initial=$INITIAL_RATING/$INITIAL_DEVIATION/$INITIAL_VOLATILITY;establish=$ESTABLISH_AFTER/$ESTABLISHED_DEVIATION"
    override val stage: RatingModel.Stage = RatingModel.Stage.PROVISIONAL

    public companion object {
        public const val INITIAL_RATING: Double = 1500.0
        public const val INITIAL_DEVIATION: Double = 350.0
        public const val INITIAL_VOLATILITY: Double = 0.06
        /** A number, rather than a range, needs this many matches… */
        public const val ESTABLISH_AFTER: Int = 10
        /** …and a deviation this narrow. Both, because ten matches against one opponent narrow little. */
        public const val ESTABLISHED_DEVIATION: Double = 120.0
        /**
         * The upset bound the harness asks for, stated: one result never moves a rating by more than this. With the
         * initial deviation of 350 the paper's arithmetic tops out below it; the tests hold it over random play.
         */
        public const val MOST_ONE_MATCH_MAY_MOVE: Double = 400.0
        private const val SCALE = 173.7178
        private const val EPSILON = 0.000001
    }

    private data class State(val mu: Double, val phi: Double, val sigma: Double, val matches: Int) {
        val rating: Double get() = mu * SCALE + INITIAL_RATING
        val deviation: Double get() = phi * SCALE
    }

    private fun fresh() = State(0.0, INITIAL_DEVIATION / SCALE, INITIAL_VOLATILITY, 0)

    private fun g(phi: Double) = 1.0 / sqrt(1.0 + 3.0 * phi * phi / (PI * PI))
    private fun expected(mu: Double, muJ: Double, phiJ: Double) = 1.0 / (1.0 + exp(-g(phiJ) * (mu - muJ)))

    /** One player's update from one game against one opponent's pre-game state. Glickman (2012), steps 3–8. */
    private fun update(me: State, opp: State, score: Double): State {
        val gj = g(opp.phi)
        val e = expected(me.mu, opp.mu, opp.phi)
        val v = 1.0 / (gj * gj * e * (1 - e))
        val delta = v * gj * (score - e)
        // Volatility: the illustrative iteration, to the paper's tolerance.
        val a = ln(me.sigma * me.sigma)
        val phi2 = me.phi * me.phi
        fun f(x: Double): Double {
            val ex = exp(x)
            return ex * (delta * delta - phi2 - v - ex) / (2 * (phi2 + v + ex) * (phi2 + v + ex)) - (x - a) / (tau * tau)
        }
        var aa = a
        var bb = if (delta * delta > phi2 + v) ln(delta * delta - phi2 - v) else {
            var k = 1
            while (f(a - k * tau) < 0) k++
            a - k * tau
        }
        var fa = f(aa); var fb = f(bb)
        while (abs(bb - aa) > EPSILON) {
            val c = aa + (aa - bb) * fa / (fb - fa)
            val fc = f(c)
            if (fc * fb <= 0) { aa = bb; fa = fb } else fa /= 2
            bb = c; fb = fc
        }
        val sigma = exp(aa / 2)
        val phiStar = sqrt(phi2 + sigma * sigma)
        val phi = 1.0 / sqrt(1.0 / (phiStar * phiStar) + 1.0 / v)
        val mu = me.mu + phi * phi * gj * (score - e)
        return State(mu, phi, sigma, me.matches + 1)
    }

    override fun rate(evidence: List<EvidenceRow>): Pair<List<Snapshot>, List<LedgerLine>> {
        val rows = evidence.filter { it.qualifying }.sortedWith(compareBy({ it.at }, { it.matchId }))
        val states = LinkedHashMap<PlayerId, State>()
        val ledger = ArrayList<LedgerLine>()
        val pools = Pools()
        for (row in rows) {
            val h = states[row.home] ?: fresh()
            val a = states[row.away] ?: fresh()
            val h2 = update(h, a, row.homeScore)
            val a2 = update(a, h, 1.0 - row.homeScore)
            states[row.home] = h2; states[row.away] = a2
            pools.join(row.home, row.away)
            fun line(who: PlayerId, before: State, after: State, opp: State, score: Double) = LedgerLine(
                player = who, at = row.at, cause = LedgerLine.Cause.MATCH, matchId = row.matchId,
                delta = after.rating - before.rating,
                explanation = Explanation(
                    opponent = if (who == row.home) row.away else row.home,
                    opponentRatingAtTheTime = opp.rating, opponentConfidenceAtTheTime = confidence(opp),
                    ownRatingAtTheTime = before.rating,
                    predictedProbability = expected(before.mu, opp.mu, opp.phi),
                    realisedOutcome = score, modelVersion = version,
                ),
            )
            ledger += line(row.home, h, h2, a, row.homeScore)
            ledger += line(row.away, a, a2, h, 1.0 - row.homeScore)
        }
        val asOf = rows.maxOfOrNull { it.at } ?: Watermark(0, 0)
        val snapshots = states.entries.sortedBy { it.key.value }.map { (player, s) ->
            Snapshot(
                player = player, modelId = id, modelVersion = version, parameterHash = parameterHash, scaleEpoch = 1,
                asOf = asOf, rating = s.rating, confidence = confidence(s), matchesCounted = s.matches, published = true,
                dispersion = 1.96 * s.deviation, pool = pools.sizeOf(player),
            )
        }
        return snapshots to ledger
    }

    /** How narrow the deviation has become, as a fraction of the way from the initial one to the established one. */
    private fun confidence(s: State): Double =
        ((INITIAL_DEVIATION - s.deviation) / (INITIAL_DEVIATION - ESTABLISHED_DEVIATION)).coerceIn(0.0, 1.0)

    /** Connected components of who has played whom: union–find, small and exact. */
    private class Pools {
        private val parent = HashMap<PlayerId, PlayerId>()
        private fun find(p: PlayerId): PlayerId {
            var x = p
            while (parent.getOrPut(x) { x } != x) x = parent.getValue(x)
            return x
        }
        fun join(a: PlayerId, b: PlayerId) { val ra = find(a); val rb = find(b); if (ra != rb) parent[ra] = rb }
        fun sizeOf(p: PlayerId): Int { val r = find(p); return parent.keys.count { find(it) == r } }
    }
}
