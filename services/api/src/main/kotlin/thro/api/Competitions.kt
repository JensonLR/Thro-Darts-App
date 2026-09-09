package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.competition.Bracket
import thro.competition.Entrant
import thro.competition.EntrantKind
import thro.competition.EventAccess

/**
 * The event lifecycle: editions, entries, check-in and the draw.
 *
 * Check-in is where this module earns its place. ADR-006 issues a scoring grant there rather than
 * at match-open, because match-open is the moment the design draws but nothing guarantees a network
 * at it — and a player arriving at a dead-signal venue must still be able to score. Check-in is
 * inherently online, since it is how the organiser knows who is present.
 *
 * An `event` is one edition of a tournament (ADR-017). It is not a league season: nothing here
 * affiliates a team or registers a player, and nothing in a league season enters, checks in or
 * draws.
 */
public class Competitions(private val connection: Connection) {

    public data class CheckedIn(val grantId: UUID, val expiresWith: Instant)

    public fun openEvent(
        eventId: UUID,
        name: String,
        startsAt: Instant,
        sessionEndsAt: Instant,
        venueLabel: String? = null,
        venueId: UUID? = null,
        tournamentId: UUID? = null,
        entrantKind: EntrantKind = EntrantKind.PLAYER,
        access: EventAccess = EventAccess.OPEN,
        entriesCloseAt: Instant? = null,
        capacity: Int? = null,
    ) {
        connection.prepareStatement(
            """
            INSERT INTO competition.event
              (event_id, name, venue_label, venue_id, tournament_id, starts_at, session_ends_at,
               entrant_kind, access, entries_close_at, capacity)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId); ps.setString(2, name); ps.setString(3, venueLabel)
            ps.setObject(4, venueId); ps.setObject(5, tournamentId)
            ps.setObject(6, java.sql.Timestamp.from(startsAt))
            ps.setObject(7, java.sql.Timestamp.from(sessionEndsAt))
            ps.setString(8, entrantKind.name.lowercase())
            ps.setString(9, access.name.lowercase())
            ps.setObject(10, entriesCloseAt?.let { java.sql.Timestamp.from(it) })
            if (capacity == null) ps.setNull(11, java.sql.Types.INTEGER) else ps.setInt(11, capacity)
            ps.executeUpdate()
        }
    }

    /**
     * Enters an entrant. The kind is checked twice — here by the sealed type, and in the database
     * by a foreign key onto the event's declared kind — because an entry that is quietly the wrong
     * shape corrupts the draw.
     */
    public fun enter(eventId: UUID, entrant: Entrant, seed: Int? = null): UUID {
        val id = UUID.randomUUID()
        val column = when (entrant) {
            is Entrant.Player -> "player_id"
            is Entrant.Pair -> "pair_id"
            is Entrant.Team -> "team_id"
        }
        connection.prepareStatement(
            "INSERT INTO competition.entry (entry_id, event_id, entrant_kind, $column, seed) VALUES (?, ?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, eventId)
            ps.setString(3, entrant.kind.name.lowercase())
            ps.setObject(4, UUID.fromString(entrant.competitorId))
            if (seed == null) ps.setNull(5, java.sql.Types.INTEGER) else ps.setInt(5, seed)
            ps.executeUpdate()
        }
        return id
    }

    /** A single player's entry. */
    public fun enter(eventId: UUID, playerId: UUID, seed: Int? = null): UUID =
        enter(eventId, Entrant.Player(playerId.toString()), seed)

    /**
     * Checks a competitor in on a device, and issues the scoring grant that lets them score all day
     * with no network.
     *
     * The grant's lifetime is the event's stated session end plus 24 hours. An organiser who sets
     * that end time too early is the one way to make grants lapse mid-event, which is why it is a
     * column on the event rather than a constant.
     *
     * [playerId] is the person present. For a single-player entry it is the competitor; for a pair
     * or a team it is whichever member checked the side in. The grant is still issued to the
     * competitor until V015 makes the grant actor a player (see the execution plan §4).
     */
    public fun checkIn(
        eventId: UUID,
        competitorId: UUID,
        deviceId: UUID,
        byOrganiser: UUID,
        playerId: UUID? = competitorId,
    ): CheckedIn {
        val sessionEnd = sessionEndOf(eventId)
            ?: throw IllegalArgumentException("no such event")
        val grantId = Grants(connection).issue(
            eventId = eventId, actorId = competitorId, deviceId = deviceId,
            actorRole = "participant", sessionEndsAt = sessionEnd, issuedBy = byOrganiser,
        )
        connection.prepareStatement(
            """
            INSERT INTO competition.check_in (event_id, competitor_id, device_id, grant_id, player_id)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (event_id, competitor_id, device_id)
              DO UPDATE SET grant_id = EXCLUDED.grant_id, player_id = EXCLUDED.player_id,
                            checked_in_at = clock_timestamp()
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId); ps.setObject(2, competitorId)
            ps.setObject(3, deviceId); ps.setObject(4, grantId); ps.setObject(5, playerId)
            ps.executeUpdate()
        }
        return CheckedIn(grantId, sessionEnd)
    }

    /**
     * Makes the first-round draw from the entries, using the bracket maths.
     *
     * Byes are stored as bracket ties with one competitor so the bracket keeps its shape, and never
     * as a played result: a bye is not a win, produces no statistics and creates no match.
     */
    public fun draw(eventId: UUID): List<UUID> {
        val entries = entriesOf(eventId).map { it.first }
        require(entries.isNotEmpty()) { "an event with no entries cannot be drawn" }
        val math = Bracket.math(entries.size)

        // `Bracket.firstRound` returns the bye holders and a count of preliminary matches; it does
        // not pair the remaining competitors, so the pairing is done here rather than pretending
        // its Undetermined placeholders are ties.
        val byeHolders = entries.take(math.byes)
        val playing = entries.drop(math.byes)
        check(playing.size == math.preliminaryMatches * 2) {
            "bracket maths and the field disagree: ${playing.size} competitors into " +
                "${math.preliminaryMatches} matches"
        }

        val created = mutableListOf<UUID>()
        var position = 0

        // Byes go to the highest seeds, which is what the approved organiser design specifies.
        // A bye is not a win: it creates no match and produces no statistics.
        for (competitor in byeHolders) {
            position += 1
            created += insertTie(eventId, position, competitor, null, isBye = true)
        }
        for (i in playing.indices step 2) {
            position += 1
            created += insertTie(eventId, position, playing[i], playing[i + 1], isBye = false)
        }

        connection.prepareStatement("UPDATE competition.event SET state = 'drawn' WHERE event_id = ?")
            .use { ps -> ps.setObject(1, eventId); ps.executeUpdate() }
        return created
    }

    private fun insertTie(
        eventId: UUID, position: Int, home: UUID, away: UUID?, isBye: Boolean,
    ): UUID {
        val id = UUID.randomUUID()
        connection.prepareStatement(
            """
            INSERT INTO competition.bracket_tie
              (fixture_id, event_id, round_number, position, home_id, away_id, is_bye)
            VALUES (?, ?, 1, ?, ?, ?, ?)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id); ps.setObject(2, eventId); ps.setInt(3, position)
            ps.setObject(4, home); ps.setObject(5, away); ps.setBoolean(6, isBye)
            ps.executeUpdate()
        }
        return id
    }

    private fun entriesOf(eventId: UUID): List<Pair<UUID, Int?>> {
        val out = mutableListOf<Pair<UUID, Int?>>()
        connection.prepareStatement(
            """
            SELECT competitor_id, seed FROM competition.entry
             WHERE event_id = ? AND withdrawn_at IS NULL
             ORDER BY seed NULLS LAST, entered_at
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId)
            ps.executeQuery().use { rs ->
                while (rs.next()) out += (rs.getObject(1) as UUID) to (rs.getObject(2) as Int?)
            }
        }
        return out
    }

    private fun sessionEndOf(eventId: UUID): Instant? {
        connection.prepareStatement("SELECT session_ends_at FROM competition.event WHERE event_id = ?")
            .use { ps ->
                ps.setObject(1, eventId)
                ps.executeQuery().use { rs ->
                    return if (rs.next()) rs.getTimestamp(1).toInstant() else null
                }
            }
    }
}
