package thro.api

import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.MembershipRole

/**
 * Who changed what (PD-120). A season's officials record results, correct them, award and annul, move fixtures, set
 * the rules and register players — and every one of those is already a row with an actor and a time, because nothing
 * here is ever edited in place. The history reads those rows back as sentences, newest first, for the season's
 * administrators: the answer to "who put that result in?" without anybody opening a database.
 */
class SeasonHistoryTest {

    @Test
    fun `a season's history says who did what, in words, newest first`() {
        if (!TestDatabase.configured) return
        TestDatabase.migrated().use { c ->
            val orgs = Organisations(c); val rel = Relations(c); val accounts = Accounts(c)
            val device = UUID.randomUUID()
            val t0 = Instant.parse("2026-09-01T18:00:00Z")
            fun person(sub: String, name: String): UUID {
                val s = accounts.signIn("apple", sub, device); accounts.setDisplayName(s.accountId, name)
                // A name is shown only for an adult who has said their name may be listed; anybody else is "An official".
                Friends(c).declareAge(s.accountId, "adult"); Consent(c).say(s.accountId, Consent.Scope.LISTING, yes = true)
                return s.playerId!!
            }
            val lee = person("008.lee", "Lee Organiser"); val sam = person("008.sam", "Sam Wilson")
            val league = orgs.createLeague("Teesside Thursday League")
            val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
            rel.grant(lee, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString()))
            val a = orgs.createDivision(season, "Division A", 1)
            val riverside = orgs.createTeam("Riverside A", by = lee); val grange = orgs.createTeam("Grange A", by = lee)
            for (t in listOf(riverside, grange)) orgs.acceptAffiliation(orgs.affiliate(t, season, divisionId = a, from = t0), t0)
            val first = orgs.scheduleFixture(season, a, riverside, grange, Instant.parse("2026-10-08T18:30:00Z"))
            val second = orgs.scheduleFixture(season, a, grange, riverside, Instant.parse("2026-11-05T19:30:00Z"))

            val declared = orgs.declareResult(first, 5, 3, by = lee)
            val corrected = orgs.declareResult(first, 4, 3, by = lee, supersedes = declared)
            orgs.voidOutcome(first, corrected, "Wrong night: it has not been played.", by = lee)
            orgs.awardFixture(first, riverside, "Grange did not turn up.", by = lee)
            // A move through the organiser's own command, which now says who made it.
            val moved = OrganisationCommands(c).handle(OrganisationCommands.Command.RearrangeFixture(UUID.randomUUID(), device, lee, second, Instant.parse("2026-11-12T20:00:00Z"), expectedVersion = 1))
            assertTrue(moved is OrganisationCommands.Result.Applied, moved.toString())
            LeagueActs(c).setPoints(season, lee, win = 3, draw = 1, loss = 0, awarded = null, perLegWon = null, tieBreak = null, awardsCountAsPlayed = null)
            val policy = orgs.draftPolicy("league_season", season, "registration", 1, LocalDate.of(2026, 9, 1), """{"requires":["name"]}""", by = lee)
            orgs.approvePolicy(policy, by = lee)
            orgs.register(sam, season, riverside, policy, from = t0, by = lee)

            // Read as the server reads it: the role the API narrows to, not the owner.
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            val history = SeasonHistory(c).of(season)
            c.createStatement().use { it.execute("RESET ROLE") }
            val said = history.map { it.what }

            assertTrue(said.contains("Recorded Riverside A 5–3 Grange A"), said.toString())
            assertTrue(said.contains("Corrected Riverside A v Grange A to 4–3 (it was 5–3)"), said.toString())
            assertTrue(said.contains("Annulled the result of Riverside A v Grange A — Wrong night: it has not been played."), said.toString())
            assertTrue(said.contains("Awarded Riverside A v Grange A to Riverside A — Grange did not turn up."), said.toString())
            assertTrue(said.contains("Moved Grange A v Riverside A from Thu 5 Nov, 7:30 pm to Thu 12 Nov, 8:00 pm"), said.toString())
            assertTrue(said.any { it.startsWith("Set the points rules (version 1)") }, said.toString())
            assertTrue(said.contains("Registered Sam Wilson with Riverside A"), said.toString())
            assertTrue(history.all { it.who == "Lee Organiser" }, "every act here was Lee's, the move included: " + history.map { it.who to it.what })
            assertEquals(history.sortedByDescending { it.at }.map { it.what }, said, "newest first")
            assertEquals(setOf("result", "correction", "void", "award", "move", "rules", "registration"), history.map { it.kind }.toSet())
        }
    }
}
