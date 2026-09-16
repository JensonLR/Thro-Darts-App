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
        playerId: UUID = competitorId,
    ): CheckedIn {
        val sessionEnd = sessionEndOf(eventId)
            ?: throw IllegalArgumentException("no such event")
        // The grant is the person's, not the entry's (V020): it is what evidence recorded from
        // their device is annotated with, and a pair or a team cannot hold a phone.
        val grantId = Grants(connection).issue(
            eventId = eventId, actorId = playerId, deviceId = deviceId,
            actorRole = "participant", sessionEndsAt = sessionEnd, issuedBy = byOrganiser,
        )
        connection.prepareStatement(
            """
            INSERT INTO competition.check_in (event_id, competitor_id, device_id, grant_id, player_id)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (event_id, player_id, device_id)
              DO UPDATE SET grant_id = EXCLUDED.grant_id, competitor_id = EXCLUDED.competitor_id,
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

        // The bracket's slots in seed order (PD-115): 1 at the top, 2 at the bottom, 3 and 4 in the other quarters,
        // and so on — so the top seeds cannot meet before the final. Entries come ranked by seed then by when they
        // entered; a slot whose rank is beyond the field is empty, and its neighbour has a bye. Because the empty
        // slots are the lowest ranks and the lowest ranks sit opposite the highest, the byes go to the highest seeds,
        // as the approved organiser design specifies — and the count is the bracket maths' count.
        val slots = seedOrder(math.bracketSize)
        check(slots.size == math.byes * 2 + math.preliminaryMatches * 2 || math.bracketSize == 1) { "bracket maths and the field disagree" }

        val created = mutableListOf<UUID>()
        var position = 0
        for (i in slots.indices step 2) {
            val home = entries.getOrNull(slots[i]); val away = entries.getOrNull(slots[i + 1])
            when {
                home != null && away != null -> { position += 1; created += insertTie(eventId, position, home, away, isBye = false) }
                home != null -> { position += 1; created += insertTie(eventId, position, home, null, isBye = true) }
                away != null -> { position += 1; created += insertTie(eventId, position, away, null, isBye = true) }
                else -> Unit // two empty slots: a field smaller than half the bracket, which the maths never produces
            }
        }
        check(created.size == math.byes + math.preliminaryMatches) { "the draw made ${created.size} ties for ${math.byes} byes and ${math.preliminaryMatches} matches" }

        connection.prepareStatement("UPDATE competition.event SET state = 'drawn' WHERE event_id = ?")
            .use { ps -> ps.setObject(1, eventId); ps.executeUpdate() }
        return created
    }

    /** Ranks in slot order for a bracket of [size] (a power of two): [0], then [0,1], [0,3,1,2], [0,7,3,4,1,6,2,5]… */
    private fun seedOrder(size: Int): List<Int> {
        var order = listOf(0)
        while (order.size < size) {
            val n = order.size * 2
            order = order.flatMap { listOf(it, n - 1 - it) }
        }
        return order
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
