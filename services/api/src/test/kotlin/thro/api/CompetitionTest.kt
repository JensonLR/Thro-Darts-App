package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.competition.Bracket

/**
 * The competition lifecycle, and the thing it exists to make possible: check-in issues the scoring
 * grant that lets a player score all day with no network.
 *
 * The 74-entrant case is here on purpose. The approved organiser design describes it as "Round of
 * 64 with 10 byes"; 10 is the preliminary-match count and the real bye figure is 54. That was one
 * of the defects found in the design, so it is the field size worth asserting against.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class CompetitionTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    @Test
    fun `check-in issues the grant that makes offline scoring possible`() {
        if (!configured) {
            println("no database configured (set PGHOST) — competition tests skipped")
            return
        }
        val c = migrated()
        val comp = Competitions(c)
        val grants = Grants(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        val eventId = UUID.randomUUID()
        val organiser = UUID.randomUUID()
        val starts = Instant.now()
        val ends = starts.plus(10, ChronoUnit.HOURS)
        comp.openEvent(eventId, "County Open", starts, ends, "The Red Lion")

        val alice = UUID.randomUUID()
        val device = UUID.randomUUID()
        comp.enter(eventId, alice, seed = 1)

        // Before check-in there is no authority to record anything.
        val (before, _) = grants.authorityFor(UUID.randomUUID(), alice, device, Instant.now())
        check("an entrant who has not checked in holds no grant", before == Authority.UNGRANTED)

        val checkedIn = comp.checkIn(eventId, alice, device, organiser)
        val (after, gid) = grants.authorityFor(UUID.randomUUID(), alice, device, Instant.now())
        check("checking in issues a grant", after == Authority.GRANTED)
        check("and the check-in records which one", gid == checkedIn.grantId)

        // The grant must outlast a tournament day, which is the whole point of issuing it here.
        val (lateInTheDay, _) = grants.authorityFor(
            UUID.randomUUID(), alice, device, ends.minus(1, ChronoUnit.HOURS),
        )
        check("it is still valid at the end of a ten-hour session", lateInTheDay == Authority.GRANTED)
        val (nextMorning, _) = grants.authorityFor(
            UUID.randomUUID(), alice, device, ends.plus(20, ChronoUnit.HOURS),
        )
        check("and the morning after", nextMorning == Authority.GRANTED)
        val (later, _) = grants.authorityFor(
            UUID.randomUUID(), alice, device, ends.plus(30, ChronoUnit.HOURS),
        )
        check("but not indefinitely", later == Authority.EXPIRED)

        // Checking in again on the same device supersedes rather than duplicating.
        comp.checkIn(eventId, alice, device, organiser)
        c.prepareStatement(
            "SELECT count(*) FROM trust.scoring_grant WHERE actor_id = ? AND revoked_at IS NULL",
        ).use { ps ->
            ps.setObject(1, alice)
            ps.executeQuery().use { rs ->
                rs.next()
                check("re-checking in leaves exactly one live grant", rs.getInt(1) == 1)
            }
        }

        // --- the draw, on the field size the design got wrong -------------------------------------
        val big = UUID.randomUUID()
        comp.openEvent(big, "74 entrants", starts, ends)
        repeat(74) { comp.enter(big, UUID.randomUUID(), seed = it + 1) }
        val fixtures = comp.draw(big)

        val math = Bracket.math(74)
        check("the bracket is 128, not 64", math.bracketSize == 128)
        check("there are 54 byes, not 10", math.byes == 54)
        check("and 10 preliminary matches", math.preliminaryMatches == 10)
        check("the draw makes one fixture per bye plus one per match", fixtures.size == 54 + 10)

        c.prepareStatement(
            "SELECT count(*) FILTER (WHERE is_bye), count(*) FILTER (WHERE NOT is_bye) FROM competition.fixture WHERE event_id = ?",
        ).use { ps ->
            ps.setObject(1, big)
            ps.executeQuery().use { rs ->
                rs.next()
                check("54 of them are byes", rs.getInt(1) == 54)
                check("and 10 are matches", rs.getInt(2) == 10)
            }
        }

        // A bye is not a win: it creates no match and cannot be given one. A real match has to
        // exist for this to test anything — an earlier version used a subquery that returned NULL,
        // so the update set match_id to null and succeeded without exercising the constraint.
        val realMatch = UUID.randomUUID()
        Matches(c).open(
            realMatch, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
            playtestFormat(thro.engine.PlayerId("Home")),
        )
        val r = try {
            c.prepareStatement(
                "UPDATE competition.fixture SET match_id = ? WHERE event_id = ? AND is_bye",
            ).use { ps ->
                ps.setObject(1, realMatch); ps.setObject(2, big)
                ps.executeUpdate()
            }
            false
        } catch (e: org.postgresql.util.PSQLException) {
            e.message!!.contains("bye_is_never_a_match")
        }
        check("a bye can never be given a match", r)

        // Two competitors cannot share a seed: a non-deterministic draw is uncheckable afterwards.
        val dup = UUID.randomUUID()
        comp.openEvent(dup, "seeds", starts, ends)
        comp.enter(dup, UUID.randomUUID(), seed = 1)
        val clash = try {
            comp.enter(dup, UUID.randomUUID(), seed = 1)
            false
        } catch (e: org.postgresql.util.PSQLException) {
            e.message!!.contains("entry_seed_unique")
        }
        check("two competitors cannot hold the same seed", clash)

        println("  $passed competition properties held")
        assertEquals(15, passed)
    }
}
