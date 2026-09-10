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

            now = now.plus(Teams.INVITE_TTL).plusSeconds(1)
            assertEquals("That code has expired. Ask for a new one.", assertFailsWith<Teams.Refused> { teams.join(person(c, "Late", "adult"), code.code) }.why)
            assertEquals("A team name is 2 to 60 characters.", assertFailsWith<Teams.Refused> { teams.create(jenson, "X", null) }.why)
            // A private team is nobody's business but its members'.
            c.createStatement().use { st -> st.execute("UPDATE competition.team SET visibility = 'private', row_version = row_version + 1 WHERE team_id = '${team.teamId}'") }
            assertNull(teams.front(team.teamId, viewer = null)); assertEquals("The Sun Inn", teams.front(team.teamId, viewer = kid)!!.name)
        }
    }
}
