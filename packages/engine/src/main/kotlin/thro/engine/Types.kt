package thro.engine

/**
 * THRØ scoring domain — types.
 *
 * Deliberately constrained, because this module must produce identical results on iOS, Android and
 * server validation. It has no dependency beyond the Kotlin standard library, and contains no
 * floating point, no clock access, no randomness and no I/O. Anything non-deterministic — who threw
 * first, what time it is — arrives as an input, never as something the engine reaches for.
 */

@JvmInline
public value class PlayerId(public val value: String)

public enum class OutRule { DOUBLE, MASTER, STRAIGHT }

public enum class InRule {
    STRAIGHT,
    DOUBLE,
    MASTER,
    ;

    /**
     * Whether a player must open before anything scores.
     *
     * The engine scores a visit, not a dart, so this needed a capture rule before it could be
     * scored honestly at all — the founder asked for double-in because leagues and tournaments play
     * it, and PD-008 settled how a visit records it: what is recorded on a visit thrown while the
     * player has not opened is the score FROM the opening dart onward, and zero means they did not
     * open. That is what the scorer calls at the oche, it costs no statistic (a visit is three darts
     * either way), and a non-zero total that no opening sequence can make is refused.
     */
    public val requiresOpening: Boolean get() = this != STRAIGHT
}

/**
 * What a bust does to the score (OD-023). Declared on the match, never inferred, and never a
 * condition written into a screen: the engine is the only place that reads it.
 */
public enum class BustRule {
    /**
     * The standard rule. The visit counts for nothing and the score returns to what it was when the
     * visit began. On 40, a 20 then a D15 leaves 40.
     */
    RESTORE_VISIT,

    /**
     * A local rule some pub leagues play: the darts scored before the busting dart stand, and only
     * the busting dart counts for nothing. On 40, a 20 then a D15 leaves 20.
     *
     * Only the darts can say what came before the bust, so under this rule a visit that busts must
     * be recorded as darts; a busting total is refused as [RejectionReason.DARTS_REQUIRED].
     */
    KEEP_SCORED_DARTS,
}

/** Whether the right to start alternates every leg, or only between sets. Real competitions differ. */
public enum class Alternation { PER_LEG, PER_SET }

public enum class StructureMode { BEST_OF, FIRST_TO }

/**
 * @param clearBy legs a competitor must lead by to take the unit. 1 for most formats, 2 for
 *   two-clear-legs competitions.
 * @param cap an upper bound where a two-clear format would otherwise run indefinitely.
 */
public data class Structure(
    val mode: StructureMode,
    val target: Int,
    val clearBy: Int = 1,
    val cap: Int? = null,
) {
    init {
        require(target > 0) { "target must be positive" }
        require(clearBy >= 1) { "clearBy must be at least 1" }
    }

    /** Wins needed under this structure. Best-of-9 needs 5; first-to-5 needs 5. */
    public val winsRequired: Int
        get() = when (mode) {
            StructureMode.FIRST_TO -> target
            StructureMode.BEST_OF -> target / 2 + 1
        }
}

public data class MatchFormat(
    val startingScore: Int,
    val inRule: InRule,
    val outRule: OutRule,
    val legs: Structure,
    /** Null means the match is decided on legs alone. */
    val sets: Structure? = null,
    val throwFirst: PlayerId,
    val alternation: Alternation = Alternation.PER_LEG,
    val bustRule: BustRule = BustRule.RESTORE_VISIT,
) {
    init {
        require(startingScore > 1) { "starting score must exceed 1" }
    }
}

/** The part of the board a dart landed in. */
public enum class Ring { MISS, SINGLE, DOUBLE, TREBLE }

/**
 * One dart, as it landed (OD-023).
 *
 * A dart is decided by its RING, never by its value: a single 20 and a double 10 both score 20, and
 * only one of them finishes a double-out leg. That is the whole reason the engine takes darts at all.
 *
 * `number` is 1..20 or 25 (the bull's number), and 0 for a miss. The inner bull is `Dart(25, DOUBLE)`
 * and scores 50; the outer bull is `Dart(25, SINGLE)` and scores 25. A dart that is not on the board —
 * a treble bull, a double nought — can be constructed, is [isOnTheBoard] false, and is refused by the
 * engine as [RejectionReason.DART_INVALID] rather than thrown as an exception.
 */
public data class Dart(val number: Int, val ring: Ring) {
    public val isOnTheBoard: Boolean
        get() = when (ring) {
            Ring.MISS -> number == 0
            Ring.SINGLE, Ring.DOUBLE -> number in 1..20 || number == BULL_NUMBER
            Ring.TREBLE -> number in 1..20
        }

