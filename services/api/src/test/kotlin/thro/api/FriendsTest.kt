package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** Friends (V028): by code, in person, adults only, ended but never deleted. */
class FriendsTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private fun account(c: Connection, name: String, band: String = "adult"): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) VALUES ('$id', '$name', '$band', ${if (band == "unknown") "'none'" else "'self_declared'"})")
        }
        return id
    }

    @Test
    fun `a code makes two adults friends once, and the code is spent`() {
        if (!configured) return
        migrated().use { c ->
            var now = Instant.parse("2026-09-10T20:00:00Z")
            val friends = Friends(c) { now }
            val jenson = account(c, "Jenson R."); val ethan = account(c, "Ethan T.")
            val invite = friends.invite(jenson)
            assertEquals(8, invite.code.length); assertEquals(now.plus(Friends.INVITE_TTL), invite.expiresAt)
            assertTrue(invite.code.none { it in "0O1I" }, "a code is said across a table")

            val made = friends.accept(ethan, invite.code.lowercase().chunked(4).joinToString(" "))
            assertEquals(jenson, made.accountId); assertEquals("Jenson R.", made.displayName)
            assertEquals(listOf("Ethan T."), friends.friends(jenson).map { it.displayName })
            assertEquals(listOf("Jenson R."), friends.friends(ethan).map { it.displayName })

            assertEquals("That code has been used already. Ask for a new one.", assertFailsWith<Friends.Refused> { friends.accept(account(c, "Third"), invite.code) }.why)
            assertEquals("You are friends already.", assertFailsWith<Friends.Refused> { friends.accept(ethan, friends.invite(jenson).code) }.why)
            assertEquals("That is your own code. Give it to a friend.", assertFailsWith<Friends.Refused> { friends.accept(jenson, friends.invite(jenson).code) }.why)
            assertEquals("That is not a THRØ friend code: eight letters and numbers.", assertFailsWith<Friends.Refused> { friends.accept(ethan, "hello") }.why)

            val late = friends.invite(jenson)
            now = now.plus(Friends.INVITE_TTL).plusSeconds(1)
            assertEquals("That code has expired. Ask for a new one.", assertFailsWith<Friends.Refused> { friends.accept(account(c, "Late"), late.code) }.why)

            assertTrue(friends.remove(ethan, jenson)); assertTrue(!friends.remove(ethan, jenson), "ended once")
            assertEquals(emptyList(), friends.friends(jenson))
            // Ended, not deleted: the row is still there with who ended it.
            c.createStatement().use { st -> st.executeQuery("SELECT count(*) FROM identity.friendship WHERE ended_by = '$ethan'").use { rs -> rs.next(); assertEquals(1, rs.getInt(1)) } }
            // And they may be friends again.
            friends.accept(ethan, friends.invite(jenson).code)
            assertEquals(1, friends.friends(jenson).size)
        }
    }

    @Test
    fun `an unknown age is refused, not guessed, and a minor is refused for now`() {
        if (!configured) return
        migrated().use { c ->
            val friends = Friends(c) { Instant.parse("2026-09-10T20:00:00Z") }
            val unknown = account(c, "New", band = "unknown"); val minor = account(c, "Young", band = "minor"); val adult = account(c, "Grown")
            assertTrue(assertFailsWith<Friends.Refused> { friends.invite(unknown) }.why.startsWith("Say you are 18 or over"))
            assertTrue(assertFailsWith<Friends.Refused> { friends.invite(minor) }.why.startsWith("Friends on THRØ are for adults"))
            val code = friends.invite(adult).code
            assertTrue(assertFailsWith<Friends.Refused> { friends.accept(unknown, code) }.why.startsWith("Say you are 18"))
            // The database holds the same line even if a route forgot: an invite row for a minor is refused by trigger.
            val refused = runCatching {
                c.createStatement().use { st -> st.execute("INSERT INTO identity.friend_invite (code, account_id, expires_at) VALUES ('ABCDEFGH', '$minor', clock_timestamp() + interval '1 day')") }
            }.exceptionOrNull()
            assertTrue(refused?.message?.contains("said it is an adult") == true, "$refused")
            // Declaring adult unlocks it; declaring back to unknown is not a thing.
            friends.declareAge(unknown, "adult")
            friends.accept(unknown, code)
            assertFailsWith<IllegalArgumentException> { friends.declareAge(unknown, "unknown") }
        }
    }
}
