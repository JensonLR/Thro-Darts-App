package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The Team OS slice: start, code, join, and a roster that names only those the rule allows. */
class TeamsTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    /** An account made the way sign-in makes one, with its self-created player. */
    private fun person(c: Connection, name: String, band: String): UUID {
        val account = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) VALUES ('$account', '$name', '$band', ${if (band == "unknown") "'none'" else "'self_declared'"})")
        }
        val org = Organisations(c)
        val player = org.createPlayer(source = "self", by = account)
        org.claim(player, account, "self_created")
        return player
    }

    @Test
    fun `a team is started, filled by code, and names only those who may be named`() {
        if (!configured) return
        migrated().use { c ->
            var now = Instant.parse("2026-09-10T21:00:00Z")
            val teams = Teams(c) { now }
            val jenson = person(c, "Jenson R.", "adult"); val ethan = person(c, "Ethan T.", "unknown"); val kid = person(c, "Young", "minor")
            val team = teams.create(jenson, "  The Sun Inn ", "Stockton-on-Tees")
            assertEquals("The Sun Inn", team.name); assertEquals("admin", team.role); assertEquals(1, team.members)
            assertEquals(listOf("The Sun Inn"), teams.mine(jenson).map { it.name })
            assertTrue(Relations(c).decide(jenson, "team.manage", thro.authz.ObjectRef(thro.authz.ObjectType.TEAM, team.teamId.toString())).allowed)

            assertEquals("Only the team's admin or captain makes its code.", assertFailsWith<Teams.Refused> { teams.invite(ethan, team.teamId) }.why)
            val code = teams.invite(jenson, team.teamId)
            assertEquals(20, code.maxUses)
            assertEquals("player", teams.join(ethan, code.code.lowercase()).role)
            teams.join(kid, code.code)
            assertEquals("You are in this team already.", assertFailsWith<Teams.Refused> { teams.join(ethan, code.code) }.why)
            assertEquals("That is not a THRØ team code: eight letters and numbers.", assertFailsWith<Teams.Refused> { teams.join(ethan, "x") }.why)

            val front = teams.front(team.teamId, viewer = null)!!
            assertEquals(3, front.roster.size, "everyone is counted")
            assertEquals(listOf("Jenson R.", null, null), front.roster.map { it.name }, "only the consenting adult is named; the unknown and the minor are not")
            assertNull(front.yourRole)
            assertEquals("player", teams.front(team.teamId, viewer = ethan)!!.yourRole)

            // A home: a public venue found by name, then moved; the old tenure is closed, not lost.
            Organisations(c).createVenue("The Sun Inn", "Stockton-on-Tees")
            assertEquals(listOf("The Sun Inn"), teams.venues("sun").map { it.name })
            assertEquals("Only the team's admin or captain sets its home.", assertFailsWith<Teams.Refused> { teams.setHome(ethan, team.teamId, teams.venues("sun")[0].venueId, null, null) }.why)
            assertEquals("The Sun Inn", teams.setHome(jenson, team.teamId, teams.venues("sun")[0].venueId, null, null).venue?.name)
            assertEquals("The Dolphin", teams.setHome(jenson, team.teamId, null, "The Dolphin", "Stockton-on-Tees").venue?.name)
            c.createStatement().use { st -> st.executeQuery("SELECT count(*) FROM competition.team_venue_tenure WHERE team_id = '${team.teamId}'").use { rs -> rs.next(); assertEquals(2, rs.getInt(1), "two tenures, one closed") } }
            now = now.plus(Teams.INVITE_TTL).plusSeconds(1)
            assertEquals("That code has expired. Ask for a new one.", assertFailsWith<Teams.Refused> { teams.join(person(c, "Late", "adult"), code.code) }.why)
            assertEquals("A team name is 2 to 60 characters.", assertFailsWith<Teams.Refused> { teams.create(jenson, "X", null) }.why)
            // A private team is nobody's business but its members'.
            c.createStatement().use { st -> st.execute("UPDATE competition.team SET visibility = 'private', row_version = row_version + 1 WHERE team_id = '${team.teamId}'") }
            assertNull(teams.front(team.teamId, viewer = null)); assertEquals("The Sun Inn", teams.front(team.teamId, viewer = kid)!!.name)
        }
    }

    @Test
    fun `the admin names a captain and a vice-captain, one of each, and the side's history is kept`() {
        if (!configured) return
        migrated().use { c ->
            var now = Instant.parse("2026-09-11T20:00:00Z")
            val teams = Teams(c) { now }
            val admin = person(c, "Jenson R.", "adult"); val ethan = person(c, "Ethan T.", "adult"); val sam = person(c, "Sam C.", "adult")
            val team = teams.create(admin, "The Bell", "Stockton-on-Tees")
            val code = teams.invite(admin, team.teamId).code
            now = now.plusSeconds(60); teams.join(ethan, code); teams.join(sam, code)
            fun handle(front: Teams.Front, name: String): UUID = front.roster.first { it.name == name }.memberId!!
            val teamRef = thro.authz.ObjectRef(thro.authz.ObjectType.TEAM, team.teamId.toString())

            val asAdmin = teams.front(team.teamId, admin)!!
            assertTrue(asAdmin.roster.all { it.memberId != null }, "the admin sees each entry's handle, to name a captain with")
            assertTrue(teams.front(team.teamId, null)!!.roster.all { it.memberId == null }, "a public front carries none")
            assertTrue(teams.front(team.teamId, ethan)!!.roster.all { it.memberId == null }, "and nor does a member's")
            assertTrue(!teams.json(teams.front(team.teamId, null)!!).contains("memberId"))

            now = now.plusSeconds(60)
            val named = teams.assign(admin, team.teamId, handle(asAdmin, "Ethan T."), "captain")
            assertEquals("captain", named.roster.first { it.name == "Ethan T." }.role)
            assertTrue(Relations(c).decide(ethan, "team.manage", teamRef).allowed, "a captain runs the team on the command path too")
            assertEquals(20, teams.invite(ethan, team.teamId).maxUses, "and makes its code")

            now = now.plusSeconds(60)
            val replaced = teams.assign(admin, team.teamId, handle(named, "Sam C."), "captain")
            assertEquals(mapOf<String?, String>("Jenson R." to "admin", "Sam C." to "captain", "Ethan T." to "player"),
                         replaced.roster.associate { it.name to it.role }, "one captain at a time")
            assertTrue(!Relations(c).decide(ethan, "team.manage", teamRef).allowed, "the old captain's relation is revoked with the captaincy")
            now = now.plusSeconds(60)
            val vice = teams.assign(admin, team.teamId, handle(replaced, "Ethan T."), "vice_captain")
            assertEquals("vice_captain", vice.roster.first { it.name == "Ethan T." }.role)
            assertTrue(!Relations(c).decide(ethan, "team.manage", teamRef).allowed, "a vice-captain does not run the team")

            assertEquals(403, assertFailsWith<Teams.Refused> { teams.assign(sam, team.teamId, handle(vice, "Ethan T."), "player") }.status,
                "a captain does not name captains")
            assertEquals("The admin stays the admin.", assertFailsWith<Teams.Refused> { teams.assign(admin, team.teamId, handle(vice, "Jenson R."), "player") }.why)
            assertEquals("A role on a team is captain, vice-captain or player.", assertFailsWith<Teams.Refused> { teams.assign(admin, team.teamId, handle(vice, "Ethan T."), "admin") }.why)
            assertEquals("That person is not on the team.", assertFailsWith<Teams.Refused> { teams.assign(admin, team.teamId, UUID.randomUUID(), "captain") }.why)

            // Who held what, and until when, is the side's history: joined, captained, a player, vice-captain.
            c.createStatement().use { st ->
                st.executeQuery("SELECT string_agg(role, ',' ORDER BY valid_from) FROM competition.team_membership WHERE team_id = '${team.teamId}' AND player_id = '$ethan'")
                    .use { rs -> rs.next(); assertEquals("player,captain,player,vice_captain", rs.getString(1)) }
            }

            // A clock that has not moved still records a change after the row it ends began.
            val stuck = teams.assign(admin, team.teamId, handle(vice, "Ethan T."), "player")
            val again = Teams(c) { now }.assign(admin, team.teamId, handle(stuck, "Ethan T."), "captain")
            assertEquals("captain", again.roster.first { it.name == "Ethan T." }.role)
        }
    }
}