    public val value: Int
        get() = when (ring) {
            Ring.MISS -> 0
            Ring.SINGLE -> number
            Ring.DOUBLE -> 2 * number
            Ring.TREBLE -> 3 * number
        }

    /** Whether this dart may end a leg under [outRule]. The bull is a double. */
    public fun mayFinish(outRule: OutRule): Boolean = when (outRule) {
        OutRule.DOUBLE -> ring == Ring.DOUBLE
        OutRule.MASTER -> ring == Ring.DOUBLE || ring == Ring.TREBLE
        OutRule.STRAIGHT -> value > 0
    }

    /** Whether this dart may open a leg under [inRule]. The same rings as finishing, and for the same reason. */
    public fun mayOpen(inRule: InRule): Boolean = when (inRule) {
        InRule.DOUBLE -> ring == Ring.DOUBLE
        InRule.MASTER -> ring == Ring.DOUBLE || ring == Ring.TREBLE
        InRule.STRAIGHT -> value > 0
    }

    /** The name a scorer says, and the one the route table uses: T20, D16, 20, 25, Bull, Miss. */
    public val name: String
        get() = when {
            ring == Ring.MISS -> "Miss"
            number == BULL_NUMBER && ring == Ring.DOUBLE -> "Bull"
            number == BULL_NUMBER && ring == Ring.SINGLE -> "25"
            ring == Ring.SINGLE -> "$number"
            ring == Ring.DOUBLE -> "D$number"
            else -> "T$number"
        }

    override fun toString(): String = name

    public companion object {
        public const val BULL_NUMBER: Int = 25
        public val MISS: Dart = Dart(0, Ring.MISS)
        public val BULL: Dart = Dart(BULL_NUMBER, Ring.DOUBLE)
        public val OUTER_BULL: Dart = Dart(BULL_NUMBER, Ring.SINGLE)

        /**
         * Reads a dart's name — the inverse of [name]. Syntactic only: `T25` parses to a dart that is
         * not on the board, so the refusal is the engine's and carries its reason. Null for text that is
         * not a dart's name at all.
         */
        public fun parse(text: String): Dart? {
            val t = text.trim()
            when (t) {
                "Miss", "0" -> return MISS
                "Bull", "D25" -> return BULL
                "25", "S25" -> return OUTER_BULL
            }
            val (ring, digits) = when (t.firstOrNull()) {
                'S' -> Ring.SINGLE to t.drop(1)
                'D' -> Ring.DOUBLE to t.drop(1)
                'T' -> Ring.TREBLE to t.drop(1)
                else -> Ring.SINGLE to t
            }
            // ASCII digits only, exactly as the Swift twin reads them: `toIntOrNull` alone would take a
            // sign, and the two parsers must accept the same text.
            if (digits.isEmpty() || !digits.all { it in '0'..'9' }) return null
            return Dart(digits.toIntOrNull() ?: return null, ring)
        }
    }
}

public sealed interface Command {
    /**
     * @param dartsUsed how many darts the visit consumed. Only ever ambiguous on a visit that wins
     *   a leg, so it may be null (unknown) or 3 on any other visit. Null means *unknown* — never
     *   zero, and never inferred.
     * @param dartsAtDouble how many of those darts were thrown at a double. Asked on **every** visit
     *   that began on a checkout number, not only on one that finished: a player who was on a finish
     *   and missed still attempted doubles, and those attempts are what make checkout percentage
     *   computable at all. Null means unknown; 0 means genuinely none were thrown.
     */
    public data class RecordVisit(
        val player: PlayerId,
        val visitTotal: Int,
        val dartsUsed: Int? = null,
        val dartsAtDouble: Int? = null,
    ) : Command

    /**
     * A visit recorded as the darts that were thrown (OD-023): one to three, in order, and none after
     * the dart that finished or bust the visit. The engine derives everything a total had to be told —
     * what counted, whether and where it bust, how many darts were used and how many were thrown at
     * a double — so none of it can be contradicted by a client.
     */
    public data class RecordDarts(
        val player: PlayerId,
        val darts: List<Dart>,
    ) : Command
}

public enum class RejectionReason {
    IMPOSSIBLE_VISIT_TOTAL,

