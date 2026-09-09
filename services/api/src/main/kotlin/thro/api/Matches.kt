package thro.api

import java.sql.Connection
import java.util.UUID
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * The engine's two labels. Seats, not people: evidence names the seat that threw, and the aggregate
 * — fixed when the match opened — says who sat there. A display name is joined from the identity
 * module at render time and is never stored beside evidence (OD-024, V018).
 */
public object Seat {
    public const val HOME: String = "home"
    public const val AWAY: String = "away"
    public val home: PlayerId = PlayerId(HOME)
    public val away: PlayerId = PlayerId(AWAY)
}

/** Who is playing and under what rules, as the store holds it. */
public data class MatchAggregate(
    val matchId: UUID,
    val eventId: UUID?,
    val homeId: UUID,
    val awayId: UUID,
    val format: MatchFormat,
) {
    public val participants: Set<UUID> get() = setOf(homeId, awayId)

    /** The engine works in seats; the store works in identifiers. This is the join. */
    public fun playerFor(id: UUID): PlayerId? = when (id) {
        homeId -> Seat.home
        awayId -> Seat.away
        else -> null
    }

    public fun idFor(seat: String): UUID? = when (seat) {
        Seat.HOME -> homeId
        Seat.AWAY -> awayId
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

    /**
     * Opens a match between two competitors. No name is taken, because none may be stored: the
     * format's `throwFirst` names a seat, and the seats are bound to [homeId] and [awayId] here.
     */
    public fun open(
        matchId: UUID,
        homeId: UUID,
        awayId: UUID,
        format: MatchFormat,
        eventId: UUID? = null,
    ) {
        require(format.throwFirst.value == Seat.HOME || format.throwFirst.value == Seat.AWAY) {
            "throwFirst names a seat, ${Seat.HOME} or ${Seat.AWAY}, never a person"
        }
        connection.prepareStatement(
            """
            INSERT INTO evidence.match
              (match_id, event_id, home_id, away_id, starting_score,
               in_rule, out_rule, legs_mode, legs_target, throw_first)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.setObject(2, eventId)
            ps.setObject(3, homeId)
            ps.setObject(4, awayId)
            ps.setInt(5, format.startingScore)
            ps.setString(6, format.inRule.name.lowercase())
            ps.setString(7, format.outRule.name.lowercase())
            ps.setString(8, format.legs.mode.name.lowercase())
            ps.setInt(9, format.legs.target)
            ps.setObject(10, if (format.throwFirst.value == Seat.HOME) homeId else awayId)
            ps.executeUpdate()
        }
    }

    public fun load(matchId: UUID): MatchAggregate? {
        connection.prepareStatement(
            """
            SELECT match_id, event_id, home_id, away_id, starting_score,
                   in_rule, out_rule, legs_mode, legs_target, throw_first
              FROM evidence.match WHERE match_id = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.executeQuery().use { rs ->
                if (!rs.next()) return null
                val homeId = rs.getObject("home_id") as UUID
                val first = rs.getObject("throw_first") as UUID
                return MatchAggregate(
                    matchId = rs.getObject("match_id") as UUID,
                    eventId = rs.getObject("event_id") as UUID?,
                    homeId = homeId,
                    awayId = rs.getObject("away_id") as UUID,
                    format = MatchFormat(
                        startingScore = rs.getInt("starting_score"),
                        inRule = InRule.valueOf(rs.getString("in_rule").uppercase()),
                        outRule = OutRule.valueOf(rs.getString("out_rule").uppercase()),
                        legs = Structure(
                            StructureMode.valueOf(rs.getString("legs_mode").uppercase()),
                            rs.getInt("legs_target"),
                        ),
                        throwFirst = if (first == homeId) Seat.home else Seat.away,
                    ),
                )
            }
        }
    }
}
