package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.UUID

/**
 * "Show me darts I can play." Execution plan §8 and Phase E, at the store level.
 *
 * Every card says **why it appears**. A card without reasons is a recommendation THRØ cannot
 * explain, and an event ranked by anything a sponsor could buy would be exactly the objectivity
 * failure the foundation report warns about (§13). So this is a read over facts — dates, venues,
 * entrant kinds, access, the player's own entries and series — and the reasons are the facts.
 *
 * Honest limits, stated in the card rather than papered over: capacity and closing date are what
 * the organiser declared, and "not stated" is a value; eligibility for `qualified`, `restricted`
 * and `member_only` events is a policy of the event that is not yet modelled, so those events
 * appear with "eligibility not yet checkable by THRØ", never as eligible.
 */
public class Discovery(private val connection: Connection) {

    private val london = ZoneId.of("Europe/London")

    public enum class Section { THIS_WEEKEND, NEAR_YOU, CLOSING_SOON, YOU_ARE_ELIGIBLE, YOUR_SERIES, ALREADY_ENTERED, ALL }

    public data class Card(
        val eventId: UUID,
        val name: String,
        val tournamentName: String?,
        val venueName: String?,
        val locality: String?,
        val startsAt: Instant,
        val entriesCloseAt: Instant?,
        val entrantKind: String,
        val access: String,
        val capacity: Int?,
        val liveEntries: Int,
        val entered: Boolean,
        val seriesLabels: List<String>,
        val reasons: List<String>,
    ) {
        /** Null when the organiser has not stated a capacity: "not stated", never "unlimited". */
        public val spotsRemaining: Int? get() = capacity?.let { (it - liveEntries).coerceAtLeast(0) }
    }

