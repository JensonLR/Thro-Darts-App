package thro.api

import java.sql.Connection
import java.sql.DriverManager
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * ADR-018's rule, under attack: two admins, two devices, one row.
 *
 * The conflict test is not two calls in sequence on one connection — that proves the trigger and
 * nothing about concurrency. It is two connections, both holding the same expected version, both
 * writing inside open transactions at the same moment. The second blocks on the first's row lock,
 * and when the first commits it must find zero rows to update and answer Stale with the current
 * row. Nothing is merged, nothing is overwritten, and a replay of either command returns exactly
 * what it returned the first time.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class OrganisationCommandTest {

    private fun connect(): Connection {
        val host = System.getenv("PGHOST")
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        return DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
    }

    @Test
    fun `a stale write is refused with the current row, a replay returns what it returned, and nobody unauthorised writes`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — organisation command tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        val rel = Relations(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        val ade = UUID.randomUUID()   // team admin
        val kim = UUID.randomUUID()   // team captain
        val zed = UUID.randomUUID()   // a stranger
        val phoneA = UUID.randomUUID()
        val phoneK = UUID.randomUUID()
        val team = orgs.createTeam("Riverside A", by = ade)
        rel.grant(ade, "admin", ObjectRef(ObjectType.TEAM, team.toString()))
        rel.grant(kim, "captain", ObjectRef(ObjectType.TEAM, team.toString()))

        // --- authorization: deny by default, recorded whichever way ------------------------------
        val strangerCmd = OrganisationCommands.Command.RenameTeam(UUID.randomUUID(), phoneA, zed, team, "Zed's Team", 1)
        val stranger = OrganisationCommands(c).handle(strangerCmd)
        check("a stranger cannot rename a team", stranger is OrganisationCommands.Result.Refused)
        check("the team is untouched", nameOf(c, team) == "Riverside A")
        c.prepareStatement("SELECT allowed FROM audit.decision WHERE subject_id = ? AND action = 'team.manage'")
            .use { ps -> ps.setObject(1, zed); ps.executeQuery().use { rs -> check("and the refusal is on the audit record", rs.next() && !rs.getBoolean(1)) } }
        check("a blank name is refused before anything is written",
            OrganisationCommands(c).handle(OrganisationCommands.Command.RenameTeam(UUID.randomUUID(), phoneA, ade, team, "  ", 1))
                is OrganisationCommands.Result.Refused)

        // --- the happy path, and idempotency -----------------------------------------------------
        val rename = OrganisationCommands.Command.RenameTeam(UUID.randomUUID(), phoneA, ade, team, "Riverside Arrows", 1)
        val first = OrganisationCommands(c).handle(rename)
        check("an admin's rename is applied at version 2", first == OrganisationCommands.Result.Applied(2))
        check("the row is renamed", nameOf(c, team) == "Riverside Arrows")
        val replay = OrganisationCommands(c).handle(rename)
        check("a replay of the same command returns the stored response and applies nothing",
            replay is OrganisationCommands.Result.Replayed && replay.stored.contains("\"applied\"") && versionOf(c, team) == 2)
        check("the previous name is kept with its period", c.prepareStatement(
            "SELECT count(*) FROM competition.team_name WHERE team_id = ? AND name = 'Riverside A' AND valid_until IS NOT NULL",
        ).use { ps -> ps.setObject(1, team); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) == 1 } })

        // --- a stale write, sequentially ---------------------------------------------------------
        val stale = OrganisationCommands.Command.RenameTeam(UUID.randomUUID(), phoneK, kim, team, "Riverside Club Darts", 1)
        val s = OrganisationCommands(c).handle(stale)
        check("a write carrying an old version is refused as stale",
            s is OrganisationCommands.Result.Stale && s.currentVersion == 2 && s.current.contains("Riverside Arrows"))
        check("and nothing changed", nameOf(c, team) == "Riverside Arrows" && versionOf(c, team) == 2)
        val staleReplay = OrganisationCommands(c).handle(stale)
        check("a replay of the stale command returns the stored stale response, not a fresh attempt",
            staleReplay is OrganisationCommands.Result.Replayed && staleReplay.stored.contains("\"stale\""))

        // --- the conflict test: two connections, same expected version, same moment -------------
        val fixtureSeason = orgs.openSeason(orgs.createLeague("Teesside Thursday"), "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        val away = orgs.createTeam("Grange A")
        val secretary = UUID.randomUUID()
        val treasurer = UUID.randomUUID()
        rel.grant(secretary, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, fixtureSeason.toString()))
        rel.grant(treasurer, "admin", ObjectRef(ObjectType.LEAGUE_SEASON, fixtureSeason.toString()))
        val t0 = Instant.parse("2026-10-01T19:30:00Z")
        val fixture = orgs.scheduleFixture(fixtureSeason, null, team, away, at = t0)

        val c1 = connect()
        val c2 = connect()
        try {
            val both = Executors.newFixedThreadPool(2)
            val ready = CountDownLatch(2)
            val go = CountDownLatch(1)
            fun race(conn: Connection, actor: UUID, device: UUID, to: Instant) = both.submit<OrganisationCommands.Result> {
                ready.countDown(); go.await(10, TimeUnit.SECONDS)
                OrganisationCommands(conn).handle(
                    OrganisationCommands.Command.RearrangeFixture(UUID.randomUUID(), device, actor, fixture, to, expectedVersion = 1),
                )
            }
            val f1 = race(c1, secretary, UUID.randomUUID(), t0.plus(7, ChronoUnit.DAYS))
            val f2 = race(c2, treasurer, UUID.randomUUID(), t0.plus(14, ChronoUnit.DAYS))
            ready.await(10, TimeUnit.SECONDS); go.countDown()
            val r1 = f1.get(30, TimeUnit.SECONDS)
            val r2 = f2.get(30, TimeUnit.SECONDS)
            both.shutdown()

            val applied = listOf(r1, r2).filterIsInstance<OrganisationCommands.Result.Applied>()
            val stales = listOf(r1, r2).filterIsInstance<OrganisationCommands.Result.Stale>()
            check("of two concurrent writers with the same expected version, exactly one is applied", applied.size == 1 && applied.single().version == 2)
            check("and the other is told the row is stale, with the current row", stales.size == 1 && stales.single().currentVersion == 2)
            val (ver, date) = c.prepareStatement("SELECT row_version, scheduled_at FROM competition.league_fixture WHERE fixture_id = ?")
                .use { ps -> ps.setObject(1, fixture); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) to rs.getTimestamp(2).toInstant() } }
            check("the fixture is at version 2 with exactly one of the two dates", ver == 2 && (date == t0.plus(7, ChronoUnit.DAYS) || date == t0.plus(14, ChronoUnit.DAYS)))
            check("the stale writer's date was not applied over the winner's", stales.single().current.let { cur ->
                (date == t0.plus(7, ChronoUnit.DAYS) && !cur.contains("2026-10-15")) || (date == t0.plus(14, ChronoUnit.DAYS) && !cur.contains("2026-10-08"))
            })
            c.prepareStatement("SELECT count(*), count(*) FILTER (WHERE outcome = 'applied'), count(*) FILTER (WHERE outcome = 'stale') FROM competition.command_receipt WHERE command_type = 'RearrangeFixture'")
                .use { ps -> ps.executeQuery().use { rs -> rs.next(); check("both commands have a receipt: one applied, one stale", rs.getInt(1) == 2 && rs.getInt(2) == 1 && rs.getInt(3) == 1) } }
            c.prepareStatement("SELECT count(*) FROM competition.league_fixture_change WHERE fixture_id = ?")
                .use { ps -> ps.setObject(1, fixture); ps.executeQuery().use { rs -> rs.next(); check("exactly one change was logged, with the original date", rs.getInt(1) == 1) } }
        } finally {
            c1.close(); c2.close()
        }

        // --- the rule holds outside the handler too ------------------------------------------------
        val outside = try {
            c.prepareStatement("UPDATE competition.league_fixture SET scheduled_at = now(), row_version = 7 WHERE fixture_id = ?")
                .use { ps -> ps.setObject(1, fixture); ps.executeUpdate() }
            false
        } catch (e: org.postgresql.util.PSQLException) {
            e.message!!.contains("stale write")
        }
        check("SQL that skips the handler is still refused by the row's trigger", outside)

        // --- a captain does not rearrange league fixtures --------------------------------------------
        val captainTry = OrganisationCommands(c).handle(
            OrganisationCommands.Command.RearrangeFixture(UUID.randomUUID(), phoneK, kim, fixture, t0.plus(21, ChronoUnit.DAYS), expectedVersion = 2),
        )
        check("a team captain cannot rearrange a league fixture unilaterally", captainTry is OrganisationCommands.Result.Refused)
        check("a receipt is written for a refusal too", c.prepareStatement(
            "SELECT count(*) FROM competition.command_receipt WHERE outcome = 'refused'",
        ).use { ps -> ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) >= 3 } })
        check("no application role can rewrite a receipt", try {
            c.createStatement().use { it.execute("SET ROLE app_competition") }
            try {
                c.createStatement().use { it.execute("UPDATE competition.command_receipt SET outcome = 'applied'") }; false
            } finally { c.createStatement().use { it.execute("RESET ROLE") } }
        } catch (e: org.postgresql.util.PSQLException) { e.message!!.contains("permission denied") })

        println("  $passed organisational command properties held")
        assertEquals(21, passed)
    }

    private fun nameOf(c: Connection, team: UUID): String =
        c.prepareStatement("SELECT name FROM competition.team WHERE team_id = ?").use { ps ->
            ps.setObject(1, team); ps.executeQuery().use { rs -> rs.next(); rs.getString(1) }
        }

    private fun versionOf(c: Connection, team: UUID): Int =
        c.prepareStatement("SELECT row_version FROM competition.team WHERE team_id = ?").use { ps ->
            ps.setObject(1, team); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) }
        }
}