    /**
     * A non-zero total recorded by a player who has not opened, that no sequence beginning with a
     * legal opening segment can make. Distinct from IMPOSSIBLE_VISIT_TOTAL because the total is
     * perfectly possible for an opened player: 180 is three trebles, and three trebles cannot open
     * a double-in leg. The message a client shows differs, so the reason does too.
     */
    IMPOSSIBLE_OPENING_TOTAL,
    VISIT_TOTAL_OUT_OF_RANGE,
    DARTS_USED_INVALID,
    DARTS_AT_DOUBLE_INVALID,
    NOT_YOUR_TURN,
    MATCH_COMPLETE,

    /** A dart that is not on the board: a treble bull, a double nought. */
    DART_INVALID,

    /**
     * A total that busts, under [BustRule.KEEP_SCORED_DARTS]. What stands depends on the darts before
     * the busting one, and a total does not say — so the scorer enters the darts rather than THRØ
     * guessing which of them came first.
     */
    DARTS_REQUIRED,
}

public enum class BustReason {
    BELOW_ZERO,
    REMAINDER_ONE,
    NOT_CHECKOUT_POSSIBLE,

    /**
     * Reached zero on a dart that may not end the leg — a treble or a single under double-out. Only
     * darts can show it: a total of 60 from 60 reads as a checkout, and T20 from 60 is a bust.
     */
    NOT_A_FINISHING_DART,
}

/**
 * What one accepted visit amounted to, for the record and for every statistic built on it.
 *
 * @param visitTotal the total a visit-level record carries: the darts from the opening one onward,
 *   including a busting dart — exactly what [Command.RecordVisit] would have been given.
 * @param scored the points the visit took off the score. Zero on a standard bust; under
 *   [BustRule.KEEP_SCORED_DARTS], what the darts before the busting one scored.
 * @param dartsUsed three on any visit that did not win the leg — a bust forfeits the rest of the
 *   hand — and the darts actually thrown on one that did. Null where the visit did not say.
 * @param dartsAtDouble darts thrown while the score in front of them was a one-dart finish. Null
 *   where the visit did not say.
 * @param bustAt the index of the dart that bust the visit, when the darts were given.
 * @param darts the darts, when they were given.
 */
public data class VisitReading(
    val visitTotal: Int,
    val scored: Int,
    val dartsUsed: Int?,
    val dartsAtDouble: Int?,
    val bustAt: Int? = null,
    val darts: List<Dart>? = null,
)

public enum class Effect { SCORED, BUST, LEG_WON, SET_WON, MATCH_WON }

public sealed interface Outcome {
    public data class Accepted(
        val state: MatchState,
        val effect: Effect,
        val bustReason: BustReason? = null,
        /** Null only where an engine older than 1.4.0 produced the outcome. */
        val reading: VisitReading? = null,
    ) : Outcome

    /** A rejection is part of the contract, not an exception: the UI renders it. */
    public data class Rejected(val reason: RejectionReason) : Outcome
}

public data class MatchState(
    val format: MatchFormat,
    val home: PlayerId,
    val away: PlayerId,
    val remaining: Map<PlayerId, Int>,
    val legsWonInSet: Map<PlayerId, Int>,
    val setsWon: Map<PlayerId, Int>,
    val legsWonTotal: Map<PlayerId, Int>,
    val currentSet: Int,
    val currentLeg: Int,
    val legStarter: PlayerId,
    val setStarter: PlayerId,
    /** Null once the match is complete. */
    val thrower: PlayerId?,
    val winner: PlayerId? = null,
    val visitsInLeg: Int = 0,
    /**
     * Who has opened in the current leg (PD-008). Under straight-in both are open from the first
     * dart; under double-in or master-in a player scores nothing until they open, and this resets
     * with every leg and every set, because opening is a fact about a leg and not about a match.
     */
    val opened: Map<PlayerId, Boolean> = emptyMap(),
) {
    public val isComplete: Boolean get() = winner != null

    public fun opponentOf(p: PlayerId): PlayerId = if (p == home) away else home

    public companion object {
        public fun start(format: MatchFormat, home: PlayerId, away: PlayerId): MatchState {
            require(home != away) { "a competitor cannot play itself" }
            require(format.throwFirst == home || format.throwFirst == away) {
                "throwFirst must be one of the competitors"
            }
            val zero = mapOf(home to 0, away to 0)
            val open = !format.inRule.requiresOpening
            return MatchState(
                format = format,
                home = home,
                away = away,
                remaining = mapOf(home to format.startingScore, away to format.startingScore),
                legsWonInSet = zero,
                setsWon = zero,
                legsWonTotal = zero,
                currentSet = 1,
                currentLeg = 1,
                legStarter = format.throwFirst,
                setStarter = format.throwFirst,
                thrower = format.throwFirst,
                opened = mapOf(home to open, away to open),
            )
        }
    }
}
