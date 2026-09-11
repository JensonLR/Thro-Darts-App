package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Erasure (V031): a person can take themselves out of THRØ, and what is left names nobody.
 *
 * The assertion that matters is the last one — **their name appears in no text column anywhere in
 * the identity schema afterwards** — because it is the one that keeps holding when somebody adds a
 * column next month and forgets this file exists.
 */
class ErasureTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private val now = Instant.parse("2026-09-11T11:00:00Z")

    /** Every text value stored anywhere in the identity schema, for the sweep. */
    private fun everyTextInIdentity(c: Connection): List<String> {
        val columns = c.prepareStatement(
            """SELECT table_name, column_name FROM information_schema.columns
                WHERE table_schema = 'identity' AND data_type IN ('text','character varying')""",
        ).use { ps ->
            ps.executeQuery().use { rs ->
                generateSequence { if (rs.next()) rs.getString(1) to rs.getString(2) else null }.toList()
            }
        }
        return columns.flatMap { (table, column) ->
            c.createStatement().use { st ->
                st.executeQuery("""SELECT "$column" FROM identity."$table" WHERE "$column" IS NOT NULL""").use { rs ->
                    generateSequence { if (rs.next()) rs.getString(1) else null }.toList()
                }
            }
        }
    }

    private fun one(c: Connection, sql: String): String? =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> if (rs.next()) rs.getString(1) else null } }

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }

    @Test
    fun `erasing an account destroys everything that identifies the person and keeps what is somebody else's`() {
        if (!configured) return
        migrated().use { c ->
            val accounts = Accounts(c, { now })
            val friends = Friends(c) { now }
            val device = UUID.randomUUID()

            // Jenson signs in with Apple, names himself, says he is an adult, and makes a friend.
            val jenson = accounts.signIn("apple", "apple-subject-jenson-0001", device).accountId
            accounts.setDisplayName(jenson, "Jenson R.")
            c.createStatement().use { st ->
                st.execute("UPDATE identity.account SET age_band = 'adult', age_assurance = 'self_declared' WHERE account_id = '$jenson'")
                st.execute("INSERT INTO identity.device (device_id, account_id, label) VALUES ('$device', '$jenson', 'Jenson''s iPhone')")
                st.execute("INSERT INTO identity.consent_record (consent_id, account_id, basis, given_by, artefact_ref) VALUES ('${UUID.randomUUID()}', '$jenson', 'self', '$jenson', 'roster')")
            }
            val ethan = accounts.signIn("apple", "apple-subject-ethan-0002", UUID.randomUUID()).accountId
            accounts.setDisplayName(ethan, "Ethan T.")
            c.createStatement().use { st ->
                st.execute("UPDATE identity.account SET age_band = 'adult', age_assurance = 'self_declared' WHERE account_id = '$ethan'")
            }
            friends.accept(ethan, friends.invite(jenson).code)
            assertEquals(1, friends.friends(ethan).size)
            val jensonPlayer = accounts.profile(jenson)!!.playerId
            assertTrue(jensonPlayer != null, "signing in gave him a competitor row")
            val session = accounts.signIn("apple", "apple-subject-jenson-0001", device)
            assertTrue(accounts.resolve(session.accessToken) != null, "his session works before")

            // He asks to be taken out.
            val gone = accounts.erase(jenson)
            assertEquals(1, gone.credentials); assertEquals(1, gone.devices)
            assertEquals(1, gone.friendships); assertEquals(1, gone.claims)
            // Signing in records one consent of its own, and the test added a second.
            assertEquals(2, gone.consents)
            assertTrue(gone.sessions >= 1)

            // The name is gone, the band is back to unknown, the account is marked.
            assertEquals("", one(c, "SELECT display_name FROM identity.account WHERE account_id = '$jenson'"))
            assertEquals("unknown", one(c, "SELECT age_band FROM identity.account WHERE account_id = '$jenson'"))
            assertEquals("none", one(c, "SELECT age_assurance FROM identity.account WHERE account_id = '$jenson'"))
            assertTrue(one(c, "SELECT deleted_at FROM identity.account WHERE account_id = '$jenson'") != null)

            // The way in is destroyed rather than only revoked: the Apple subject is not there.
            assertEquals(0, count(c, "SELECT count(*) FROM identity.credential WHERE subject = 'apple-subject-jenson-0001'"))
            assertEquals(0, count(c, "SELECT count(*) FROM identity.credential WHERE account_id = '$jenson' AND revoked_at IS NULL"))
            // Every session is dead the moment it returns, not when the token expires.
            assertNull(accounts.resolve(session.accessToken), "his session is dead")
            assertEquals(0, count(c, "SELECT count(*) FROM identity.session_family WHERE account_id = '$jenson' AND revoked_at IS NULL"))
            // The device label was his own words.
            assertNull(one(c, "SELECT label FROM identity.device WHERE account_id = '$jenson'"))
            // Nothing about him can leave THRØ again.
            assertEquals("false", one(c, "SELECT identity.player_may_be_disclosed('$jensonPlayer')::text"))
            assertEquals(0, count(c, "SELECT count(*) FROM identity.player_claim WHERE account_id = '$jenson' AND revoked_at IS NULL"))
            assertEquals(0, count(c, "SELECT count(*) FROM identity.consent_record WHERE account_id = '$jenson' AND revoked_at IS NULL"))

            // Ethan's side: the friendship ended, and he is not told a name that no longer exists.
            assertEquals(0, friends.friends(ethan).size)
            assertEquals("Ethan T.", one(c, "SELECT display_name FROM identity.account WHERE account_id = '$ethan'"))

            // What belongs to other people stays: the competitor row is still there, and it never
            // held a name to begin with (V018) — which is why keeping it costs nobody anything.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.player WHERE player_id = '$jensonPlayer'"))

            // THE SWEEP. His name is in no text column anywhere in identity, and neither is his
            // Apple subject. This is the assertion that survives somebody adding a column.
            val text = everyTextInIdentity(c)
            assertFalse(text.any { it.contains("Jenson") }, "his name survived somewhere: ${text.filter { it.contains("Jenson") }}")
            assertFalse(text.any { it.contains("apple-subject-jenson") }, "his Apple subject survived somewhere")
            assertTrue(text.any { it.contains("Ethan T.") }, "and the sweep can actually find a name that should be there")
        }
    }

    @Test
    fun `somebody holding a friend code they never gave out can still be erased`() {
        if (!configured) return
        migrated().use { c ->
            val accounts = Accounts(c, { now })
            val friends = Friends(c) { now }
            // The founder's own account on staging, exactly as it stood when Delete did nothing: Apple
            // and Google, signed in more than once, an adult, and one friend code made and never
            // handed over. The first test above only ever made a code somebody then used.
            val me = accounts.signIn("apple", "apple-subject-holder-0001", UUID.randomUUID()).accountId
            accounts.signIn("google", "google-subject-holder-0001", UUID.randomUUID(), linkTo = me)
            accounts.signIn("apple", "apple-subject-holder-0001", UUID.randomUUID())
            accounts.setDisplayName(me, "Jenson R.")
            c.createStatement().use { st ->
                st.execute("UPDATE identity.account SET age_band = 'adult', age_assurance = 'self_declared' WHERE account_id = '$me'")
            }
            val code = friends.invite(me).code

            // V031 raised here — "a code is for somebody else" — and the whole erasure rolled back.
            val gone = accounts.erase(me)
            assertEquals(2, gone.credentials, "both ways in")
            assertTrue(gone.sessions >= 3, "every sign-in's session")
            assertEquals("", one(c, "SELECT display_name FROM identity.account WHERE account_id = '$me'"))

            // Nobody typed the code, so the record does not say anybody did.
            assertEquals(1, count(c, "SELECT count(*) FROM identity.friend_invite WHERE code = '$code'"))
            assertNull(one(c, "SELECT used_at::text FROM identity.friend_invite WHERE code = '$code'"))

            // And it admits nobody. The person it was meant for is told so in words, and not why.
            val stranger = accounts.signIn("apple", "apple-subject-stranger-0002", UUID.randomUUID()).accountId
            c.createStatement().use { st ->
                st.execute("UPDATE identity.account SET age_band = 'adult', age_assurance = 'self_declared' WHERE account_id = '$stranger'")
            }
            val refused = assertFailsWith<Friends.Refused> { friends.accept(stranger, code) }
            assertEquals("That code no longer works. Ask for a new one.", refused.why)
            assertEquals(0, count(c, "SELECT count(*) FROM identity.friendship WHERE account_a = '$stranger' OR account_b = '$stranger'"))
        }
    }

    @Test
    fun `signing in again after an erasure is a new person, not the old one coming back`() {
        if (!configured) return
        migrated().use { c ->
            val accounts = Accounts(c, { now })
            val device = UUID.randomUUID()
            val first = accounts.signIn("apple", "apple-subject-returning", device).accountId
            accounts.setDisplayName(first, "Jenson R.")
            val firstPlayer = accounts.profile(first)!!.playerId
            accounts.erase(first)

            // The same Apple ID, because it is the same phone and the same person — and THRØ has
            // destroyed everything that could tie the two together, so it must not pretend otherwise.
            val second = accounts.signIn("apple", "apple-subject-returning", device).accountId
            assertNotEquals(first, second, "the erased account did not come back")
            val profile = accounts.profile(second)!!
            assertFalse(profile.named, "and it is not carrying the name he asked to be rid of")
            assertNotEquals(firstPlayer, profile.playerId, "a new competitor: the old one's matches are not his again")
            assertNull(accounts.profile(first), "the erased account reads as gone")
        }
    }

    @Test
    fun `an account can only be erased once`() {
        if (!configured) return
        migrated().use { c ->
            val accounts = Accounts(c, { now })
            val id = accounts.signIn("google", "google-subject-once", UUID.randomUUID()).accountId
            accounts.erase(id)
            // A second tap must not overwrite the first erasure's record of what it destroyed.
            val again = assertFailsWith<Exception> { accounts.erase(id) }
            assertTrue(again.message!!.contains("already erased"), again.message!!)
            assertEquals(1, count(c, "SELECT count(*) FROM identity.erasure WHERE account_id = '$id'"))
        }
    }

    @Test
    fun `the service cannot reach those columns any other way`() {
        if (!configured) return
        migrated().use { c ->
            // The erasure exists as one narrow function precisely so the running service does NOT
            // hold the standing power to rewrite anybody's sign-in. If that stops being true, the
            // argument in V031's header stops being true with it.
            c.createStatement().use { st -> st.execute("SET ROLE app_competition") }
            val id = UUID.randomUUID()
            c.createStatement().use { st ->
                st.execute("SET ROLE thro_owner")
                st.execute("INSERT INTO identity.account (account_id, display_name) VALUES ('$id', 'Someone')")
                st.execute("INSERT INTO identity.credential (credential_id, account_id, kind, subject) VALUES ('${UUID.randomUUID()}', '$id', 'apple', 'subject-to-protect')")
                st.execute("SET ROLE app_competition")
            }
            assertFailsWith<Exception> {
                c.createStatement().use { st -> st.execute("UPDATE identity.credential SET subject = 'rewritten' WHERE account_id = '$id'") }
            }
            c.createStatement().use { st -> st.execute("RESET ROLE") }
            assertEquals("subject-to-protect", one(c, "SELECT subject FROM identity.credential WHERE account_id = '$id'"))
        }
    }
}
