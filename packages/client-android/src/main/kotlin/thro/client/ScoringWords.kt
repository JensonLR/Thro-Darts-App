package thro.client

import thro.engine.BustReason
import thro.engine.BustRule
import thro.engine.Dart
import thro.engine.Darts
import thro.engine.RejectionReason
import thro.engine.Ring
import thro.engine.RuleTables
import thro.journal.Seat

/// What the scoring screen says, in a type so it is tested rather than looked at — the rule the wrist and
/// the wall already follow.
public object ThroScoringWords {

    /// Three digits at most, and never a leading zero that means nothing. 180 is the ceiling the engine
    /// enforces; this stops a fourth digit reaching it at all, which is the difference between a keypad
    /// that cannot be misused and a rejection the player has to read.
    public fun typed(current: String, digit: Int): String {
        val next = if (current == "0") "$digit" else current + digit
        if (next.length > 3) return current
        return if ((next.toIntOrNull() ?: 0) > RuleTables.MAX_VISIT_TOTAL) current else next
    }

    /// The line under the two scores: what is being typed, or what just happened, or where the visit stands.
    ///
    /// **What is typed outranks what happened**, because the player is looking at their own fingers. The
    /// mark from the last visit is what they read when they are not typing.
    public fun say(session: ThroSession, typed: String): String {
        if (typed.isNotEmpty()) return typed
        return when (val mark = session.mark) {
            is ThroMark.Refused -> refused(mark.reason)
            is ThroMark.Bust -> bust(session, mark)
            is ThroMark.Scored -> live(session)
            is ThroMark.LegWon -> legWon(session, mark.seat, "Leg")
            is ThroMark.SetWon -> legWon(session, mark.seat, "Set")
            ThroMark.MatchWon -> session.state.winner
                ?.let { session.name(if (it == session.state.home) Seat.HOME else Seat.AWAY) }
                ?.let { "$it wins" } ?: "Match"
            ThroMark.AlreadyDecided -> VISIT_ALREADY_DECIDED
            is ThroMark.Trouble -> mark.message
            null -> live(session)
        }
    }

    /// Where the visit in hand stands, from the engine's reading of the darts so far: the route that is still on,
    /// or — once the darts have decided the visit — what they decided, so the player presses Enter knowing.
    public fun live(session: ThroSession): String {
        val reading = session.throwerReading
        when (reading?.settled) {
            Darts.Settled.BUST -> {
                val kept = if (session.bustRule == BustRule.KEEP_SCORED_DARTS) reading.scoredBefore else null
                val cause = bustReason(reading.bustReason, reading.counted, reading.at, session.darts, kept)
                return listOfNotNull("Bust.", cause, "Press Enter to record it.").joinToString(" ")
            }
            Darts.Settled.LEG_WON -> return "That finishes the leg. Press Enter to record it."
            Darts.Settled.SCORED, null -> Unit
        }
        return session.throwerRoute.joinToString(" ")
    }

    /// A bust once it is recorded: why, and the score the ENGINE left the thrower on. Under keep-scored darts that
    /// is not the score the visit began on, so it is never worked out here.
    public fun bust(session: ThroSession, mark: ThroMark.Bust): String {
        val cause = bustReason(mark.reason, mark.total, mark.bustAt, mark.darts, mark.kept)
        val score = if (mark.kept != null && mark.kept > 0) "Score now ${mark.restored}."
                    else "Score restored to ${mark.restored}."
        return listOfNotNull("Bust.", cause, score, next(session)).joinToString(" ")
    }

    private fun legWon(session: ThroSession, seat: Seat, unit: String): String =
        listOfNotNull(
            "$unit to ${session.name(seat)}, ${session.legs(Seat.HOME)}–${session.legs(Seat.AWAY)}.",
            next(session),
        ).joinToString(" ")

    private fun next(session: ThroSession): String? = session.throwerSeat?.let { "${session.name(it)} to throw." }

    /// The engine's reason for a bust, in words a player at the board can check — the iPhone's sentences.
    ///
    /// With darts it names the dart that bust, because "bust" alone does not say which of three did it. Under
    /// keep-scored darts it says what stood, because that is the number most players will not expect.
    public fun bustReason(
        reason: BustReason?,
        total: Int,
        bustAt: Int? = null,
        darts: List<Dart>? = null,
        kept: Int? = null,
    ): String? {
        val which = bustAt?.let { i -> darts?.getOrNull(i)?.let { ThroDartWords.written(it) } }
        val cause = when (reason) {
            BustReason.REMAINDER_ONE -> which?.let { "$it leaves 1." } ?: "That leaves 1."
            BustReason.NOT_CHECKOUT_POSSIBLE -> "$total cannot be finished on a double."
            BustReason.NOT_A_FINISHING_DART -> which?.let { "$it reaches zero, and this leg has to end on a double." }
                ?: "That reaches zero on a dart that cannot finish."
            BustReason.BELOW_ZERO -> which?.let { "$it goes below zero." }
            null -> null
        }
        if (kept == null || kept <= 0) return cause
        return listOfNotNull(cause, "The $kept before it stands.").joinToString(" ")
    }

    public const val VISIT_ALREADY_DECIDED: String = "That visit is already decided — press Enter to record it."

    public const val DARTS_REQUIRED: String =
        "That is a bust, and this match keeps the darts before a bust. Enter this visit dart by dart."

