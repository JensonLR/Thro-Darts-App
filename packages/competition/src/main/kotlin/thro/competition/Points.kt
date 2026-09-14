package thro.competition

/**
 * What a result is worth, and what orders the table (PD-054).
 *
 * **THRØ has a standard and a league may replace it.** The founder's decision was both halves: a league that
 * has said nothing gets a table rather than an empty screen, and a league that scores its darts differently
 * writes its own rules and those are what count. The condition that makes the standard safe is not in this
 * file — it is that every table says which policy ordered it and whose it is, so nobody mistakes THRØ's
 * standard for their league's constitution. OD-022's warning was about a constant *buried* in a calculation.
 *
 * **A rule THRØ cannot compute is refused, not ignored**, in the shape [RegistrationPolicy] set: a league
 * whose bonus point depends on the scoreline of each individual fixture is told so by name, because a table
 * that quietly dropped that rule would be a table that is wrong in a way only its league could notice.
 */
public data class PointsPolicy(
    /** Points for winning a fixture. */
    val win: Int = 2,
    val draw: Int = 1,
    val loss: Int = 0,
    /** What an awarded fixture or a walkover is worth to the side that received it. */
    val awarded: Int = 2,
    /**
     * Points for each leg won, for the leagues that score by leg as well as by fixture. Computable from a
     * season's totals, which is why it is here and a per-fixture bonus is not.
     */
    val perLegWon: Int = 0,
    val chain: List<TieBreak> = listOf(TieBreak.POINTS, TieBreak.LEG_DIFFERENCE, TieBreak.LEGS_FOR),
    /** Whether a fixture nobody played still counts in the played column. Most leagues say it does. */
    val awardsCountAsPlayed: Boolean = true,
) {

    /**
     * One team's row, from what the database counted.
     *
     * Awards arrive as counts and never as legs (ADR-012): a scoreline invented for a fixture nobody played
     * would pollute every leg-difference tie-break beneath it. So an award moves the points and the won
     * column, and leaves legs exactly as they were.
     */
    public fun row(
        competitorId: String,
        playedWon: Int,
        playedDrawn: Int,
        playedLost: Int,
        legsFor: Int,
        legsAgainst: Int,
        awardedFor: Int = 0,
        awardedAgainst: Int = 0,
    ): StandingsRow {
        val playedFixtures = playedWon + playedDrawn + playedLost
        return StandingsRow(
            competitorId = competitorId,
            played = playedFixtures + if (awardsCountAsPlayed) awardedFor + awardedAgainst else 0,
            won = playedWon + awardedFor,
            drawn = playedDrawn,
            lost = playedLost + awardedAgainst,
            legsFor = legsFor,
            legsAgainst = legsAgainst,
            points = win * playedWon + draw * playedDrawn + loss * playedLost +
                awarded * awardedFor + loss * awardedAgainst +
                perLegWon * legsFor,
        )
    }

    public companion object {
        /**
         * THRØ's standard (PD-054): two points a win, one a draw, none for a loss, and a walkover worth what
         * a win is worth. Ordered by points, then leg difference, then legs for. No bonus points — a league
         * that awards them writes its own.
         */
        public val STANDARD: PointsPolicy = PointsPolicy()

        /** The sentence shown beside a table THRØ's standard ordered, so the standard is never silent. */
        public const val STANDARD_SAYS: String =
            "Two points a win, one a draw. THRØ's standard, not this league's own rules."

        private val knownKeys = setOf(
            "win", "draw", "loss", "awarded", "points_per_leg_won", "tie_break", "awards_count_as_played",
        )

        private val tieBreaks = mapOf(
            "points" to TieBreak.POINTS,
            "leg_difference" to TieBreak.LEG_DIFFERENCE,
            "legs_for" to TieBreak.LEGS_FOR,
            "head_to_head" to TieBreak.HEAD_TO_HEAD,
            "played" to TieBreak.PLAYED,
        )

        /**
         * Parses the body of an approved `points` policy. A Map rather than JSON text, as
         * [RegistrationPolicy.parse] takes one, so this package stays free of a JSON reader and the reading
         * happens at the edge that already has one.
         */
        public fun parse(fields: Map<String, Any?>): PointsPolicy {
            val unknown = fields.keys - knownKeys
            require("bonus" !in unknown) {
                "this league awards a bonus point on a fixture's own scoreline, which THRØ cannot yet count: " +
                    "a table is built from a season's totals, and a per-fixture bonus needs each fixture. " +
                    "Points per leg won is supported as points_per_leg_won"
            }
            require(unknown.isEmpty()) { "points policy has keys THRØ cannot execute: $unknown" }

            fun points(key: String, fallback: Int): Int {
                val raw = fields[key] ?: return fallback
                val n = (raw as? Number)?.toInt()
                requireNotNull(n) { "$key is a number of points, not '$raw'" }
                require(n >= 0) {
                    "$key is $n: THRØ does not take points away for a result. A deduction is a decision about " +
                        "a team, recorded as one, not a rule about what a loss is worth"
                }
                return n
            }

            val declared = (fields["tie_break"] as? List<*>)?.map { step ->
                val name = step.toString().lowercase()
                tieBreaks[name] ?: throw IllegalArgumentException(
                    "points policy breaks ties on '$name', which THRØ cannot order by; it knows " +
                        tieBreaks.keys.joinToString(", "),
                )
            }
            require(declared == null || declared.isNotEmpty()) {
                "a tie_break is the order to try, so an empty one says nothing; leave it out for THRØ's own"
            }
            require(declared == null || declared.size == declared.toSet().size) {
                "a tie_break step appears once: trying the same one twice cannot separate anybody"
            }

            return PointsPolicy(
                win = points("win", 2),
                draw = points("draw", 1),
                loss = points("loss", 0),
                awarded = points("awarded", points("win", 2)),
                perLegWon = points("points_per_leg_won", 0),
                chain = declared ?: STANDARD.chain,
                awardsCountAsPlayed = fields["awards_count_as_played"] != false,
            )
        }
    }
}
