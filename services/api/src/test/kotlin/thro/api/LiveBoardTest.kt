package thro.api

import java.sql.Connection
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * A game on a public screen (PD-088).
 *
 * The founder's decision was *"if it's legal all games should be live shown"*. These are the conditional.
 *
 * The thing being protected is narrow and worth stating: a league result published afterwards says what
 * happened. A live board says **where a named person is, right now**, to whoever is in the room. That
 * difference is the whole reason `player_may_be_shown_live` has no guardian branch when
 * `player_may_be_disclosed` does, and every test below is about the seam between them.
 */
class LiveBoardTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private fun account(c: Connection, name: String, band: String, assurance: String): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) " +
                       "VALUES ('$id', '$name', '$band', '$assurance')")
        }
        return id
    }

    /** A player, claimed by an account — the link `player_may_be_shown_live` walks. */
    private fun player(c: Connection, account: UUID): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO competition.player (player_id, source) VALUES ('$id', 'self')")
            st.execute("INSERT INTO identity.player_claim (claim_id, account_id, player_id, method) " +
                       "VALUES ('${UUID.randomUUID()}', '$account', '$id', 'self_created')")
        }
        return id
    }

    private fun shownLive(c: Connection, player: UUID): Boolean =
        c.createStatement().use { st ->
            st.executeQuery("SELECT identity.player_may_be_shown_live('$player')").use { it.next(); it.getBoolean(1) }
        }

    private fun disclosed(c: Connection, player: UUID): Boolean =
        c.createStatement().use { st ->
            st.executeQuery("SELECT identity.player_may_be_disclosed('$player')").use { it.next(); it.getBoolean(1) }
        }

    /** A guardian consent, which only the secretary may write — inserted directly, as it is here. */
    private fun guardianConsent(c: Connection, account: UUID, scope: String) {
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.consent_record (account_id, basis, scope, given_by, artefact_ref) " +
                       "VALUES ('$account', 'guardian', '$scope', '$account', 'a form somebody signed')")
        }
    }

    @Test
    fun `an adult who has said yes may be named on a screen`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann", "adult", "self_declared")
            val p = player(c, ann)
            assertTrue(!shownLive(c, p), "and not before they say so")

            Consent(c).say(ann, Consent.Scope.LIVE, yes = true)
            assertTrue(shownLive(c, p))
        }
    }

    @Test
    fun `a child may never be shown live, and a guardian cannot agree to it for them`() {
        if (!configured) return
        migrated().use { c ->
            val kid = account(c, "Sam", "minor", "guardian_declared")
            val p = player(c, kid)

            // The guardian consents to both. Listing is a fact about membership and a guardian may agree
            // to it; the live screen is a fact about where the child is standing at 9pm, and they may not.
            guardianConsent(c, kid, "listing")
            guardianConsent(c, kid, "live")

            assertTrue(disclosed(c, p), "a guardian may put a child on a team page — that is the existing rule")
            assertTrue(!shownLive(c, p), "and may not put them on a pub wall while they are playing")
        }
    }

    @Test
    fun `a child cannot agree to it themselves either, and is told why`() {
        if (!configured) return
        migrated().use { c ->
            val kid = account(c, "Sam", "minor", "self_declared")
            val p = player(c, kid)

            val answer = Consent(c).say(kid, Consent.Scope.LIVE, yes = true)
            assertTrue(!answer.given)
            // Refused at the write as well as at the gate. The gate stops a name reaching a screen; this
            // stops a row existing that says a child agreed to something THRØ would never act on.
            assertEquals(Consent.WHY_NOT_LIVE, answer.refusedBecause)
            assertEquals(0, count(c, "SELECT count(*) FROM identity.consent_record " +
                                     "WHERE account_id = '$kid' AND scope = 'live'"))
            // They still have the `holding` record every self-created account gets, and should: THRØ is
            // keeping what they typed on the basis that they typed it. That is the whole point of the
            // three scopes — one of them is true of everybody and lets no name out.
            assertEquals("holding", one(c, "SELECT scope FROM identity.consent_record WHERE account_id = '$kid'"))
            assertTrue(!shownLive(c, p))
        }
    }

    @Test
    fun `an unknown age is not an adult here either`() {
        if (!configured) return
        migrated().use { c ->
            // The rule the whole system turns on, and the reason it is load-bearing: this is what happens
            // when nobody has said, which is the ordinary case rather than the exotic one.
            val nobody = account(c, "Someone", "unknown", "none")
            val p = player(c, nobody)
            assertTrue(!Consent(c).say(nobody, Consent.Scope.LIVE, yes = true).given)
            assertTrue(!shownLive(c, p))
        }
    }

    @Test
    fun `saying yes to one screen is not saying yes to the other`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann", "adult", "self_declared")
            val p = player(c, ann)

            Consent(c).say(ann, Consent.Scope.LISTING, yes = true)
            assertTrue(disclosed(c, p))
            assertTrue(!shownLive(c, p), "a team page is not a live board, and one answer is not both")

            Consent(c).say(ann, Consent.Scope.LIVE, yes = true)
            assertTrue(shownLive(c, p))
            assertEquals(setOf(Consent.Scope.LISTING, Consent.Scope.LIVE), Consent(c).given(ann))
        }
    }

    @Test
    fun `withdrawing takes the name off the screen and keeps the record that it was given`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann", "adult", "self_declared")
            val p = player(c, ann)
            Consent(c).say(ann, Consent.Scope.LIVE, yes = true)
            assertTrue(shownLive(c, p))

            Consent(c).say(ann, Consent.Scope.LIVE, yes = false)
            assertTrue(!shownLive(c, p), "and the screen stops naming them at the next read, not the next season")
            // Revoked, not removed. "They said yes in March and no in June" has to be answerable, or it
            // is a flag rather than a consent record.
            assertEquals(1, count(c, "SELECT count(*) FROM identity.consent_record " +
                                     "WHERE account_id = '$ann' AND scope = 'live' AND revoked_at IS NOT NULL"))
        }
    }

    @Test
    fun `saying yes twice is one record, not a pile`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann", "adult", "self_declared")
            repeat(3) { Consent(c).say(ann, Consent.Scope.LIVE, yes = true) }
            assertEquals(1, count(c, "SELECT count(*) FROM identity.consent_record " +
                                     "WHERE account_id = '$ann' AND scope = 'live' AND revoked_at IS NULL"))
        }
    }

    @Test
    fun `an adult who loses their adult band stops being nameable, without anybody revoking anything`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann", "adult", "self_declared")
            val p = player(c, ann)
            Consent(c).say(ann, Consent.Scope.LIVE, yes = true)
            assertTrue(shownLive(c, p))

            // A correction: the band was wrong. The consent record is untouched and still live — and the
            // gate asks about the band every time rather than trusting the consent to imply it, so the
            // name comes off the screen on the next read.
            c.createStatement().use { st ->
                st.execute("UPDATE identity.account SET age_band = 'minor' WHERE account_id = '$ann'")
            }
            assertTrue(!shownLive(c, p), "the gate reads the band now, not the band at the time consent was given")
        }
    }

    @Test
    fun `the scope column did not quietly widen the older gate`() {
        if (!configured) return
        migrated().use { c ->
            val ann = account(c, "Ann", "adult", "self_declared")
            val p = player(c, ann)
            // Live only. Before V045 there was one kind of consent record and `player_may_be_disclosed`
            // read them all; if it had been left that way, agreeing to a pub screen would have silently
            // put this person on a team page as well.
            Consent(c).say(ann, Consent.Scope.LIVE, yes = true)
            assertTrue(!disclosed(c, p), "agreeing to one exposure must never grant the other")
        }
    }

    private fun one(c: Connection, sql: String): String? =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> if (rs.next()) rs.getString(1) else null } }

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }
}