    /// A refusal in words a player can act on. Never the enum's name: `IMPOSSIBLE_VISIT_TOTAL` is true and
    /// useless, and a person holding three darts needs to know what to type instead.
    public fun refused(reason: RejectionReason): String = when (reason) {
        RejectionReason.IMPOSSIBLE_VISIT_TOTAL -> "No three darts make that"
        // Distinct from the above on purpose, and the engine keeps them distinct for exactly this reason:
        // 180 is a perfectly possible visit and cannot open a double-in leg, so telling a player it is
        // impossible would be telling them something false.
        RejectionReason.IMPOSSIBLE_OPENING_TOTAL -> "Not in yet — that cannot start the leg"
        RejectionReason.VISIT_TOTAL_OUT_OF_RANGE -> "A visit is 0 to 180"
        RejectionReason.MATCH_COMPLETE -> "The match is over"
        RejectionReason.NOT_YOUR_TURN -> "Not your throw"
        RejectionReason.DARTS_USED_INVALID, RejectionReason.DARTS_AT_DOUBLE_INVALID ->
            "That does not add up as three darts"
        // Keypad darts are always on the board, so this is a defect rather than a mis-key; it is still a
        // sentence, because a refusal a player cannot read is a dead end.
        RejectionReason.DART_INVALID -> "One of those darts is not on the board"
        // Keep-scored darts: what stands after a bust depends on which darts came first, and a total does not say.
        RejectionReason.DARTS_REQUIRED -> DARTS_REQUIRED
    }

    /// What Enter says on the dart keypad. It carries the running total once the visit can be entered, and
    /// otherwise how many darts are still to come — a key out of the light with nothing to say is a key a player
    /// taps twice and then distrusts.
    public fun enterLabel(session: ThroSession): String {
        val darts = session.darts
        if (darts.isEmpty()) return "Enter"
        if (!session.dartsMayBeEntered) {
            val left = Darts.HAND - darts.size
            return if (left == 1) "One more" else "$left more"
        }
        return "Enter ${darts.sumOf { it.value }}"
    }
    /// The question and its context, in the words iOS uses.
    public fun prompt(p: ThroSession.Prompt): Pair<String, String> = when (p) {
        is ThroSession.Prompt.DartsUsed -> "Darts used to check out?" to "Finish on ${p.total}"
        is ThroSession.Prompt.DartsAtDouble -> "Darts thrown at a double?" to
            (if (p.finished) "Finish on ${p.total}" else "${p.total} scored from a finish")
    }
}

/// How the keypad writes and says a dart. The ENGINE's dart throughout — this only names it.
public object ThroDartWords {

    /// The sectors as the keypad lays them out: four rows of five, counting down from 20, as on the iPhone.
    public val rows: List<List<Int>> = (20 downTo 1).chunked(5)

    /// On a scoresheet and on the key: T20, D16, 5, 25, BULL, and MISS for a miss — a key has to say what
    /// pressing it does.
    public fun written(dart: Dart): String = when {
        dart.ring == Ring.MISS -> "MISS"
        dart == Dart.BULL -> "BULL"
        else -> dart.name
    }

    /// For TalkBack: "double 16", "treble 20", "single 5", "twenty five", "bullseye", "miss".
    public fun spoken(dart: Dart): String = when {
        dart.ring == Ring.MISS -> "miss"
        dart == Dart.BULL -> "bullseye"
        dart == Dart.OUTER_BULL -> "twenty five"
        dart.ring == Ring.DOUBLE -> "double ${dart.number}"
        dart.ring == Ring.TREBLE -> "treble ${dart.number}"
        else -> "single ${dart.number}"
    }

    /// Half-entered darts as a screen keeps them across being rebuilt: their names, comma-separated. Anything that
    /// does not read back as darts is dropped rather than guessed at.
    public fun store(darts: List<Dart>): String = darts.joinToString(",") { it.name }

    public fun read(stored: String): List<Dart> =
        if (stored.isBlank()) emptyList() else stored.split(',').mapNotNull { Dart.parse(it) }.filter { it.isOnTheBoard }
}

/// Which keypad the scorer is using.
public enum class ThroEntryMode {
    /// The total of three darts, typed. The default, as on the iPhone: it is what every darts app already does.
    TOTAL,

    /// The three darts, one at a time.
    DARTS,
    ;

    public val label: String get() = if (this == TOTAL) "Total" else "Darts"
    public val spoken: String get() = if (this == TOTAL) "Enter the total of three darts" else "Enter each dart"

    public companion object {
        /// The keypad a match opens on. **A keep-scored-darts match opens on darts**, whatever was used last:
        /// under that rule a bust can only be recorded as darts, and a scorer who finds that out from a refusal
        /// mid-leg has been let down by the screen.
        public fun initial(stored: ThroEntryMode?, bustRule: BustRule): ThroEntryMode =
            if (bustRule == BustRule.KEEP_SCORED_DARTS) DARTS else stored ?: TOTAL

        public fun of(stored: String?): ThroEntryMode? = entries.firstOrNull { it.name == stored }
    }
}

/// The keypad last used, kept where the device id and the notice memory are: the app's one preferences file.
public class ThroScoringPreferences(context: android.content.Context) {
    private val prefs = context.getSharedPreferences("thro", android.content.Context.MODE_PRIVATE)

    public var entryMode: ThroEntryMode?
        get() = ThroEntryMode.of(prefs.getString(KEY, null))
        set(value) { prefs.edit().putString(KEY, value?.name).apply() }

    private companion object {
        const val KEY = "thro.scoring.entryMode"
    }

}
