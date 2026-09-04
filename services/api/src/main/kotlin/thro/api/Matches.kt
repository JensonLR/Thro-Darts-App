package thro.api

import java.sql.Connection
import java.util.UUID
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode

/** Who is playing and under what rules, as the store holds it. */
public data class MatchAggregate(
    val matchId: UUID,
    val eventId: UUID?,
    val homeId: UUID,
    val awayId: UUID,
    val homeName: String,
    val awayName: String,
    val format: MatchFormat,
) {
    public val participants: Set<UUID> get() = setOf(homeId, awayId)

    /** The engine works in display names; the store works in identifiers. This is the join. */
    public fun playerFor(id: UUID): PlayerId? = when (id) {
        homeId -> PlayerId(homeName)
        awayId -> PlayerId(awayName)
        else -> null
    }

    public fun idFor(name: String): UUID? = when (name) {
        homeName -> homeId
        awayName -> awayId
        else -> null
    }
}

/**
 * The match aggregate: the authoritative answer to "who is playing this match".
 *
 * ADR-008's highest-value attack is cross-match evidence injection — post a leg event carrying a
 * stranger's match id and you move a stranger's rating. The defence is that the participant set is
 * **loaded from here**, never taken from the request. Every caller that used to pass names in is
 * now passing a hint at best; the store decides.
 */
public class Matches(private val connection: Connection) {

    public fun open(
        matchId: UUID,
        homeId: UUID,
        awayId: UUID,
        homeName: String,
        awayName: String,
        format: MatchFormat,
        eventId: UUID? = null,
    ) {
        connection.prepareStatement(
            """
            INSERT INTO evidence.match
              (match_id, event_id, home_id, away_id, home_name, away_name, starting_score,
               in_rule, out_rule, legs_mode, legs_target, throw_first)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, eventId)
            ps.setObject(3, homeId)
            ps.setObject(4, awayId)
            ps.setString(5, homeName)
            ps.setString(6, awayName)
            ps.setInt(7, format.startingScore)
            ps.setString(8, format.inRule.name.lowercase())
            ps.setString(9, format.outRule.name.lowercase())
            ps.setString(10, format.legs.mode.name.lowercase())
            ps.setInt(11, format.legs.target)
            ps.setObject(12, if (format.throwFirst.value == homeName) homeId else awayId)
            ps.executeUpdate()
        }
    }

    public fun load(matchId: UUID): MatchAggregate? {
        connection.prepareStatement(
            """
            SELECT match_id, event_id, home_id, away_id, home_name, away_name, starting_score,
                   in_rule, out_rule, legs_mode, legs_target, throw_first
              FROM evidence.match WHERE match_id = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.executeQuery().use { rs ->
                if (!rs.next()) return null
                val homeId = rs.getObject("home_id") as UUID
                val homeName = rs.getString("home_name")
                val awayName = rs.getString("away_name")
                val first = rs.getObject("throw_first") as UUID
                return MatchAggregate(
                    matchId = rs.getObject("match_id") as UUID,
                    eventId = rs.getObject("event_id") as UUID?,
                    homeId = homeId,
                    awayId = rs.getObject("away_id") as UUID,
                    homeName = homeName,
                    awayName = awayName,
                    format = MatchFormat(
                        startingScore = rs.getInt("starting_score"),
                        inRule = InRule.valueOf(rs.getString("in_rule").uppercase()),
                        outRule = OutRule.valueOf(rs.getString("out_rule").uppercase()),
                        legs = Structure(
                            StructureMode.valueOf(rs.getString("legs_mode").uppercase()),
                            rs.getInt("legs_target"),
                        ),
                        throwFirst = PlayerId(if (first == homeId) homeName else awayName),
                    ),
                )
            }
        }
    }
}
