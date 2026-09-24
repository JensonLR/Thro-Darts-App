package thro.api

import java.sql.Connection
import java.util.UUID
import thro.engine.Command
import thro.engine.Effect
import thro.engine.Engine
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId
import thro.engine.RuleTables
import thro.stats.Basis
import thro.stats.Stat
import thro.stats.Statistics
import thro.stats.VisitRecord

/**
 * Turns one device's account of a match into the per-visit records the statistics layer consumes.
 *
 * The event payload carries what the scorer was told — the player and the visit total with its two
 * optional dart counts, or since OD-023 the darts themselves. It does not carry the remaining before and after, or whether the visit
 * busted or won the leg, because those are **derived** facts and storing them would let a stored
 * copy disagree with the rules. They are recovered here the only honest way: by replaying the log
 * through the same engine that accepted it.
 *
 * This is a projection, so it is rebuildable and never a source of truth. Nothing here writes.
 */
public class StatsProjection(private val connection: Connection) {

    /** A record with the competitor it belongs to, since every figure is a property of one player. */
    public data class Attributed(val player: String, val record: VisitRecord)

    /**
     * @param format the match's own format, from the aggregate. It is **not** optional and it is not
     *   defaulted, because that is exactly how this went wrong: the projection replayed every match
     *   under a fixed 501 / double-out / first-to-five while the command path rehydrated from the
     *   match's stored format. A match stored as 301 was replayed as 501, so every remaining was
     *   wrong; a match stored as straight-out had busts fabricated at a remainder of one. The
     *   figures then disagreed with the scoreboard that produced them — the precise failure the
     *   shared-format comment was written to prevent.
     */
    public fun visitsFor(
        matchId: UUID, deviceId: UUID, home: String, away: String, format: MatchFormat,
    ): List<Attributed> {
        val h = PlayerId(home)
        val a = PlayerId(away)
        var state = MatchState.start(format, h, a)
        val out = mutableListOf<Attributed>()
        // Ordinals are per competitor per leg: firstNineAverage takes a player's first three
        // visits of a leg, so a counter shared across both players would take the wrong three.
        val ordinals = mutableMapOf<Pair<String, Int>, Int>()

        connection.prepareStatement(
            """
            SELECT payload::text
            FROM evidence.event
            WHERE match_id = ? AND device_id = ? AND event_type = 'VisitRecorded'
            ORDER BY device_seq
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, deviceId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val visit = Visits.commandOf(rs.getString(1)) ?: continue
                    val player = when (visit) {
                        is Command.RecordVisit -> visit.player
                        is Command.RecordDarts -> visit.player
                    }

                    val legBefore = state.currentLeg
                    val before = state.remaining[player] ?: continue
                    val outcome = Engine.apply(state, visit)
                    if (outcome !is Outcome.Accepted) continue
                    // What the visit amounted to is the engine's reading, not the payload's: a darts visit
                    // carries no total of its own worth trusting, and under the keep rule a bust scores the
                    // darts before the busting one — which only the reading says.
                    val reading = outcome.reading
                    val total = reading?.visitTotal ?: (visit as? Command.RecordVisit)?.visitTotal ?: continue
                    val darts = reading?.dartsUsed ?: (visit as? Command.RecordVisit)?.dartsUsed
                    val atDouble = reading?.dartsAtDouble ?: (visit as? Command.RecordVisit)?.dartsAtDouble

                    val key = player.value to legBefore
                    val visitOrdinal = (ordinals[key] ?: 0) + 1
                    ordinals[key] = visitOrdinal
                    val bust = outcome.effect == Effect.BUST
                    val won = outcome.effect in setOf(Effect.LEG_WON, Effect.SET_WON, Effect.MATCH_WON)
                    out += Attributed(player.value, VisitRecord(
                        legOrdinal = legBefore,
                        visitOrdinal = visitOrdinal,
                        visitTotal = total,
                        dartsUsed = darts,
                        bust = bust,
                        remainingBefore = before,
                        // A win takes them to zero. Anything else leaves them where the engine put them —
                        // not "where they started if it bust", which is the standard rule's answer and wrong
                        // under a league that keeps the darts scored before the bust.
                        remainingAfter = if (won) 0 else outcome.state.remaining.getValue(player),
                        wonLeg = won,
                        dartsAtDouble = atDouble,
                        scored = reading?.scored,
                    ))
                    state = outcome.state
                }
            }
        }
        return out
    }

    /** Every figure below is a property of one competitor, so it is taken over that player's visits. */
    public fun summaryFor(
        matchId: UUID,
        deviceId: UUID,
        home: String,
        away: String,
        player: String,
        format: MatchFormat,
    ): String {
        val mine = visitsFor(matchId, deviceId, home, away, format)
            .filter { it.player == player }
            .map { it.record }
        // The checkable set is a property of the match's out-rule, not a constant. Under straight-out
        // more remainings are finishable than under double-out, so a checkout percentage taken
        // against the double-out set would be measured against positions the player was never in.
        val checkable = RuleTables.checkouts(format.outRule)
        val figures = linkedMapOf(
            "threeDartAverage" to Statistics.threeDartAverage(mine),
            "firstNineAverage" to Statistics.firstNineAverage(mine),
            "checkoutPercentage" to Statistics.checkoutPercentage(mine, checkable),
            "doublesAttempted" to Statistics.doublesAttempted(mine, checkable),
            "highestCheckout" to Statistics.highestCheckout(mine),
            "maximums" to Statistics.maximums(mine),
            "hundredPlus" to Statistics.scoresAtLeast(mine, 100),
            "oneFortyPlus" to Statistics.scoresAtLeast(mine, 140),
            "bestLegInVisits" to Statistics.bestLegInVisits(mine),
            "finishRateFromCheckable" to Statistics.finishRateFromCheckablePosition(mine, checkable),
        )
        return figures.entries.joinToString(",", "{", "}") { (k, v) -> "\"$k\":${v.toJson()}" }
    }
}

/** The wire shape from PD-001: a figure never crosses the boundary without its basis. */
internal fun Stat.toJson(): String {
    val parts = mutableListOf("\"basis\":\"${basis.name}\"")
    when (basis) {
        Basis.EXACT -> parts += "\"value\":${value.fmt()}"
        Basis.BOUNDED -> {
            parts += "\"lower\":${lower.fmt()}"
            parts += "\"upper\":${upper.fmt()}"
        }
        Basis.UNAVAILABLE -> Unit
    }
    parts += "\"evidenceLevel\":\"${evidenceLevel.name}\""
    parts += "\"sampleSize\":$sampleSize"
    note?.let { parts += "\"note\":\"${it.replace("\\", "\\\\").replace("\"", "\\\"")}\"" }
    return parts.joinToString(",", "{", "}")
}

/** Two decimal places, without a locale and without floating-point noise in the output. */
private fun Double?.fmt(): String {
    if (this == null) return "null"
    val scaled = java.math.BigDecimal(this).setScale(2, java.math.RoundingMode.HALF_UP)
    return scaled.toPlainString()
}