    /**
     * Upcoming events for a player between [from] and [to], with the sections each belongs to and
     * the reasons it appears. [homeLocality] is the player's team's locality where known; nothing
     * here reads a person's location.
     */
    public fun forPlayer(playerId: UUID, from: Instant, to: Instant, homeLocality: String? = null): Map<Section, List<Card>> {
        val cards = mutableListOf<Card>()
        val mySeries = seriesEnteredBy(playerId, from)
        connection.prepareStatement(
            """
            SELECT e.event_id, e.name, t.name, v.name, coalesce(v.locality, e.venue_label), e.starts_at, e.entries_close_at,
                   e.entrant_kind, e.access, e.capacity,
                   (SELECT count(*) FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL),
                   EXISTS (SELECT 1 FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL
                             AND (en.player_id = ? OR en.pair_id IN (SELECT pair_id FROM competition.pair WHERE player_a = ? OR player_b = ?)
                                  OR en.team_id IN (SELECT team_id FROM competition.team_membership WHERE player_id = ? AND valid_until IS NULL AND status = 'active'))),
                   (SELECT coalesce(array_agg(s.name || ' ' || ss.label ORDER BY s.name), '{}')
                      FROM competition.series_event se JOIN competition.series_season ss ON ss.series_season_id = se.series_season_id
                      JOIN competition.series s ON s.series_id = ss.series_id WHERE se.event_id = e.event_id),
                   (SELECT coalesce(array_agg(se.series_season_id::text), '{}') FROM competition.series_event se WHERE se.event_id = e.event_id)
              FROM competition.event e
              LEFT JOIN competition.tournament t ON t.tournament_id = e.tournament_id
              LEFT JOIN competition.venue v ON v.venue_id = e.venue_id
             WHERE e.starts_at >= ? AND e.starts_at <= ? AND e.state IN ('open','entries_closed','drawn')
             ORDER BY e.starts_at
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, playerId); ps.setObject(2, playerId); ps.setObject(3, playerId); ps.setObject(4, playerId)
            ps.setObject(5, Timestamp.from(from)); ps.setObject(6, Timestamp.from(to))
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val startsAt = rs.getTimestamp(6).toInstant()
                    val closes = rs.getTimestamp(7)?.toInstant()
                    val kind = rs.getString(8)
                    val access = rs.getString(9)
                    val entered = rs.getBoolean(12)
                    val seriesLabels = (rs.getArray(13).array as Array<*>).map { it.toString() }
                    val seriesIds = (rs.getArray(14).array as Array<*>).map { UUID.fromString(it.toString()) }
                    val locality = rs.getString(5)
                    val reasons = mutableListOf<String>()
                    reasons += "starts ${startsAt.atZone(london).toLocalDate()}"
                    if (isThisWeekend(startsAt, from)) reasons += "this weekend"
                    if (homeLocality != null && locality != null && locality.equals(homeLocality, ignoreCase = true)) reasons += "in $locality, where your team plays"
                    if (closes != null && !closes.isBefore(from) && closes.isBefore(from.plusSeconds(7 * 86_400))) reasons += "entries close ${closes.atZone(london).toLocalDate()}"
                    if (closes == null) reasons += "closing date not stated by the organiser"
                    reasons += when (kind) { "player" -> "singles"; "pair" -> "pairs"; else -> "team entry" }
                    reasons += when (access) {
                        "open" -> "open entry"
                        "invitational" -> "by invitation"
                        else -> "$access entry — eligibility not yet checkable by THRØ"
                    }
                    if (entered) reasons += "you are entered"
                    seriesIds.filter { it in mySeries }.forEach { reasons += "part of a series you play in" }
                    if (rs.getObject(10) == null) reasons += "capacity not stated by the organiser"
                    cards += Card(
                        rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), rs.getString(4), locality, startsAt, closes,
                        kind, access, rs.getObject(10) as Int?, rs.getInt(11), entered, seriesLabels, reasons,
                    )
                }
            }
        }
        val sections = linkedMapOf<Section, MutableList<Card>>()
        fun put(s: Section, c: Card) { sections.getOrPut(s) { mutableListOf() } += c }
        for (c in cards) {
            put(Section.ALL, c)
            if (c.entered) { put(Section.ALREADY_ENTERED, c); continue }
            if (isThisWeekend(c.startsAt, from)) put(Section.THIS_WEEKEND, c)
            if (homeLocality != null && c.locality.equals(homeLocality, ignoreCase = true)) put(Section.NEAR_YOU, c)
            if (c.entriesCloseAt != null && !c.entriesCloseAt.isBefore(from) && c.entriesCloseAt.isBefore(from.plusSeconds(7 * 86_400))) put(Section.CLOSING_SOON, c)
            // Eligible means THRØ can say so: open entry, singles (a player enters alone), entries not closed,
            // and a place if the organiser stated a capacity. Anything else is not claimed.
            val spots = c.spotsRemaining
            val open = c.access == "open" && c.entrantKind == "player" &&
                (c.entriesCloseAt == null || !c.entriesCloseAt.isBefore(from)) && (spots == null || spots > 0)
            if (open) put(Section.YOU_ARE_ELIGIBLE, c)
            if (c.reasons.any { it == "part of a series you play in" }) put(Section.YOUR_SERIES, c)
        }
        return sections
    }

    private fun isThisWeekend(at: Instant, now: Instant): Boolean {
        val today = now.atZone(london).toLocalDate()
        val saturday = today.with(TemporalAdjusters.nextOrSame(DayOfWeek.SATURDAY))
        val sunday = saturday.plusDays(1)
        val d = at.atZone(london).toLocalDate()
        return d == saturday || d == sunday
    }

    /** Series seasons in which the player has a live entry to any event, from [since] on or earlier. */
    private fun seriesEnteredBy(playerId: UUID, since: Instant): Set<UUID> {
        val out = mutableSetOf<UUID>()
        connection.prepareStatement(
            """
            SELECT DISTINCT se.series_season_id
              FROM competition.entry en JOIN competition.series_event se ON se.event_id = en.event_id
             WHERE en.withdrawn_at IS NULL AND en.player_id = ?
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, playerId); ps.executeQuery().use { rs -> while (rs.next()) out += rs.getObject(1) as UUID } }
        return out
    }
}
