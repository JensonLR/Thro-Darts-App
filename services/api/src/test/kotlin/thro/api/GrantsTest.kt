package thro.api

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Scoping grants (ADR-006 mechanism 1).
 *
 * The property that matters most here is the one that looks like a bug if you skim it: a revoked
 * scorer's visit is still WRITTEN. Rejecting it would destroy evidence for an authorization reason,
 * and the dispute that needs that evidence is precisely the one where someone's authority was
 * contested. Authority annotates; it never gates.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class GrantsTest {

    private val host = System.getenv("PGHOST").orEmpty()
    private val configured = host.isNotBlank()

    private fun migrated(): Connection {
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        val c = DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
        c.createStatement().use { st ->
            for (s in listOf("evidence", "trust", "rating", "read")) {
                st.execute("DROP SCHEMA IF EXISTS $s CASCADE")
            }
            for (r in listOf("thro_owner", "app_match", "app_trust", "app_rating", "app_read")) {
                st.execute("DROP ROLE IF EXISTS $r")
            }
        }
        val dir = generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "services/api/migrations") }
            .firstOrNull { it.isDirectory } ?: File("migrations")
        dir.listFiles { f -> f.extension == "sql" }?.sortedBy { it.name }?.forEach { f ->
            c.createStatement().use { it.execute(f.readText()) }
        }
        return c
    }

    @Test
    fun `authority annotates evidence and never destroys it`() {
        if (!configured) {
            println("no database configured (set PGHOST) — grant tests skipped")
            return
        }
        val c = migrated()
        val grants = Grants(c)
        val h = CommandHandler(c)
        val event = UUID.randomUUID()
        val organiser = UUID.randomUUID()
        var passed = 0

        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        fun visit(
            match: UUID, device: UUID, actor: UUID, seq: Long, total: Int, at: Instant,
        ): CommandResult = h.handle(
            VisitCommand(
                commandId = UUID.randomUUID(), matchId = match, deviceId = device, deviceSeq = seq,
                actorId = actor, actorRole = "participant", correlationId = UUID.randomUUID(),
                player = "Home", visitTotal = total, dartsUsed = null,
                occurredAt = at.toString(), occurredTz = "Europe/London",
            ),
            "Home", "Away",
        )

        fun authorityOf(match: UUID, device: UUID): String? {
            c.prepareStatement(
                "SELECT authority FROM evidence.event WHERE match_id = ? AND device_id = ? ORDER BY device_seq DESC LIMIT 1",
            ).use { ps ->
                ps.setObject(1, match); ps.setObject(2, device)
                ps.executeQuery().use { rs -> return if (rs.next()) rs.getString(1) else null }
            }
        }

        fun eventCount(match: UUID): Int {
            c.prepareStatement("SELECT count(*) FROM evidence.event WHERE match_id = ?").use { ps ->
                ps.setObject(1, match)
                ps.executeQuery().use { rs -> rs.next(); return rs.getInt(1) }
            }
        }

        val sessionEndsAt = Instant.now().plus(10, ChronoUnit.HOURS)

        // --- a live grant ---------------------------------------------------------------------
        run {
            val match = UUID.randomUUID(); val device = UUID.randomUUID(); val actor = UUID.randomUUID()
            Matches(c).open(match, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
                playtestFormat(thro.engine.PlayerId("Home")))
            grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            check("a granted visit is applied", visit(match, device, actor, 1, 60, Instant.now()) is CommandResult.Applied)
            check("and is recorded as granted", authorityOf(match, device) == "granted")
        }

        // --- no grant at all ------------------------------------------------------------------
        run {
            val match = UUID.randomUUID(); val device = UUID.randomUUID(); val actor = UUID.randomUUID()
            Matches(c).open(match, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
                playtestFormat(thro.engine.PlayerId("Home")))
            check("an ungranted visit is still applied", visit(match, device, actor, 1, 60, Instant.now()) is CommandResult.Applied)
            check("and is flagged ungranted", authorityOf(match, device) == "ungranted")
            check("the evidence exists", eventCount(match) == 1)
        }

        // --- revoked before the visit ----------------------------------------------------------
        run {
            val match = UUID.randomUUID(); val device = UUID.randomUUID(); val actor = UUID.randomUUID()
            Matches(c).open(match, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
                playtestFormat(thro.engine.PlayerId("Home")))
            val g = grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            grants.revoke(g, organiser, "scorer reassigned")
            val at = Instant.now().plusSeconds(60)
            check("a revoked scorer's visit is still applied", visit(match, device, actor, 1, 60, at) is CommandResult.Applied)
            check("and is flagged revoked", authorityOf(match, device) == "revoked")
            check("the evidence was NOT destroyed", eventCount(match) == 1)
        }

        // --- revoked, but the visit happened before the revocation -----------------------------
        run {
            val match = UUID.randomUUID(); val device = UUID.randomUUID(); val actor = UUID.randomUUID()
            Matches(c).open(match, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
                playtestFormat(thro.engine.PlayerId("Home")))
            val before = Instant.now().minus(2, ChronoUnit.HOURS)
            val g = grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            grants.revoke(g, organiser, "reassigned after the fact")
            check(
                "a visit thrown BEFORE the revocation stays granted",
                visit(match, device, actor, 1, 60, before).let { it is CommandResult.Applied } &&
                    authorityOf(match, device) == "granted",
            )
        }

        // --- a stale journal replayed weeks later (ADR-006's named failure) ---------------------
        run {
            val match = UUID.randomUUID(); val device = UUID.randomUUID(); val actor = UUID.randomUUID()
            Matches(c).open(match, UUID.randomUUID(), UUID.randomUUID(), "Home", "Away",
                playtestFormat(thro.engine.PlayerId("Home")))
            grants.issue(event, actor, device, "participant", sessionEndsAt = Instant.now(), issuedBy = organiser)
            val weeksLater = Instant.now().plus(30, ChronoUnit.DAYS)
            check(
                "a visit from a stale journal is still applied",
                visit(match, device, actor, 1, 60, weeksLater) is CommandResult.Applied,
            )
            check("and is flagged expired", authorityOf(match, device) == "expired")
        }

        // --- an already-expired grant cannot be issued at all -----------------------------------
        run {
            val actor = UUID.randomUUID(); val device = UUID.randomUUID()
            val refused = try {
                grants.issue(
                    event, actor, device, "participant",
                    sessionEndsAt = Instant.now().minus(48, ChronoUnit.HOURS), issuedBy = organiser,
                )
                false
            } catch (e: org.postgresql.util.PSQLException) {
                e.message!!.contains("grant_expires_after_issue")
            }
            check("a grant that expires before it is issued is refused", refused)
        }

        // --- lifetime covers a tournament day ----------------------------------------------------
        run {
            val actor = UUID.randomUUID(); val device = UUID.randomUUID()
            val ends = Instant.now().plus(10, ChronoUnit.HOURS)
            grants.issue(event, actor, device, "participant", sessionEndsAt = ends, issuedBy = organiser)
            val (a, _) = grants.authorityFor(UUID.randomUUID(), actor, device, ends.plus(23, ChronoUnit.HOURS))
            check("a grant outlives the session by a day", a == Authority.GRANTED)
            val (b, _) = grants.authorityFor(UUID.randomUUID(), actor, device, ends.plus(25, ChronoUnit.HOURS))
            check("and expires after that", b == Authority.EXPIRED)
        }

        // --- reassignment revokes rather than adds ------------------------------------------------
        run {
            val actor = UUID.randomUUID(); val device = UUID.randomUUID()
            grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            c.prepareStatement(
                "SELECT count(*) FROM trust.scoring_grant WHERE actor_id = ? AND device_id = ? AND revoked_at IS NULL",
            ).use { ps ->
                ps.setObject(1, actor); ps.setObject(2, device)
                ps.executeQuery().use { rs ->
                    rs.next()
                    check("re-issuing leaves exactly one live grant", rs.getInt(1) == 1)
                }
            }
        }

        // --- a match-scoped grant is preferred over an event-wide one -----------------------------
        run {
            val actor = UUID.randomUUID(); val device = UUID.randomUUID(); val match = UUID.randomUUID()
            grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            val scoped = grants.issue(
                event, actor, device, "venue_scorer", matchId = match,
                sessionEndsAt = sessionEndsAt, issuedBy = organiser,
            )
            val (a, g) = grants.authorityFor(match, actor, device, Instant.now())
            check("the match-scoped grant wins", a == Authority.GRANTED && g == scoped)
        }

        // --- the revocation record survives -------------------------------------------------------
        run {
            val actor = UUID.randomUUID(); val device = UUID.randomUUID()
            val g = grants.issue(event, actor, device, "participant", sessionEndsAt = sessionEndsAt, issuedBy = organiser)
            grants.revoke(g, organiser, "suspected collusion")
            c.prepareStatement("SELECT revoked_by, revoked_reason FROM trust.scoring_grant WHERE grant_id = ?").use { ps ->
                ps.setObject(1, g)
                ps.executeQuery().use { rs ->
                    rs.next()
                    check(
                        "who revoked it and why is kept",
                        rs.getObject(1) == organiser && rs.getString(2) == "suspected collusion",
                    )
                }
            }
        }

        println("  $passed grant properties held")
        assertTrue(passed >= 16, "expected at least 16 properties, got $passed")
        assertNotNull(c)
    }
}
