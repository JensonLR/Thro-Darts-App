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

public enum class InRule { STRAIGHT, DOUBLE, MASTER }

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
) {
    init { require(startingScore > 1) { "starting score must exceed 1" } }
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
}

public enum class RejectionReason {
    IMPOSSIBLE_VISIT_TOTAL,
    VISIT_TOTAL_OUT_OF_RANGE,
    DARTS_USED_INVALID,
    DARTS_AT_DOUBLE_INVALID,
    NOT_YOUR_TURN,
    MATCH_COMPLETE,
}

public enum class BustReason { BELOW_ZERO, REMAINDER_ONE, NOT_CHECKOUT_POSSIBLE }

public enum class Effect { SCORED, BUST, LEG_WON, SET_WON, MATCH_WON }

public sealed interface Outcome {
    public data class Accepted(
        val state: MatchState,
        val effect: Effect,
        val bustReason: BustReason? = null,
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
            )
        }
    }
}
