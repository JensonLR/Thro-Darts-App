package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.engine.BustRule
import thro.engine.Dart
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * A visit recorded as darts, and a league that keeps the darts scored before a bust (OD-023), through every path
 * that writes or replays a match: the command handler, an upload, a correction, the statistics and the record.
 *
 * The two rules the engine learned are only worth anything if every replay reads them the same way, so each test
 * here writes one way and reads another: a keep-rule bust written by a command is read back by a fresh replay, a
 * darts upload is read back by the match record, and the average is taken from the log rather than from the write.
 */
class DartsTest {
    private val configured = TestDatabase.configured
    private val at = Instant.parse("2026-09-24T19:30:00Z")

    private fun format(start: Int, bust: BustRule = BustRule.RESTORE_VISIT, firstTo: Int = 3) = MatchFormat(
        startingScore = start, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
        legs = Structure(StructureMode.FIRST_TO, firstTo), throwFirst = Seat.home, bustRule = bust,
    )

    private fun darts(vararg names: String): List<Dart> = names.map { requireNotNull(Dart.parse(it)) { it } }

    /** A match between two fresh competitors, scored on one device by the home player. */
    private class Table(val c: Connection, val match: UUID, val home: UUID, val device: UUID, val eventId: UUID? = null) {
        var seq = 0L
        /** A refused visit is no evidence and takes no place in the device's sequence, so only an applied one advances it. */
        fun visit(player: String, total: Int? = null, darts: List<Dart>? = null): CommandResult {
            return CommandHandler(c).handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = device, deviceSeq = seq + 1,
                    actorId = home, actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = player, visitTotal = total, dartsUsed = null,
                    occurredAt = "2026-09-24T19:00:00Z", occurredTz = "Europe/London", darts = darts,
                ),
            ).also { if (it is CommandResult.Applied) seq += 1 }
        }
        fun eventAt(seq: Long): UUID = c.prepareStatement(
            "SELECT event_id FROM evidence.event WHERE match_id = ? AND device_id = ? AND device_seq = ?",
        ).use { ps ->
            ps.setObject(1, match); ps.setObject(2, device); ps.setLong(3, seq)
            ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) as UUID }
        }
    }

    private fun table(c: Connection, f: MatchFormat, eventId: UUID? = null): Table {
        val match = UUID.randomUUID(); val home = UUID.randomUUID()
        Matches(c).open(match, home, UUID.randomUUID(), f, eventId)
        return Table(c, match, home, UUID.randomUUID(), eventId)
    }

    private fun one(c: Connection, sql: String): String? =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> if (rs.next()) rs.getString(1) else null } }

    // --- the command path ----------------------------------------------------------------------------

    @Test
    fun `a visit sent as darts is applied, stored with its darts, and replayed as darts`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val t = table(c, format(501))
            val r = t.visit("home", darts = darts("T20", "T20", "T20"))
            assertEquals("scored", (r as CommandResult.Applied).effect)

            val id = t.eventAt(1)
            assertEquals("2", one(c, "SELECT schema_version::text FROM evidence.event WHERE event_id = '$id'"), "a darts visit is schema 2")
            assertEquals("[\"T20\", \"T20\", \"T20\"]", one(c, "SELECT payload->>'darts' FROM evidence.event WHERE event_id = '$id'"))
            // What the engine derived is beside the darts, so a reader that knows only totals still reads it.
            assertEquals("180", one(c, "SELECT payload->>'visitTotal' FROM evidence.event WHERE event_id = '$id'"))
            assertEquals("3", one(c, "SELECT payload->>'dartsUsed' FROM evidence.event WHERE event_id = '$id'"))

            // A reload — a new handler on a new connection — replays the darts and lands on 321.
            TestDatabase.connect().use { fresh ->
                assertEquals(321, CommandHandler(fresh).replayFor(t.match, t.device).remaining.getValue(Seat.home))
            }
            // And a total is still stored exactly as it was: schema 1, no darts.
            t.visit("away", total = 60)
            assertEquals("1", one(c, "SELECT schema_version::text FROM evidence.event WHERE event_id = '${t.eventAt(2)}'"))
            assertEquals(null, one(c, "SELECT payload->>'darts' FROM evidence.event WHERE event_id = '${t.eventAt(2)}'"))
        }
    }

    @Test
    fun `T20 from 60 is a bust when the darts say so`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val t = table(c, format(60))
            val r = t.visit("home", darts = darts("T20")) as CommandResult.Applied
            assertEquals("bust", r.effect)
            assertEquals("NOT_A_FINISHING_DART", r.reason)
            assertEquals(60, CommandHandler(c).replayFor(t.match, t.device).remaining.getValue(Seat.home))
            // The same 60 as a total is a checkout, which is exactly why a replay must read the darts.
            val other = table(c, format(60))
            assertEquals("leg_won", (other.visit("home", total = 60) as CommandResult.Applied).effect)
        }
    }

    @Test
    fun `under the keep rule a bust keeps the darts before it, and a reload agrees`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val t = table(c, format(40, BustRule.KEEP_SCORED_DARTS))
            // On 40, a 20 then a D15: the 20 stands, the D15 counts for nothing.
            val bust = t.visit("home", darts = darts("20", "D15")) as CommandResult.Applied
            assertEquals("bust", bust.effect)
            TestDatabase.connect().use { fresh ->
                assertEquals(20, CommandHandler(fresh).replayFor(t.match, t.device).remaining.getValue(Seat.home),
                             "a fresh replay of the log reads the match's own rule")
            }
            t.visit("away", total = 10)
            // D10 finishes from 20 — and only from 20. The command path rehydrated the kept score.
            assertEquals("leg_won", (t.visit("home", darts = darts("D10")) as CommandResult.Applied).effect)

            // The standard rule, the same darts: back to 40.
            val std = table(c, format(40))
            std.visit("home", darts = darts("20", "D15"))
            assertEquals(40, CommandHandler(c).replayFor(std.match, std.device).remaining.getValue(Seat.home))
        }
    }

    @Test
    fun `under the keep rule a busting total is refused, because only darts can say what stands`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val t = table(c, format(40, BustRule.KEEP_SCORED_DARTS))
            val r = t.visit("home", total = 50)
            assertEquals(CommandResult.Refused("DARTS_REQUIRED"), r)
            assertEquals("0", one(c, "SELECT count(*)::text FROM evidence.event WHERE match_id = '${t.match}'"), "and it produced no evidence")
            // A total that does not bust is fine under either rule.
            assertTrue(t.visit("home", total = 20) is CommandResult.Applied)
        }
    }

    @Test
    fun `a dart that is not on the board is refused by the engine, with its reason`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val t = table(c, format(501))
            assertEquals(CommandResult.Refused("DART_INVALID"), t.visit("home", darts = listOf(Dart(25, thro.engine.Ring.TREBLE))))
        }
    }

    // --- the statistics --------------------------------------------------------------------------------

    @Test
    fun `the average under the keep rule counts the darts a bust kept`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val keep = format(40, BustRule.KEEP_SCORED_DARTS)
            val t = table(c, keep)
            t.visit("home", darts = darts("20", "D15"))
            val records = StatsProjection(c).visitsFor(t.match, t.device, "home", "away", keep).map { it.record }
            val v = records.single()
            assertTrue(v.bust); assertEquals(50, v.visitTotal); assertEquals(20, v.scored)
            assertEquals(20, v.remainingAfter, "the engine's remaining, not the standard rule's guess")
            val summary = StatsProjection(c).summaryFor(t.match, t.device, "home", "away", "home", keep)
            assertTrue(summary.contains("\"threeDartAverage\":{\"basis\":\"EXACT\",\"value\":20.00"), summary)

            // The same darts under the standard rule score nothing.
            val std = format(40)
            val s = table(c, std)
            s.visit("home", darts = darts("20", "D15"))
            val stdSummary = StatsProjection(c).summaryFor(s.match, s.device, "home", "away", "home", std)
            assertTrue(stdSummary.contains("\"threeDartAverage\":{\"basis\":\"EXACT\",\"value\":0.00"), stdSummary)
        }
    }

    // --- an upload -------------------------------------------------------------------------------------

    private fun player(c: Connection): UUID {
        val id = UUID.randomUUID()
        c.createStatement().use { it.execute("INSERT INTO competition.player (player_id, source) VALUES ('$id', 'self')") }
        return id
    }

    private fun row(seq: Long, seat: String, total: Int? = null, darts: List<Dart>? = null) =
        Uploads.Row(seq, "visit", seat, total, null, at.plusSeconds(seq * 20), "Europe/London", darts)

    private fun strike(seq: Long, seat: String, strikes: Long) =
        Uploads.Row(seq, "retraction", seat, null, strikes, at.plusSeconds(seq * 20), "Europe/London")

    @Test
    fun `an upload of darts under the keep rule is replayed, stored as the engine said, and read back the same`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val device = UUID.randomUUID(); val match = UUID.randomUUID()
            val keep = format(40, BustRule.KEEP_SCORED_DARTS, firstTo = 1)
            val out = Uploads(c) { at }.receive(me, device, match, "home", keep, listOf(
                row(1, "home", darts = darts("20", "D15")),
                row(2, "away", total = 30),
                // Both a total and the darts, agreeing: fine.
                row(3, "home", total = 20, darts = darts("D10")),
            ))
            val stored = out as? Uploads.Result.Stored ?: error("refused: $out")
            assertEquals(3, stored.visits)
            fun p(seq: Int, k: String) = one(c, "SELECT payload->>'$k' FROM evidence.event WHERE match_id = '$match' AND device_seq = $seq")
            assertEquals("bust", p(1, "effect")); assertEquals("50", p(1, "visitTotal")); assertEquals("[\"20\", \"D15\"]", p(1, "darts"))
            assertEquals("scored", p(2, "effect"))
            assertEquals("match_won", p(3, "effect"))
            assertEquals("keep_scored_darts", one(c, "SELECT bust_rule FROM evidence.match WHERE match_id = '$match'"))

            val record = MatchRecords(c).replay(match)!!
            assertEquals("home", record.winner, "the record replays the kept 20 and the D10 that finished it")
            val summary = MatchRecords(c).summary(match, me)!!
            assertTrue(MatchRecords(c).json(summary).contains("\"bustRule\":\"keepScoredDarts\""))
        }
    }

    @Test
    fun `an upload holding a visit that cannot have happened is refused, naming the row, and nothing lands`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val me = player(c); val uploads = Uploads(c) { at }
            fun send(f: MatchFormat, vararg rows: Uploads.Row): Pair<UUID, Uploads.Result> {
                val match = UUID.randomUUID()
                return match to uploads.receive(me, UUID.randomUUID(), match, "home", f, rows.toList())
            }
            fun why(r: Uploads.Result) = (r as? Uploads.Result.Refused)?.why ?: error("stored: $r")

            val (m1, impossible) = send(format(501), row(1, "home", total = 60), row(2, "away", total = 179))
            assertTrue(why(impossible).contains("row 2") && why(impossible).contains("no three darts score 179"), why(impossible))
            assertEquals("0", one(c, "SELECT count(*)::text FROM evidence.event WHERE match_id = '$m1'"))
            assertEquals(null, one(c, "SELECT match_id::text FROM evidence.match WHERE match_id = '$m1'"), "the match was not opened either")

            val (_, outOfTurn) = send(format(501), row(1, "away", total = 60))
            assertTrue(why(outOfTurn).contains("not that seat's turn"), why(outOfTurn))

            val (_, keepTotal) = send(format(40, BustRule.KEEP_SCORED_DARTS), row(1, "home", total = 50))
            assertTrue(why(keepTotal).contains("dart by dart"), why(keepTotal))

            val (_, contradicted) = send(format(501), row(1, "home", total = 170, darts = darts("T20", "T20", "T20")))
            assertTrue(why(contradicted).contains("says 170, but T20, T20, T20 scores 180"), why(contradicted))

            // A visit the scorer struck need not stand: the board showed it, so it is kept, as the engine found it.
            val (m2, struck) = send(format(501), row(1, "home", total = 179), strike(2, "home", 1), row(3, "home", total = 60))
            assertTrue(struck is Uploads.Result.Stored, "$struck")
            assertEquals("refused", one(c, "SELECT payload->>'effect' FROM evidence.event WHERE match_id = '$m2' AND device_seq = 1"))
            assertEquals("IMPOSSIBLE_VISIT_TOTAL", one(c, "SELECT payload->>'refused' FROM evidence.event WHERE match_id = '$m2' AND device_seq = 1"))
            assertEquals("scored", one(c, "SELECT payload->>'effect' FROM evidence.event WHERE match_id = '$m2' AND device_seq = 3"))
        }
    }

    // --- a correction ----------------------------------------------------------------------------------

    @Test
    fun `a correction is played before it is kept`() {
        if (!configured) return
        TestDatabase.migrated().use { c ->
            val rel = Relations(c)
            val event = UUID.randomUUID(); val official = UUID.randomUUID()
            val eventObj = ObjectRef(ObjectType.EVENT, event.toString())
            rel.grant(official, "official", eventObj)
            fun officiated(f: MatchFormat): Table = table(c, f, event).also {
                rel.link(ObjectRef(ObjectType.MATCH, it.match.toString()), eventObj)
            }
            var seq = 900L
            fun correct(t: Table, visitSeq: Long, to: Int) =
                Corrections(c).correctVisit(t.match, t.eventAt(visitSeq), official, to, UUID.randomUUID(), ++seq)
            fun why(r: Corrections.Result) = (r as? Corrections.Result.Refused)?.why ?: error("corrected: $r")

            // 101, first to one leg: home 60, away 45.
            val t = officiated(format(101, firstTo = 1))
            t.visit("home", total = 60); t.visit("away", total = 45)
            assertTrue(why(correct(t, 1, 179)).contains("no three darts score 179"))
            // 101 from 101 wins the match — and leaves away's 45 thrown after the match was over.
            val later = why(correct(t, 1, 101))
            assertTrue(later.contains("later visit (45)") && later.contains("already over"), later)
            // Away's 45 corrected to 101 is the last visit, so it stands, and it is stored as what it was: a win.
            val ok = correct(t, 2, 101)
            assertTrue(ok is Corrections.Result.Corrected, "$ok")
            val id = (ok as Corrections.Result.Corrected).correctionEventId
            assertEquals("match_won", one(c, "SELECT payload->>'effect' FROM evidence.event WHERE event_id = '$id'"))

            // Under the keep rule a correction to a busting total is refused: only darts say what stands.
            val k = officiated(format(40, BustRule.KEEP_SCORED_DARTS))
            k.visit("home", total = 20)
            assertTrue(why(correct(k, 1, 50)).contains("dart by dart"))
            assertEquals("0", one(c, "SELECT count(*)::text FROM evidence.event WHERE match_id = '${k.match}' AND event_type = 'VisitCorrected'"))
        }
    }
}
