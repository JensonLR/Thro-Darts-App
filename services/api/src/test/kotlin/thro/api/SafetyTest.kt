package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Reporting, blocking and the terms (PD-050): what the stores require of an app that carries what people
 * write, held against a real database.
 */
class SafetyTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private fun account(c: Connection, name: String): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) " +
                       "VALUES ('$id', '$name', 'adult', 'self_declared')")
        }
        return id
    }

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }

    @Test
    fun `a report is raised, answered within a day, and kept whatever is decided`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-11T21:00:00Z")
            val safety = Safety(c) { at }
            val ann = account(c, "Ann")
            val moderator = account(c, "Moderator")
            val team = Organisations(c).createTeam("A Rude Name", "Stockton-on-Tees")

            assertEquals("THRØ does not know how to report that.",
                         assertFailsWith<Safety.Refused> { safety.report(ann, "weather", team, "it is raining") }.why)
            assertEquals("Say what is wrong with it, in a sentence.",
                         assertFailsWith<Safety.Refused> { safety.report(ann, "team", team, " ") }.why)

            val report = safety.report(ann, "team", team, "  The name is a slur.  ")
            assertEquals("The name is a slur.", report.reason, "trimmed, and kept as they wrote it")
            assertEquals(at.plus(Safety.ANSWER_WITHIN), report.answerDueAt, "answered within a day, as the stores require")
            assertFalse(report.urgent)

            assertEquals(listOf(report.reportId), safety.queue().map { it.report.reportId })
            assertEquals(0, safety.queue().first().decisions, "nobody has answered it yet")

            assertEquals("That is not one of the answers a report can have.",
                         assertFailsWith<Safety.Refused> { safety.decide(report.reportId, "ignored", "no", moderator) }.why)
            safety.decide(report.reportId, "hidden", "The name is hidden until the team renames it.", moderator)
            assertEquals(1, safety.queue().first().decisions)
            assertEquals(1, count(c, "SELECT count(*) FROM safety.report"), "a report is kept, whatever was decided")

            // A second look is a second decision, never an edit of the first.
            safety.decide(report.reportId, "corrected", "The team renamed itself.", moderator)
            assertEquals(2, count(c, "SELECT count(*) FROM safety.decision WHERE report_id = '${report.reportId}'"))
        }
    }

    /**
     * A moderator cannot answer a report about an id (PD-101). The queue says what was reported, by the name another
     * person would have read — and it is read as the role the server narrows to, not as the test's owner, because a
     * grant the owner has and the server lacks is exactly how a queue works here and 500s in production.
     */
    @Test
    fun `the queue says what was reported, by the name somebody read`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-14T15:00:00Z")
            val orgs = Organisations(c)
            val ann = account(c, "Ann")
            val rude = account(c, "Rude Name 1")
            val team = orgs.createTeam("A Rude Name", "Stockton-on-Tees")
            val venue = orgs.createVenue("The Rude Arms")
            val league = orgs.createLeague("The Rude League")
            val gone = UUID.randomUUID()
            val safety = Safety(c) { at }
            val reports = mapOf(
                "account" to safety.report(ann, "account", rude, "Their name is a slur."),
                "team" to safety.report(ann, "team", team, "The team name is a slur."),
                "venue" to safety.report(ann, "venue", venue, "The venue name is a slur."),
                "league" to safety.report(ann, "league", league, "The league name is a slur."),
                "match" to safety.report(ann, "match", UUID.randomUUID(), "They threatened me after the match."),
                "gone" to safety.report(ann, "team", gone, "A team that is no longer there."),
            )
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            val labels = safety.queue().associate { it.report.reportId to it.subject }
            assertEquals("Rude Name 1", labels[reports.getValue("account").reportId], "an account by its display name")
            assertEquals("A Rude Name", labels[reports.getValue("team").reportId], "a team by its name")
            assertEquals("The Rude Arms", labels[reports.getValue("venue").reportId], "a venue by its name")
            assertEquals("The Rude League", labels[reports.getValue("league").reportId], "a league by its name")
            assertEquals("A match", labels[reports.getValue("match").reportId], "a match names nobody in it")
            assertEquals("Not on THRØ any more", labels[reports.getValue("gone").reportId], "something no longer there says so")
        }
    }

    /**
     * A decision does what it says (PD-103). Until this, *hidden* and *account_suspended* were words on a record and the
     * moderator did the thing by hand — or did not, and the record said it had been done. Run as `app_competition`,
     * because that is the role the server holds, and a grant the owner has and the server lacks is a 500 in production.
     */
    @Test
    fun `a decision does what it says - hides, suspends, reinstates - and refuses what it cannot do`() {
        if (!configured) return
        migrated().use { c ->
            var at = Instant.parse("2026-09-16T10:00:00Z")
            val orgs = Organisations(c)
            val ann = account(c, "Ann")
            val device = UUID.randomUUID()
            val accounts = Accounts(c, now = { at })
            // The rude account is made the way a person's is — by signing in — so it holds a player and a live session,
            // as a person being suspended would.
            val session = accounts.signIn("apple", "sub-rude", device)
            val rude = session.accountId
            accounts.setDisplayName(rude, "Rude Name")
            assertEquals(rude, accounts.resolve(session.accessToken)?.first, "the session works before any decision")
            val team = orgs.createTeam("A Rude Team", "Stockton-on-Tees")
            val venue = orgs.createVenue("The Rude Arms")
            val league = orgs.createLeague("The Rude League")
            fun visibility(table: String, key: String, id: UUID) = count(c, "SELECT count(*) FROM competition.$table WHERE $key = '$id' AND visibility = 'private'")
            fun suspended(id: UUID) = count(c, "SELECT count(*) FROM identity.account WHERE account_id = '$id' AND suspended_at IS NOT NULL")
            fun name(id: UUID) = c.createStatement().use { st -> st.executeQuery("SELECT display_name FROM identity.account WHERE account_id = '$id'").use { rs -> rs.next(); rs.getString(1) } }

            c.createStatement().use { it.execute("SET ROLE app_competition") }
            val safety = Safety(c) { at }
            val onTeam = safety.report(ann, "team", team, "The team name is a slur.")
            val onVenue = safety.report(ann, "venue", venue, "The venue name is a slur.")
            val onLeague = safety.report(ann, "league", league, "The league name is a slur.")
            val onAccount = safety.report(ann, "account", rude, "Their name is a slur.")
            val onMatch = safety.report(ann, "match", UUID.randomUUID(), "They threatened me after the match.")
            val moderator = ann

            // --- hidden ---------------------------------------------------------------------------------------
            safety.decide(onTeam.reportId, "hidden", "The name is hidden until the team renames it.", moderator)
            assertEquals(1, visibility("team", "team_id", team), "a hidden team is private: unnamed on every public surface")
            safety.decide(onVenue.reportId, "hidden", "Hidden.", moderator)
            assertEquals(1, visibility("venue", "venue_id", venue), "a hidden venue is private")
            safety.decide(onLeague.reportId, "hidden", "Hidden.", moderator)
            assertEquals(1, visibility("league", "league_id", league), "a hidden league is private: off the public list")
            safety.decide(onAccount.reportId, "hidden", "The name is replaced.", moderator)
            assertEquals(Accounts.PLACEHOLDER_NAME, name(rude), "a hidden account name is the placeholder, for the person to change")
            assertEquals("A match names nobody, so there is nothing to hide. Report the account instead.",
                         assertFailsWith<Safety.Refused> { safety.decide(onMatch.reportId, "hidden", "Hide it.", moderator) }.why)

            // --- suspended ------------------------------------------------------------------------------------
            assertEquals("Suspending is of an account. Report the account, and suspend that.",
                         assertFailsWith<Safety.Refused> { safety.decide(onTeam.reportId, "account_suspended", "Out.", moderator) }.why)
            safety.decide(onAccount.reportId, "account_suspended", "Threats, after a warning.", moderator)
            assertEquals(1, suspended(rude))
            at = at.plusSeconds(1)
            assertEquals(null, accounts.resolve(session.accessToken), "every session of a suspended account is dead on the next request")
            assertEquals("this account is suspended", assertFailsWith<Accounts.AccountSuspended> { accounts.signIn("apple", "sub-rude", device) }.message,
                         "and a suspended account cannot sign in again")
            assertEquals("You cannot suspend yourself.",
                         assertFailsWith<Safety.Refused> { safety.decide(safety.report(rude, "account", ann, "x y z").reportId, "account_suspended", "Self.", ann) }.why)

            // --- reinstated -----------------------------------------------------------------------------------
            safety.decide(onAccount.reportId, "reinstated", "Apologised; a month served.", moderator)
            assertEquals(0, suspended(rude), "reinstating lifts the suspension")
            val again = accounts.signIn("apple", "sub-rude", device)
            assertEquals(rude, accounts.resolve(again.accessToken)?.first, "and they sign in again")
            safety.decide(onTeam.reportId, "reinstated", "Renamed.", moderator)
            assertEquals(0, visibility("team", "team_id", team), "reinstating a hidden team makes it public again")
            safety.decide(onLeague.reportId, "reinstated", "Renamed.", moderator)
            assertEquals(0, visibility("league", "league_id", league))
            assertEquals("There is nothing to reinstate: no decision hid or suspended this.",
                         assertFailsWith<Safety.Refused> { safety.decide(onMatch.reportId, "reinstated", "Back.", moderator) }.why)

            // --- and every decision is on the record, in order --------------------------------------------------
            assertEquals(3, count(c, "SELECT count(*) FROM safety.decision WHERE report_id = '${onAccount.reportId}'"))
            assertEquals(2, safety.queue().first { it.report.reportId == onTeam.reportId }.decisions)
        }
    }

    @Test
    fun `a report raised by or about a child goes to the front of the queue`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-11T21:00:00Z")
            val ann = account(c, "Ann")
            val team = Organisations(c).createTeam("The Sun Inn", "Stockton-on-Tees")
            val ordinary = Safety(c) { at }.report(ann, "team", team, "The name is wrong.")
            val urgent = Safety(c) { at.plusSeconds(60) }.report(ann, "account", ann, "A child is being contacted.", urgent = true)

            assertEquals(listOf(urgent.reportId, ordinary.reportId), Safety(c) { at }.queue().map { it.report.reportId },
                         "the urgent one first, though it was raised later")
        }
    }

    @Test
    fun `a block needs no reason, is lifted rather than deleted, and both sides are blocked`() {
        if (!configured) return
        migrated().use { c ->
            val at = Instant.parse("2026-09-11T21:00:00Z")
            val safety = Safety(c) { at }
            val ann = account(c, "Ann")
            val bea = account(c, "Bea")

            assertEquals("You cannot block yourself.", assertFailsWith<Safety.Refused> { safety.block(ann, ann) }.why)
            assertFalse(safety.blocked(ann, bea))

            safety.block(ann, bea)
            safety.block(ann, bea)
            assertEquals(1, count(c, "SELECT count(*) FROM safety.block"), "blocking twice is blocking once")
            assertTrue(safety.blocked(ann, bea))
            assertTrue(safety.blocked(bea, ann), "the one who was blocked cannot reach back either")
            assertEquals(listOf(bea), safety.blocking(ann))
            assertTrue(safety.blocking(bea).isEmpty(), "and it is not their block to manage")

            Safety(c) { at.plusSeconds(60) }.lift(ann, bea)
            assertFalse(safety.blocked(ann, bea))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.block"), "the block is kept, marked lifted")
            assertEquals(1, count(c, "SELECT count(*) FROM safety.block WHERE lifted_at IS NOT NULL"))

            Safety(c) { at.plusSeconds(120) }.block(ann, bea)
            assertEquals(2, count(c, "SELECT count(*) FROM safety.block"), "blocking again is a new block")
        }
    }

    @Test
    fun `the terms are accepted once per version, and the version is what was agreed to`() {
        if (!configured) return
        migrated().use { c ->
            val safety = Safety(c) { Instant.parse("2026-09-11T21:00:00Z") }
            val ann = account(c, "Ann")

            assertFalse(safety.hasAcceptedTerms(ann), "nobody posts before agreeing")
            safety.acceptTerms(ann)
            safety.acceptTerms(ann)
            assertTrue(safety.hasAcceptedTerms(ann))
            assertEquals(1, count(c, "SELECT count(*) FROM safety.terms_acceptance WHERE account_id = '$ann'"))

            assertFalse(safety.hasAcceptedTerms(ann, "2027-01-01"), "new terms are a new agreement")
            safety.acceptTerms(ann, "2027-01-01")
            assertEquals(2, count(c, "SELECT count(*) FROM safety.terms_acceptance WHERE account_id = '$ann'"),
                         "and what they agreed to on each day is still readable")
        }
    }

    /// A person is blocked by the player somebody can actually see (PD-141).
    ///
    /// Blocking has always taken an account id, and no screen in the app has one: a roster row, a seat and
    /// an opponent line all carry a *player* id, and deliberately so — an account id is the stable handle
    /// to a person and handing it to every team-mate to make blocking possible would be a worse trade than
    /// the thing it bought. So the server does the joining, and the account id stays on the server.
    @Test
    fun `the player somebody can see is joined to the account behind them, and an unclaimed player is nobody`() {
        if (!configured) return
        migrated().use { c ->
            val safety = Safety(c) { Instant.parse("2026-09-11T21:00:00Z") }
            val ann = account(c, "Ann")
            val bea = account(c, "Bea")
            val beaPlayer = claimedPlayer(c, bea)

            assertEquals(bea, safety.accountBehind(beaPlayer), "the player's account, for the server alone")
            assertNull(safety.accountBehind(UUID.randomUUID()), "a player nobody has is nobody")
            assertNull(safety.accountBehind(unclaimedPlayer(c)), "a walk-up has no account to block")

            safety.block(ann, safety.accountBehind(beaPlayer)!!)
            assertTrue(safety.blocked(ann, bea), "blocking by player blocks the person")
        }
    }

    private fun claimedPlayer(c: Connection, accountId: UUID): UUID {
        val id = unclaimedPlayer(c)
        c.createStatement().use { st ->
            st.execute("INSERT INTO identity.player_claim (claim_id, player_id, account_id, method, claimed_at) " +
                       "VALUES ('${UUID.randomUUID()}', '$id', '$accountId', 'self_created', now())")
        }
        return id
    }

    private fun unclaimedPlayer(c: Connection): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { st ->
            st.execute("INSERT INTO competition.player (player_id, source) VALUES ('$id', 'organiser')")
        }
        return id
    }
}
