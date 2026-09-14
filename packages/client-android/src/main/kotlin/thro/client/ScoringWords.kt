package thro.client

import thro.engine.RejectionReason
import thro.engine.RuleTables

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

    /// The line under the two scores: what just happened, or what is being typed, or the route out.
    ///
    /// **What is typed outranks what happened**, because the player is looking at their own fingers. The
    /// mark from the last visit is what they read when they are not typing.
    public fun say(session: ThroSession, typed: String): String {
        if (typed.isNotEmpty()) return typed
        return when (val mark = session.mark) {
            is ThroMark.Refused -> refused(mark.reason)
            is ThroMark.Bust -> "Bust"
            is ThroMark.Scored -> checkoutOrEmpty(session)
            ThroMark.LegWon -> "Leg"
            ThroMark.MatchWon -> session.state.winner
                ?.let { session.name(if (it == session.state.home) thro.journal.Seat.HOME else thro.journal.Seat.AWAY) }
                ?.let { "$it wins" } ?: "Match"
            is ThroMark.Trouble -> mark.message
            null -> checkoutOrEmpty(session)
        }
    }

    /// The route, when the thrower is on one. **Derived by the engine's own tables**, never by this screen:
    /// the checkout shown must be the one for that number under that match's out-rule, which is PD-013 and
    /// the reason there is no table of finishes anywhere in the UI.
    private fun checkoutOrEmpty(session: ThroSession): String {
        val seat = session.throwerSeat ?: return ""
        val route = RuleTables.route(session.remaining(seat), session.state.format.outRule) ?: return ""
        return route.joinToString(" ")
    }

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
    }
}
