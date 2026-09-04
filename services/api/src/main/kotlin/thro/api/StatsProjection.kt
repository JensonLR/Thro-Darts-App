package thro.api

import java.sql.Connection
import java.util.UUID
import thro.engine.Command
import thro.engine.Effect
import thro.engine.Engine
import thro.engine.MatchState
import thro.engine.OutRule
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
 * The event payload carries what the scorer was told — the player, the visit total, and the two
 * optional dart counts. It does not carry the remaining before and after, or whether the visit
 * busted or won the leg, because those are **derived** facts and storing them would let a stored
 * copy disagree with the rules. They are recovered here the only honest way: by replaying the log
 * through the same engine that accepted it.
 *
 * This is a projection, so it is rebuildable and never a source of truth. Nothing here writes.
 */
public class StatsProjection(private val connection: Connection) {

    /** A record with the competitor it belongs to, since every figure is a property of one player. */
    public data class Attributed(val player: String, val record: VisitRecord)

    public fun visitsFor(matchId: UUID, deviceId: UUID, home: String, away: String): List<Attributed> {
        val h = PlayerId(home)
        val a = PlayerId(away)
        var state = MatchState.start(playtestFormat(h), h, a)
        val out = mutableListOf<Attributed>()
        // Ordinals are per competitor per leg: firstNineAverage takes a player's first three
        // visits of a leg, so a counter shared across both players would take the wrong three.
        val ordinals = mutableMapOf<Pair<String, Int>, Int>()

        connection.prepareStatement(
            """
            SELECT payload->>'player' AS player,
                   (payload->>'visitTotal')::int AS visit_total,
                   payload->>'dartsUsed' AS darts_used,
                   payload->>'dartsAtDouble' AS darts_at_double
            FROM evidence.event
            WHERE match_id = ? AND device_id = ? AND event_type = 'VisitRecorded'
            ORDER BY device_seq
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, deviceId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val player = PlayerId(rs.getString("player"))
                    val total = rs.getInt("visit_total")
                    val darts = rs.getString("darts_used")?.toIntOrNull()
                    val atDouble = rs.getString("darts_at_double")?.toIntOrNull()

                    val legBefore = state.currentLeg
                    val before = state.remaining.getValue(player)
                    val outcome = Engine.apply(state, Command.RecordVisit(player, total, darts, atDouble))
                    if (outcome !is Outcome.Accepted) continue

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
                        // a bust leaves the player where they started; a win takes them to zero
                        remainingAfter = if (won) 0 else if (bust) before else before - total,
                        wonLeg = won,
                        dartsAtDouble = atDouble,
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
    ): String {
        val mine = visitsFor(matchId, deviceId, home, away)
            .filter { it.player == player }
            .map { it.record }
        val checkable = RuleTables.checkouts(OutRule.DOUBLE)
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
