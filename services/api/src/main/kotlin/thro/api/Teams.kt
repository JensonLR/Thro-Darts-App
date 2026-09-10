package thro.api

import java.security.SecureRandom
import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.MembershipRole

/**
 * The Team OS slice on the phone (plan §6, first rows): start a team, get people in by code,
 * see the roster. Real rows — `competition.team`, `team_membership`, `authz.relation` — through
 * the same factories the domain tests use, so nothing here is a second way of writing a team.
 *
 * **Names on a roster are disclosed by the rule, not by default.** A member's name appears only
 * when `identity.player_may_be_disclosed` says so — an adult with their own live consent, or a
 * guardian's — and everyone else is counted, never named. A public team front therefore never
 * shows a child.
 */
public class Teams(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public data class Summary(val teamId: UUID, val name: String, val locality: String?, val role: String, val members: Int)
    public data class Member(val name: String?, val role: String)
    public data class SeasonLine(val league: String, val label: String, val division: String?)
    public data class Front(val teamId: UUID, val name: String, val locality: String?, val venue: Leagues.Venue?,
                            val seasons: List<SeasonLine>, val roster: List<Member>, val yourRole: String?)
    public data class Invite(val code: String, val expiresAt: Instant, val maxUses: Int)
    public class Refused(public val why: String) : Exception(why)

    public companion object {
        public val INVITE_TTL: Duration = Duration.ofDays(30)
        private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        private val random = SecureRandom()
        internal fun newCode(): String = (1..8).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")
        internal fun normalise(code: String): String = code.trim().uppercase().replace(" ", "").replace("-", "")
    }

    private val org = Organisations(connection)

    /** Starts a team. The starter is its first member, an admin, and holds `team#admin`. */
    public fun create(player: UUID, name: String, locality: String?): Summary {
        val clean = name.trim()
        if (clean.length !in 2..60) throw Refused("A team name is 2 to 60 characters.")
        val teamId = org.createTeam(clean, locality?.trim()?.takeIf { it.isNotEmpty() })
        org.addMember(teamId, player, MembershipRole.ADMIN, from = now(), by = player)
        Relations(connection).grant(player, "admin", ObjectRef(ObjectType.TEAM, teamId.toString()), by = player)
        return Summary(teamId, clean, locality, "admin", 1)
    }

    /** The teams this player is currently a member of, with their role in each. */
    public fun mine(player: UUID): List<Summary> =
        connection.prepareStatement(
            """
            SELECT t.team_id, t.name, t.locality, m.role,
                   (SELECT count(*) FROM competition.team_membership x WHERE x.team_id = t.team_id AND x.valid_until IS NULL)
              FROM competition.team_membership m JOIN competition.team t ON t.team_id = m.team_id
             WHERE m.player_id = ? AND m.valid_until IS NULL AND t.dissolved_at IS NULL
             ORDER BY m.valid_from DESC
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, player)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) Summary(rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), rs.getString(4), rs.getInt(5)) else null }.toList() }
        }

    private fun roleOf(player: UUID, teamId: UUID): String? =
        connection.prepareStatement("SELECT role FROM competition.team_membership WHERE team_id = ? AND player_id = ? AND valid_until IS NULL")
            .use { ps -> ps.setObject(1, teamId); ps.setObject(2, player); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null } }

    /** The team's front: public rows, names only where disclosure allows, and the viewer's own role. */
    public fun front(teamId: UUID, viewer: UUID?): Front? {
        val head = connection.prepareStatement("SELECT name, locality, visibility FROM competition.team WHERE team_id = ? AND dissolved_at IS NULL")
            .use { ps -> ps.setObject(1, teamId); ps.executeQuery().use { rs -> if (rs.next()) Triple(rs.getString(1), rs.getString(2), rs.getString(3)) else null } } ?: return null
        val yourRole = viewer?.let { roleOf(it, teamId) }
        if (head.third == "private" && yourRole == null) return null
        val venue = connection.prepareStatement(
            """SELECT v.venue_id, v.name, v.locality, v.postcode, v.latitude, v.longitude FROM competition.team_venue_tenure tv
               JOIN competition.venue v ON v.venue_id = tv.venue_id AND v.visibility = 'public'
               WHERE tv.team_id = ? AND tv.kind = 'home' AND tv.valid_until IS NULL""",
        ).use { ps -> ps.setObject(1, teamId); ps.executeQuery().use { rs -> if (rs.next()) Leagues.Venue(rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), rs.getString(4), rs.getBigDecimal(5)?.toDouble(), rs.getBigDecimal(6)?.toDouble(), null) else null } }
        val seasons = connection.prepareStatement(
            """SELECT l.name, ls.label, d.name FROM competition.team_affiliation ta
               JOIN competition.league_season ls ON ls.league_season_id = ta.league_season_id
               JOIN competition.league l ON l.league_id = ls.league_id
               LEFT JOIN competition.division d ON d.division_id = ta.division_id
               WHERE ta.team_id = ? AND ta.valid_until IS NULL ORDER BY ls.starts_on DESC""",
        ).use { ps -> ps.setObject(1, teamId); ps.executeQuery().use { rs -> generateSequence { if (rs.next()) SeasonLine(rs.getString(1), rs.getString(2), rs.getString(3)) else null }.toList() } }
        val roster = connection.prepareStatement(
            """SELECT CASE WHEN identity.player_may_be_disclosed(m.player_id) THEN a.display_name END, m.role
                 FROM competition.team_membership m
                 LEFT JOIN identity.player_claim c ON c.player_id = m.player_id AND c.revoked_at IS NULL
                 LEFT JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                WHERE m.team_id = ? AND m.valid_until IS NULL AND m.status = 'active'
                ORDER BY CASE m.role WHEN 'admin' THEN 0 WHEN 'captain' THEN 1 WHEN 'vice_captain' THEN 2 ELSE 3 END, a.display_name NULLS LAST""",
        ).use { ps -> ps.setObject(1, teamId); ps.executeQuery().use { rs -> generateSequence { if (rs.next()) Member(rs.getString(1), rs.getString(2)) else null }.toList() } }
        return Front(teamId, head.first, head.second, venue, seasons, roster, yourRole)
    }

    /** A code for the side. Made by an admin or a captain; thirty days; up to twenty people. */
    public fun invite(player: UUID, teamId: UUID): Invite {
        val role = roleOf(player, teamId)
        if (role != "admin" && role != "captain") throw Refused("Only the team's admin or captain makes its code.")
        val at = now(); val expires = at.plus(INVITE_TTL)
        repeat(5) {
            val code = newCode()
            val n = connection.prepareStatement("INSERT INTO competition.team_invite (code, team_id, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (code) DO NOTHING")
                .use { ps -> ps.setString(1, code); ps.setObject(2, teamId); ps.setObject(3, player); ps.setTimestamp(4, Timestamp.from(at)); ps.setTimestamp(5, Timestamp.from(expires)); ps.executeUpdate() }
            if (n == 1) return Invite(code, expires, 20)
        }
        error("could not mint a team code")
    }

    /** Enters a team code: the player becomes a member, as a player. */
    public fun join(player: UUID, rawCode: String): Summary {
        val code = normalise(rawCode)
        if (!Regex("^[A-HJ-NP-Z2-9]{8}$").matches(code)) throw Refused("That is not a THRØ team code: eight letters and numbers.")
        val at = now()
        val row = connection.prepareStatement("SELECT team_id, expires_at, uses, max_uses FROM competition.team_invite WHERE code = ? FOR UPDATE")
            .use { ps -> ps.setString(1, code); ps.executeQuery().use { rs -> if (rs.next()) listOf(rs.getObject(1) as UUID, rs.getTimestamp(2).toInstant(), rs.getInt(3), rs.getInt(4)) else null } }
            ?: throw Refused("No team code like that. Check it with whoever gave it to you.")
        val teamId = row[0] as UUID
        if ((row[1] as Instant).isBefore(at)) throw Refused("That code has expired. Ask for a new one.")
        if ((row[2] as Int) >= (row[3] as Int)) throw Refused("That code has admitted everyone it can. Ask for a new one.")
        if (roleOf(player, teamId) != null) throw Refused("You are in this team already.")
        connection.prepareStatement("UPDATE competition.team_invite SET uses = uses + 1 WHERE code = ?").use { ps -> ps.setString(1, code); ps.executeUpdate() }
        connection.prepareStatement("INSERT INTO competition.team_invite_use (code, player_id, used_at) VALUES (?, ?, ?)")
            .use { ps -> ps.setString(1, code); ps.setObject(2, player); ps.setTimestamp(3, Timestamp.from(at)); ps.executeUpdate() }
        org.addMember(teamId, player, MembershipRole.PLAYER, from = at, by = player)
        return mine(player).first { it.teamId == teamId }
    }

    /** Public venues whose name contains [query], for a captain choosing a home. At most twenty. */
    public fun venues(query: String, locality: String? = null): List<Leagues.Venue> =
        connection.prepareStatement(
            """SELECT venue_id, name, locality, postcode, latitude, longitude FROM competition.venue
                WHERE visibility = 'public' AND name ILIKE '%' || ? || '%' AND (? IS NULL OR locality ILIKE '%' || ? || '%')
                ORDER BY name LIMIT 20""",
        ).use { ps ->
            ps.setString(1, query.trim()); ps.setString(2, locality); ps.setString(3, locality)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) Leagues.Venue(rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), rs.getString(4), rs.getBigDecimal(5)?.toDouble(), rs.getBigDecimal(6)?.toDouble(), null) else null }.toList() }
        }

    /**
     * Sets the team's home: an existing public venue by id, or a new one by name. The admin or
     * captain only. A first home opens a tenure; a change closes the old one and opens the new,
     * so "played at X until today, at Y since" is what the history reads.
     */
    public fun setHome(player: UUID, teamId: UUID, venueId: UUID?, name: String?, locality: String?): Front {
        val role = roleOf(player, teamId)
        if (role != "admin" && role != "captain") throw Refused("Only the team's admin or captain sets its home.")
        val venue = venueId ?: run {
            val clean = name?.trim().orEmpty()
            if (clean.length !in 2..80) throw Refused("Name the venue: 2 to 80 characters.")
            org.createVenue(clean, locality?.trim()?.takeIf { it.isNotEmpty() }, by = player)
        }
        val exists = connection.prepareStatement("SELECT 1 FROM competition.venue WHERE venue_id = ? AND visibility = 'public'")
            .use { ps -> ps.setObject(1, venue); ps.executeQuery().use { it.next() } }
        if (!exists) throw Refused("No venue like that.")
        val at = now()
        val current = org.homeVenueAt(teamId, at)
        when {
            current == null -> org.openTenure(teamId, venue, from = at, by = player)
            current == venue -> Unit
            else -> {
                // A move closes the old tenure at `at` and opens the new one there; a tenure must
                // last longer than nothing, so a change in the same second as the last one is
                // recorded one second on rather than refused.
                val openedAt = org.tenuresOf(teamId).filter { it.until == null }.maxOfOrNull { it.from } ?: at
                org.moveHome(teamId, venue, at = maxOf(at, openedAt.plusSeconds(1)), by = player)
            }
        }
        return front(teamId, player)!!
    }

    public fun venuesJson(venues: List<Leagues.Venue>): String =
        "{\"venues\":[" + venues.joinToString(",") { v -> """{"venueId":"${v.venueId}","name":${q(v.name)},"locality":${q(v.locality)},"postcode":${q(v.postcode)},"latitude":${v.latitude ?: "null"},"longitude":${v.longitude ?: "null"}}""" } + "]}"

    private fun q(s: String?): String = s?.let { "\"" + it.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"" } ?: "null"

    public fun json(s: Summary): String = """{"teamId":"${s.teamId}","name":${q(s.name)},"locality":${q(s.locality)},"role":${q(s.role)},"members":${s.members}}"""
    public fun json(list: List<Summary>): String = "{\"teams\":[" + list.joinToString(",") { json(it) } + "]}"
    public fun json(f: Front): String =
        """{"teamId":"${f.teamId}","name":${q(f.name)},"locality":${q(f.locality)},"venue":""" + (f.venue?.let { v ->
            """{"venueId":"${v.venueId}","name":${q(v.name)},"locality":${q(v.locality)},"postcode":${q(v.postcode)},"latitude":${v.latitude ?: "null"},"longitude":${v.longitude ?: "null"}}"""
        } ?: "null") + ""","seasons":[${f.seasons.joinToString(",") { """{"league":${q(it.league)},"label":${q(it.label)},"division":${q(it.division)}}""" }}],""" +
            """"roster":[${f.roster.joinToString(",") { """{"name":${q(it.name)},"role":${q(it.role)}}""" }}],"yourRole":${q(f.yourRole)}}"""
    public fun json(i: Invite): String = """{"code":"${i.code}","expiresAt":"${i.expiresAt}","maxUses":${i.maxUses}}"""
}
