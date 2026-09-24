package thro.api

import thro.engine.BustRule
import thro.engine.Command
import thro.engine.Dart
import thro.engine.Darts
import thro.engine.Effect
import thro.engine.PlayerId
import thro.engine.RejectionReason
import thro.engine.VisitReading

/**
 * A visit as the event log holds it, and the command it was (OD-023).
 *
 * Every reader that replays a match turns stored payloads back into engine commands, and before darts there was one
 * shape to turn back. Now there are two — a total, or the darts that made it — and a reader that got the choice wrong
 * would replay a visit as something other than what the scorer entered: T20 from 60 is a bust, and the same visit
 * read back as a total of 60 is a checkout. So the choice is made here, once, and every replay asks.
 *
 * A visit entered as darts is stored with `schema_version` 2: the darts, and beside them the total, dart counts and
 * effect the engine derived from them, so a reader that knows only totals still finds every field it read before.
 * The darts are what is replayed; the rest is a courtesy to older readers and is never read back in preference.
 */
internal object Visits {

    /** A visit given as a total — the only shape there was before OD-023. */
    const val TOTAL_SCHEMA: Int = 1

    /** A visit given as darts. */
    const val DARTS_SCHEMA: Int = 2

    /** The schema a visit's payload is written under. */
    fun schemaOf(cmd: Command): Int = if (cmd is Command.RecordDarts) DARTS_SCHEMA else TOTAL_SCHEMA

    /**
     * The command a stored visit was: its darts when it carries them, else its total. Null when it names no seat, or
     * holds neither — such a row is still evidence, it simply replays as nothing, as a refused visit always has.
     */
    fun commandOf(payload: Map<String, Any?>): Command? {
        val seat = payload["player"] as? String ?: return null
        val darts = payload["darts"] as? List<*>
        if (darts != null) {
            val read = darts.map { name -> (name as? String)?.let(Dart::parse) ?: return null }
            return Command.RecordDarts(PlayerId(seat), read)
        }
        val total = (payload["visitTotal"] as? Number)?.toInt() ?: return null
        return Command.RecordVisit(
            PlayerId(seat), total,
            (payload["dartsUsed"] as? Number)?.toInt(),
            (payload["dartsAtDouble"] as? Number)?.toInt(),
        )
    }

    fun commandOf(payloadText: String): Command? = commandOf(Json.parseObject(payloadText))

    /**
     * Dart names off the wire, as the scorer's screen sends them. Reading a name is syntax, so a name that is not one
     * is the caller's mistake and a 400 in a sentence; a name that reads but is not on the board — a treble bull — is
     * the engine's to refuse, with its reason.
     */
    fun parseDarts(raw: Any?, field: String = "darts"): List<Dart> {
        val list = raw as? List<*>
            ?: throw IllegalArgumentException("$field must be a list of dart names, like [\"T20\",\"T20\",\"D20\"]")
        if (list.isEmpty() || list.size > Darts.HAND) {
            throw IllegalArgumentException("a visit is one to three darts, and $field has ${list.size}")
        }
        return list.map { item ->
            val name = item as? String ?: throw IllegalArgumentException("every dart in $field is named as text, like \"T20\"")
            Dart.parse(name)
                ?: throw IllegalArgumentException("\"$name\" is not the name of a dart: a dart is named like T20, D16, 20, 25, Bull or Miss")
        }
    }

    /**
     * The payload a visit is stored under. [reading] is the engine's, when it accepted the visit: a darts visit
     * stores what the engine derived rather than anything the client said. The darts are written by their canonical
     * names, never as they arrived, so nothing a client typed reaches the log verbatim.
     */
    fun payload(player: String, cmd: Command, reading: VisitReading?, effect: String, extra: String = ""): String {
        fun n(v: Int?) = v?.toString() ?: "null"
        val (total, used, atDouble) = when (cmd) {
            is Command.RecordDarts -> Triple(reading?.visitTotal, reading?.dartsUsed, reading?.dartsAtDouble)
            is Command.RecordVisit -> Triple(cmd.visitTotal, cmd.dartsUsed, cmd.dartsAtDouble)
        }
        return buildString {
            append("{\"player\":\"").append(player).append("\",")
            append("\"visitTotal\":").append(n(total)).append(",")
            append("\"dartsUsed\":").append(n(used)).append(",")
            append("\"dartsAtDouble\":").append(n(atDouble)).append(",")
            if (cmd is Command.RecordDarts) {
                append("\"darts\":[").append(cmd.darts.joinToString(",") { "\"${it.name}\"" }).append("],")
            }
            append(extra)
            append("\"effect\":\"").append(effect).append("\"}")
        }
    }

    fun effectName(e: Effect): String = when (e) {
        Effect.SCORED -> "scored"
        Effect.BUST -> "bust"
        Effect.LEG_WON -> "leg_won"
        Effect.SET_WON -> "set_won"
        Effect.MATCH_WON -> "match_won"
    }

    /** What a refused visit is called in a sentence: its darts when it had them, else its total. */
    fun describe(cmd: Command): String = when (cmd) {
        is Command.RecordDarts -> cmd.darts.joinToString(", ") { it.name }
        is Command.RecordVisit -> cmd.visitTotal.toString()
    }

    /** The engine's refusal, as a sentence a person holding the phone can act on. */
    fun sentence(reason: RejectionReason, cmd: Command): String {
        val what = describe(cmd)
        return when (reason) {
            RejectionReason.IMPOSSIBLE_VISIT_TOTAL -> "no three darts score $what"
            RejectionReason.IMPOSSIBLE_OPENING_TOTAL -> "$what cannot be scored by a player who has not yet opened the leg"
            RejectionReason.VISIT_TOTAL_OUT_OF_RANGE -> "a visit scores between 0 and 180, and $what does not"
            RejectionReason.DARTS_USED_INVALID ->
                "$what is not a visit: one to three darts, three unless the leg was won, and none after the visit was decided"
            RejectionReason.DARTS_AT_DOUBLE_INVALID -> "the darts at a double do not fit a visit of $what from that score"
            RejectionReason.NOT_YOUR_TURN -> "it was not that seat's turn to throw"
            RejectionReason.MATCH_COMPLETE -> "the match was already over"
            RejectionReason.DART_INVALID -> "one of $what is not on the board"
            RejectionReason.DARTS_REQUIRED ->
                "$what busts, and this match keeps the darts scored before a bust, so that visit has to be entered dart by dart"
        }
    }
}

/**
 * A bust rule as the wire names it (OD-023): `restoreVisit` or `keepScoredDarts`. The store says `restore_visit`
 * and `keep_scored_darts` (V059); the wire follows the camel case every other client-facing name uses.
 */
internal fun bustRuleName(rule: BustRule): String = when (rule) {
    BustRule.RESTORE_VISIT -> "restoreVisit"
    BustRule.KEEP_SCORED_DARTS -> "keepScoredDarts"
}

/** The bust rule a wire name means; absent means the standard rule, and anything else is not one THRØ plays. */
internal fun bustRuleOf(name: String?): BustRule = when (name) {
    null, "restoreVisit" -> BustRule.RESTORE_VISIT
    "keepScoredDarts" -> BustRule.KEEP_SCORED_DARTS
    else -> throw IllegalArgumentException("format.bustRule is restoreVisit or keepScoredDarts, not $name")
}
