package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID

/**
 * The public front of what is coming up: open-entry events that have not started, with the venue
 * they are at. What Discover's "Tournaments" section reads without an account.
 *
 * Public means public here too: `access = 'open'` only — a members-only or invitational event is
 * not advertised to a stranger — public venues only, and nothing on a row is a person. Entry
 * counts, eligibility and "are you in" are the signed-in discovery model's (`/v1/me/discovery`);
 * this is the notice on the pub door, not the entry form.
 */
public class Events(private val connection: Connection) {

    public data class Venue(val venueId: UUID, val name: String, val locality: String?, val postcode: String?,
                            val latitude: Double?, val longitude: Double?)
    public data class Upcoming(val eventId: UUID, val name: String, val tournament: String?, val venue: Venue?,
                               val venueLabel: String?, val startsAt: Instant, val entriesCloseAt: Instant?,
                               val entrantKind: String, val capacity: Int?)

    public fun upcoming(from: Instant, limit: Int = 100): List<Upcoming> =
        connection.prepareStatement(
            """
            SELECT e.event_id, e.name, t.name,
                   v.venue_id, v.name, v.locality, v.postcode, v.latitude, v.longitude, e.venue_label,
                   e.starts_at, e.entries_close_at, e.entrant_kind, e.capacity
              FROM competition.event e
              LEFT JOIN competition.tournament t ON t.tournament_id = e.tournament_id
              LEFT JOIN competition.venue v ON v.venue_id = e.venue_id AND v.visibility = 'public'
             WHERE e.access = 'open' AND e.state IN ('open', 'entries_closed') AND e.starts_at >= ?
             ORDER BY e.starts_at, e.name
             LIMIT ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, java.sql.Timestamp.from(from)); ps.setInt(2, limit.coerceIn(1, 200))
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null else Upcoming(
                        rs.getObject(1) as UUID, rs.getString(2), rs.getString(3),
                        (rs.getObject(4) as UUID?)?.let { Venue(it, rs.getString(5), rs.getString(6), rs.getString(7), rs.getBigDecimal(8)?.toDouble(), rs.getBigDecimal(9)?.toDouble()) },
                        rs.getString(10), rs.getTimestamp(11).toInstant(), rs.getTimestamp(12)?.toInstant(),
                        rs.getString(13), rs.getObject(14) as Int?,
                    )
                }.toList()
            }
        }

    public fun json(events: List<Upcoming>): String {
        fun q(s: String?) = s?.let { "\"" + it.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"" } ?: "null"
        return "{\"events\":[" + events.joinToString(",") { e ->
            """{"eventId":"${e.eventId}","name":${q(e.name)},"tournament":${q(e.tournament)},"venue":""" + (e.venue?.let { v ->
                """{"venueId":"${v.venueId}","name":${q(v.name)},"locality":${q(v.locality)},"postcode":${q(v.postcode)},"latitude":${v.latitude ?: "null"},"longitude":${v.longitude ?: "null"}}"""
            } ?: "null") + ""","venueLabel":${q(e.venueLabel)},"startsAt":"${e.startsAt}","entriesCloseAt":${e.entriesCloseAt?.let { "\"$it\"" } ?: "null"},"entrantKind":${q(e.entrantKind)},"capacity":${e.capacity ?: "null"}}"""
        } + "]}"
    }
}
