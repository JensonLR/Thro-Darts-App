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
 * the organiser declared, and "not stated" is a value. A gated event — `member_only`, `qualified`,
 * `restricted`, `invitational` — is called eligible only when the organiser has stated its
 * requirement in terms THRØ can check (V019) and the store says the player meets every group of
 * it; the card then names the rule that was met, or the one that was not. A gated event with no
 * stated requirement says so, and is never called eligible.
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
        /** Open entry, or a stated requirement the store says this player meets. Never a guess. */
        val qualifies: Boolean,
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
                    var qualifies = access == "open"
                    if (access == "open") {
                        reasons += "open entry"
                    } else {
                        val label = if (access == "invitational") "by invitation" else "$access entry"
                        val stated = requirementsOf(rs.getObject(1) as UUID, playerId, from)
                        when {
                            stated.isEmpty() -> reasons += "$label — requirement not stated in terms THRØ can check"
                            stated.groupBy { it.group }.values.all { g -> g.any { it.holds } } -> {
                                qualifies = true
                                reasons += "$label — you qualify: " + stated.filter { it.holds }.joinToString("; ") { it.met }
                            }
                            else -> reasons += "$label — requires " + stated.groupBy { it.group }.values
                                .first { g -> g.none { it.holds } }.joinToString(" or ") { it.asked }
                        }
                    }
                    if (entered) reasons += "you are entered"
                    seriesIds.filter { it in mySeries }.forEach { reasons += "part of a series you play in" }
                    if (rs.getObject(10) == null) reasons += "capacity not stated by the organiser"
                    cards += Card(
                        rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), rs.getString(4), locality, startsAt, closes,
                        kind, access, rs.getObject(10) as Int?, rs.getInt(11), entered, seriesLabels, reasons, qualifies,
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
            // Eligible means THRØ can say so: open entry or a stated requirement met, singles (a player
            // enters alone), entries not closed, and a place if the organiser stated a capacity.
            // Anything else is not claimed.
            val spots = c.spotsRemaining
            val open = c.qualifies && c.entrantKind == "player" &&
                (c.entriesCloseAt == null || !c.entriesCloseAt.isBefore(from)) && (spots == null || spots > 0)
            if (open) put(Section.YOU_ARE_ELIGIBLE, c)
            if (c.reasons.any { it == "part of a series you play in" }) put(Section.YOUR_SERIES, c)
        }
        return sections
    }

    private data class Row(val group: Int, val holds: Boolean, val met: String, val asked: String)

    /**
     * The event's live requirement rows with, per row, whether the store says it holds for the
     * player and how to say it either way. One query per gated card, deliberately: the number of
     * gated events in a sixty-day window is small and the honesty of the per-row verdict is not
     * worth trading for a join. The verdict comes from the same predicate as
     * `competition.player_satisfies_event`, so the card and the store cannot disagree.
     */
    private fun requirementsOf(eventId: UUID, playerId: UUID, at: Instant): List<Row> {
        val out = mutableListOf<Row>()
        connection.prepareStatement(
            """
            SELECT r.requirement_group, competition.requirement_holds_for(r, ?, ?), r.kind,
                   t.name, ls.label, l.name, q.name, r.age_band
              FROM competition.event_eligibility r
              LEFT JOIN competition.team t ON t.team_id = r.team_id
              LEFT JOIN competition.league_season ls ON ls.league_season_id = r.league_season_id
              LEFT JOIN competition.league l ON l.league_id = ls.league_id
              LEFT JOIN competition.event q ON q.event_id = r.qualifier_event_id
             WHERE r.event_id = ? AND r.withdrawn_at IS NULL
             ORDER BY r.requirement_group, r.stated_at
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, playerId); ps.setObject(2, Timestamp.from(at)); ps.setObject(3, eventId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val (met, asked) = when (rs.getString(3)) {
                        "team_member" -> "member of ${rs.getString(4)}" to "membership of ${rs.getString(4)}"
                        "league_registered" -> "registered in ${rs.getString(6)} ${rs.getString(5)}" to "registration in ${rs.getString(6)} ${rs.getString(5)}"
                        "entered_event" -> "entered ${rs.getString(7)}" to "an entry to ${rs.getString(7)}"
                        "age_band" -> "age band ${rs.getString(8)} on your claimed account" to "a claimed account whose age band is ${rs.getString(8)}"
                        else -> "invited by name" to "an invitation by name"
                    }
                    out += Row(rs.getInt(1), rs.getBoolean(2), met, asked)
                }
            }
        }
        return out
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
