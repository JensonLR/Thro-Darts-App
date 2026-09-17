package thro.api

import java.sql.Connection
import java.sql.ResultSet
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import thro.api.http.Contract

/**
 * Who changed what in a season (PD-120), for the people who run it.
 *
 * Nothing here is new information. A result, a correction, an award, an annulment, a moved fixture, a set of rules,
 * a registration — each is already a row with an actor and a time, because a season's records are appended and never
 * edited. This reads them back as sentences, newest first. An official is named only where THRØ may name them (an
 * adult who has said their name may be listed); otherwise the sentence stands and the person is "An official".
 */
public class SeasonHistory(private val connection: Connection) {

    public data class Entry(val at: Instant, val who: String?, val kind: String, val what: String)

    private companion object {
        val ZONE: ZoneId = ZoneId.of("Europe/London")
        val DOW = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        val MON = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
        val CLOCK: DateTimeFormatter = DateTimeFormatter.ofPattern("h:mm a", Locale.UK)
        fun moment(at: Instant): String {
            val z = at.atZone(ZONE)
            return "${DOW[z.dayOfWeek.value - 1]} ${z.dayOfMonth} ${MON[z.monthValue - 1]}, ${CLOCK.format(z).lowercase()}"
        }
        /** The name THRØ may show for a player id, or null. `%s` is the column holding the id. */
        fun nameOf(column: String): String =
            """(SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> '${Accounts.PLACEHOLDER_NAME.replace("'", "''")}' THEN a.display_name END
                  FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                 WHERE c.player_id = $column AND c.revoked_at IS NULL)"""
    }

    public fun of(season: UUID, limit: Int = 200): List<Entry> =
        (outcomes(season) + moves(season) + rules(season) + registrations(season)).sortedByDescending { it.at }.take(limit)

    private fun <T> rows(sql: String, season: UUID, read: (ResultSet) -> T): List<T> =
        connection.prepareStatement(sql).use { ps ->
            ps.setObject(1, season)
            ps.executeQuery().use { rs -> val out = mutableListOf<T>(); while (rs.next()) out += read(rs); out }
        }

    private fun outcomes(season: UUID): List<Entry> = rows(
        """SELECT o.decided_at, ${nameOf("o.decided_by")}, o.kind, o.legs_home, o.legs_away, coalesce(h.name, 'A team'), coalesce(a.name, 'A team'),
                  tt.name, o.reason, prev.kind, prev.legs_home, prev.legs_away
             FROM competition.league_fixture_outcome o
             JOIN competition.league_fixture f ON f.fixture_id = o.fixture_id
             LEFT JOIN competition.team h ON h.team_id = f.home_team_id
             LEFT JOIN competition.team a ON a.team_id = f.away_team_id
             LEFT JOIN competition.team tt ON tt.team_id = o.to_team_id
             LEFT JOIN competition.league_fixture_outcome prev ON prev.outcome_id = o.supersedes_outcome_id
            WHERE f.league_season_id = ?""", season,
    ) { rs ->
        val kind = rs.getString(3); val home = rs.getString(6); val away = rs.getString(7)
        val reason = rs.getString(9)?.takeIf { it.isNotBlank() }
        val legsHome = rs.getObject(4) as Int?; val legsAway = rs.getObject(5) as Int?
        val wasHome = rs.getObject(11) as Int?; val wasAway = rs.getObject(12) as Int?
        val (what, sort) = when {
            kind == "void" -> "Annulled the result of $home v $away" + (reason?.let { " — $it" } ?: "") to "void"
            legsHome != null && legsAway != null && wasHome != null && wasAway != null ->
                "Corrected $home v $away to $legsHome–$legsAway (it was $wasHome–$wasAway)" to "correction"
            legsHome != null && legsAway != null -> "Recorded $home $legsHome–$legsAway $away" to "result"
            else -> "Awarded $home v $away to ${rs.getString(8) ?: "a side"}" + (reason?.let { " — $it" } ?: "") to "award"
        }
        Entry(rs.getTimestamp(1).toInstant(), rs.getString(2), sort, what)
    }

    private fun moves(season: UUID): List<Entry> = rows(
        """SELECT ch.changed_at, ${nameOf("ch.changed_by")}, coalesce(h.name, 'A team'), coalesce(a.name, 'A team'),
                  ch.from_scheduled_at, ch.to_scheduled_at, ch.reason, ch.proposal_id
             FROM competition.league_fixture_change ch
             JOIN competition.league_fixture f ON f.fixture_id = ch.fixture_id
             LEFT JOIN competition.team h ON h.team_id = f.home_team_id
             LEFT JOIN competition.team a ON a.team_id = f.away_team_id
            WHERE f.league_season_id = ? AND ch.from_scheduled_at IS DISTINCT FROM ch.to_scheduled_at""", season,
    ) { rs ->
        val what = "Moved ${rs.getString(3)} v ${rs.getString(4)} from ${moment(rs.getTimestamp(5).toInstant())} to ${moment(rs.getTimestamp(6).toInstant())}" +
            (if (rs.getObject(8) != null) " — agreed by both teams" else "") + (rs.getString(7)?.takeIf { it.isNotBlank() }?.let { " — $it" } ?: "")
        Entry(rs.getTimestamp(1).toInstant(), rs.getString(2), "move", what)
    }

    private fun rules(season: UUID): List<Entry> = rows(
        """SELECT coalesce(p.approved_at, p.created_at), ${nameOf("coalesce(p.approved_by, p.created_by)")}, p.kind, p.version
             FROM competition.policy p
            WHERE p.league_season_id = ? AND p.approval_state IN ('approved', 'superseded')""", season,
    ) { rs ->
        val kind = rs.getString(3); val version = rs.getInt(4)
        val what = if (kind == "points") "Set the points rules (version $version)" else "Approved the ${kind.replace('_', ' ')} rules (version $version)"
        Entry(rs.getTimestamp(1).toInstant(), rs.getString(2), "rules", what)
    }

    private fun registrations(season: UUID): List<Entry> = rows(
        """SELECT r.valid_from, ${nameOf("r.recorded_by")}, ${nameOf("r.player_id")}, t.name
             FROM competition.player_registration r LEFT JOIN competition.team t ON t.team_id = r.team_id
            WHERE r.league_season_id = ? AND r.status = 'registered'""", season,
    ) { rs ->
        Entry(rs.getTimestamp(1).toInstant(), rs.getString(2), "registration", "Registered ${rs.getString(3) ?: "a player"}" + (rs.getString(4)?.let { " with $it" } ?: ""))
    }

    public fun json(entries: List<Entry>): String =
        "{\"entries\":[" + entries.joinToString(",") { e ->
            """{"at":"${e.at}","who":${e.who?.let { Contract.q(it) } ?: "null"},"kind":${Contract.q(e.kind)},"what":${Contract.q(e.what)}}"""
        } + "]}"
}
