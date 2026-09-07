package thro.journal

import thro.engine.Command
import thro.engine.InRule
import thro.engine.OutRule
import thro.engine.StructureMode
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The Android journal, held to the same properties as the iOS one.
 *
 * These are not "the same tests translated". They are the same **claims**: ADR-002 says the domain
 * is one domain rendered on two platforms, and the way that stops being a slogan is for both
 * renderings to be pinned by the same assertions. Where a number appears here it is the number the
 * Swift test asserts.
 */
class JournalTest {

    private lateinit var dir: Path
    private lateinit var path: String
    private val device = DeviceId("test-device")

    @BeforeTest fun setUp() {
        dir = Files.createTempDirectory("thro-journal")
        path = dir.resolve("journal.sqlite").toString()
    }

    @AfterTest fun tearDown() {
        dir.toFile().deleteRecursively()
    }

    private fun open(): Journal = Journal.open(path, device)

    private fun visit(seat: Seat, total: Int, dartsUsed: Int? = null, dartsAtDouble: Int? = null) =
        Command.RecordVisit(seat.playerId, total, dartsUsed, dartsAtDouble)

    // MARK: configuration

    /** The pragmas are read back, not assumed. This is the lesson the durability probe paid for. */
    @Test fun theConfigurationIsInForceAfterOpen() {
        open().use { j ->
            val inForce = j.configurationInForce
            assertEquals("wal", inForce["journal_mode"]?.lowercase())
            assertEquals("2", inForce["synchronous"], "FULL reads back as 2")
        }
    }

    /**
     * An in-memory database cannot enter WAL; it reports `memory`. Opening must throw rather than
     * carry on under a configuration that is not the one asked for.
     */
    @Test fun aRefusedConfigurationIsAnErrorNotASilentSuccess() {
        val e = assertFailsWith<JournalException.ConfigurationNotInForce> {
            Journal.open(":memory:", device)
        }
        assertEquals("journal_mode", e.pragma)
        assertEquals("wal", e.wanted)
        assertEquals("memory", e.got)
    }

    /**
     * **Android is not claimed to be durable.** `DurabilityConfiguration` asks for two pragmas, not
     * iOS's four, because Apple's `fullfsync` has no Android equivalent and reading the pragma back
     * would return 1 while nothing had happened to the hardware. This holds the shape of that
     * decision so it cannot be quietly widened into a claim.
     */
    @Test fun theConfigurationClaimsOnlyWhatItCanVerify() {
        assertEquals("WAL", DurabilityConfiguration.candidate.journalMode)
        assertEquals("FULL", DurabilityConfiguration.candidate.synchronous)
        open().use { j ->
            assertEquals(setOf("journal_mode", "synchronous"), j.configurationInForce.keys)
        }
    }

    // MARK: appending

    @Test fun deviceSequenceIsGaplessAndStartsAtOne() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            val seqs = (1..5).map { j.append(visit(Seat.HOME, 60), m.id).deviceSeq }
            assertEquals(listOf(1L, 2L, 3L, 4L, 5L), seqs)
        }
    }

    @Test fun anAppendSurvivesCloseAndReopen() {
        val id: MatchId
        val written: List<String>
        open().use { j ->
            val m = j.createMatch(NewMatch("Home", "Away"))
            id = m.id
            written = listOf(
                j.append(visit(Seat.HOME, 140), id).commandId,
                j.append(visit(Seat.AWAY, 100), id).commandId,
            )
        }
        open().use { j ->
            val read = j.entries(id)
            assertEquals(listOf(140, 100), read.map { it.visitTotal })
            assertEquals(written, read.map { it.commandId })
            assertEquals("Home", j.match(id).homeName)
        }
    }

    /** The database, not the caller, refuses to rewrite history. */
    @Test fun theJournalIsAppendOnly() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            j.append(visit(Seat.HOME, 60), m.id)
            for (sql in listOf("UPDATE journal SET visit_total = 180;", "DELETE FROM journal;")) {
                val e = assertFailsWith<JournalException.Sqlite> { raw(sql) }
                assertContains(e.message ?: "", "append-only")
            }
            assertEquals(listOf(60), j.entries(m.id).map { it.visitTotal })
        }
    }

    // MARK: replay

    /**
     * A whole leg, played through the engine and journaled, is rebuilt exactly by replay —
     * including whose turn it is and which leg the match is on.
     */
    @Test fun replayReproducesTheEngineState() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B", legsTarget = 1))
            j.append(visit(Seat.HOME, 180), m.id)
            j.append(visit(Seat.AWAY, 100), m.id)
            j.append(visit(Seat.HOME, 180), m.id)
            j.append(visit(Seat.AWAY, 100), m.id)
            j.append(visit(Seat.HOME, 141, dartsUsed = 3, dartsAtDouble = 1), m.id)

            val state = j.replay(m.id)
            assertTrue(state.isComplete)
            assertEquals(Seat.HOME.playerId, state.winner)
            assertEquals(1, state.legsWonTotal[Seat.HOME.playerId])
        }
    }

    /**
     * Ordinals are per (seat, leg) and never shared between the competitors — the mistake that once
     * put the wrong three visits into a first-nine average.
     */
    @Test fun replayedVisitsCarryPerSeatOrdinalsAndOutcomes() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B", legsTarget = 1))
            j.append(visit(Seat.HOME, 180), m.id)
            j.append(visit(Seat.AWAY, 100), m.id)
            j.append(visit(Seat.HOME, 180), m.id)
            j.append(visit(Seat.AWAY, 100), m.id)
            j.append(visit(Seat.HOME, 141, dartsUsed = 3, dartsAtDouble = 1), m.id)

            val (_, visits) = j.replayVisits(m.id)
            assertEquals(listOf(1, 1, 2, 2, 3), visits.map { it.visitOrdinal })
            assertEquals(
                listOf(Seat.HOME, Seat.AWAY, Seat.HOME, Seat.AWAY, Seat.HOME),
                visits.map { it.seat },
            )
            assertTrue(visits.last().wonLeg)
            assertEquals(141, visits.last().remainingBefore)
            assertEquals(0, visits.last().remainingAfter)
            assertTrue(visits.none { it.bust })
        }
    }

    @Test fun aBustIsReplayedAsABustWithRemainingRestored() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B", startingScore = 101, legsTarget = 1))
            // 100 leaves 1 under double-out: a bust, and the score goes back to 101.
            j.append(visit(Seat.HOME, 100), m.id)
            val (state, visits) = j.replayVisits(m.id)
            assertTrue(visits.single().bust)
            assertEquals(101, visits.single().remainingBefore)
            assertEquals(101, visits.single().remainingAfter)
            assertEquals(101, state.remaining[Seat.HOME.playerId])
        }
    }

    /** A rejection during replay is corruption. It throws; it never skips. */
    @Test fun aReplayThatHitsARejectionThrowsRatherThanSkipping() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            // 179 is not a total three darts can make.
            raw(
                "INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total, " +
                    "occurred_at) VALUES ('${m.id.value}', 'test-device', 1, 'corrupt', 'home', 179, " +
                    "'2026-09-05T00:00:00.000Z');",
            )
            val e = assertFailsWith<JournalException.ReplayRejected> { j.replay(m.id) }
            assertEquals("IMPOSSIBLE_VISIT_TOTAL", e.reason)
        }
    }

    /**
     * A row kind this build cannot read is refused rather than replayed as a visit. Falling back to
     * a visit would put a score in the match that nobody threw.
     */
    @Test fun aRowThisBuildCannotReadIsRefusedRatherThanScoredAsAVisit() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            j.append(visit(Seat.HOME, 60), m.id)
            raw(
                "INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, " +
                    "visit_total, occurred_at) VALUES ('${m.id.value}', 'test-device', 2, 'alien', " +
                    "'sponsorship', 'home', 0, '2026-09-05T00:00:00.000Z');",
            )
            assertEquals(JournalEntry.Kind.UNKNOWN, j.entries(m.id)[1].kind)
            val e = assertFailsWith<JournalException.ReplayRejected> { j.replay(m.id) }
            assertEquals("UNKNOWN_ROW_KIND", e.reason)
        }
    }

    // MARK: matches

    @Test fun matchesListsWhatIsOnThisDeviceNewestFirst() {
        open().use { j ->
            val older = j.createMatch(NewMatch("A", "B"), startedAt = Instant.ofEpochSecond(1_000))
            val newer = j.createMatch(NewMatch("C", "D"), startedAt = Instant.ofEpochSecond(2_000))
            assertEquals(listOf(newer.id, older.id), j.matches().map { it.id })
            assertFailsWith<JournalException.MatchNotFound> { j.match(MatchId("nope")) }
        }
    }

    @Test fun aMatchRecordRebuildsItsFormat() {
        open().use { j ->
            val m = j.createMatch(
                NewMatch(
                    "A", "B", startingScore = 301, inRule = InRule.DOUBLE, outRule = OutRule.STRAIGHT,
                    legsMode = StructureMode.FIRST_TO, legsTarget = 2, throwFirst = Seat.AWAY,
                ),
            )
            val f = j.match(m.id).format
            assertEquals(301, f.startingScore)
            assertEquals(InRule.DOUBLE, f.inRule)
            assertEquals(OutRule.STRAIGHT, f.outRule)
            assertEquals(StructureMode.FIRST_TO, f.legs.mode)
            assertEquals(2, f.legs.target)
            assertEquals(Seat.AWAY.playerId, f.throwFirst)
            assertEquals(Seat.AWAY.playerId, j.match(m.id).initialState.thrower)
        }
    }

    // MARK: retractions (PD-004)

    private fun threeVisits(j: Journal): MatchRecord {
        val m = j.createMatch(NewMatch("A", "B"))
        j.append(visit(Seat.HOME, 180), m.id)
        j.append(visit(Seat.AWAY, 60), m.id)
        j.append(visit(Seat.HOME, 100), m.id)
        return m
    }

    @Test fun aRetractionStrikesTheLastVisitFromReplayButNotFromTheRecord() {
        open().use { j ->
            val m = threeVisits(j)
            j.retractLastVisit(m.id)
            val all = j.entries(m.id)
            assertEquals(4, all.size, "nothing is deleted")
            assertEquals(listOf(180, 60), Journal.standingVisits(all).map { it.visitTotal })
            assertEquals(3L, all.last().correctsSeq)
        }
    }

    @Test fun retractingAgainWalksOneFurtherBack() {
        open().use { j ->
            val m = threeVisits(j)
            j.retractLastVisit(m.id)
            j.retractLastVisit(m.id)
            assertEquals(listOf(180), Journal.standingVisits(j.entries(m.id)).map { it.visitTotal })
        }
    }

    @Test fun retractingWithNothingStandingThrows() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            assertFailsWith<JournalException.NothingToRetract> { j.retractLastVisit(m.id) }
        }
    }

    // MARK: attestation (PD-011)

    @Test fun anAttestationIsAppendedAndChangesNothingAboutTheScore() {
        open().use { j ->
            val m = threeVisits(j)
            val before = j.replay(m.id)
            j.attest(m.id, Seat.HOME, agrees = true)
            assertEquals(before, j.replay(m.id))
            assertEquals(setOf(Seat.HOME), j.standing(m.id).confirmed)
        }
    }

    @Test fun bothConfirmingIsBothConfirmingAndOneContestOutranksIt() {
        open().use { j ->
            val m = threeVisits(j)
            j.attest(m.id, Seat.HOME, agrees = true)
            j.attest(m.id, Seat.AWAY, agrees = true)
            assertTrue(j.standing(m.id).bothConfirmed)
            j.attest(m.id, Seat.AWAY, agrees = false)
            val standing = j.standing(m.id)
            assertFalse(standing.bothConfirmed)
            assertTrue(standing.anyContest)
            assertEquals(setOf(Seat.AWAY), standing.contested)
        }
    }

    @Test fun anAgreementDoesNotSurviveTheResultChangingUnderIt() {
        open().use { j ->
            val m = threeVisits(j)
            j.attest(m.id, Seat.HOME, agrees = true)
            j.attest(m.id, Seat.AWAY, agrees = true)
            assertTrue(j.standing(m.id).bothConfirmed)
            j.retractLastVisit(m.id)
            val standing = j.standing(m.id)
            assertTrue(standing.stale)
            assertFalse(standing.bothConfirmed, "what they agreed to is no longer what is recorded")
        }
    }

    // MARK: ending a match short (PD-016)

    @Test fun retiringHasAWinnerAndAbandoningHasNone() {
        open().use { j ->
            val retired = threeVisits(j)
            j.end(retired.id, Ending.Retired(Seat.HOME))
            assertEquals(Ending.Retired(Seat.HOME), j.ending(retired.id))
            assertEquals(Seat.AWAY, j.ending(retired.id)?.winner)
            assertTrue(j.ending(retired.id)!!.isResult)

            val gone = threeVisits(j)
            j.end(gone.id, Ending.Abandoned)
            assertEquals(Ending.Abandoned, j.ending(gone.id))
            assertNull(j.ending(gone.id)?.winner)
            assertFalse(j.ending(gone.id)!!.isResult)
        }
    }

    /**
     * The seat an abandonment has to store is proved inert by writing the other one and reading the
     * same answer — a stronger guarantee than the comment beside the placeholder.
     */
    @Test fun abandonmentIgnoresTheSeatItStores() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            raw(
                "INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, " +
                    "visit_total, occurred_at) VALUES ('${m.id.value}', 'test-device', 1, 'aw', " +
                    "'abandonment', 'away', 0, '2026-09-05T00:00:00.000Z');",
            )
            assertEquals(Ending.Abandoned, j.ending(m.id))
            assertNull(j.ending(m.id)?.winner)
        }
    }

    @Test fun anEndingIsFinalAndASecondOneIsRefused() {
        open().use { j ->
            val m = threeVisits(j)
            j.end(m.id, Ending.Retired(Seat.HOME))
            assertFailsWith<JournalException.AlreadyEnded> { j.end(m.id, Ending.Abandoned) }
            assertEquals(Ending.Retired(Seat.HOME), j.ending(m.id))
        }
    }

    @Test fun anEndedMatchTakesNoVisitAndNoRetraction() {
        open().use { j ->
            val m = threeVisits(j)
            j.end(m.id, Ending.Abandoned)
            assertFailsWith<JournalException.AlreadyEnded> { j.append(visit(Seat.AWAY, 60), m.id) }
            assertFailsWith<JournalException.AlreadyEnded> { j.retractLastVisit(m.id) }
        }
    }

    @Test fun anEndedMatchStillReplaysEveryVisitThrownInIt() {
        open().use { j ->
            val m = threeVisits(j)
            j.end(m.id, Ending.Abandoned)
            assertEquals(3, Journal.standingVisits(j.entries(m.id)).size)
            assertEquals(221, j.replay(m.id).remaining[Seat.HOME.playerId], "501 − 180 − 100")
        }
    }

    // MARK: the device identity

    /**
     * The journal keeps the identity it was created with even if the caller forgets it. A new
     * identity would restart `device_seq` at 1 for a match that already had rows, and one device
     * would arrive at a server as two.
     */
    @Test fun theJournalKeepsTheIdentityItWasCreatedWith() {
        val id: MatchId
        Journal.open(path, DeviceId("first")).use { j ->
            id = j.createMatch(NewMatch("A", "B")).id
            j.append(visit(Seat.HOME, 60), id)
            assertNull(j.deviceIdSupersededCallers)
        }
        Journal.open(path, DeviceId("forgotten")).use { j ->
            assertEquals("first", j.deviceId.value)
            assertEquals("forgotten", j.deviceIdSupersededCallers?.value)
            assertEquals(2L, j.append(visit(Seat.AWAY, 60), id).deviceSeq, "the sequence continues")
        }
    }

    // MARK: the shelf and the one delete (PD-026)

    @Test fun archivingTakesAMatchOffHomeAndNowhereElse() {
        open().use { j ->
            val kept = j.createMatch(NewMatch("A", "B"), startedAt = Instant.ofEpochSecond(2_000))
            val shelved = j.createMatch(NewMatch("C", "D"), startedAt = Instant.ofEpochSecond(1_000))
            j.append(visit(Seat.HOME, 60), shelved.id)

            j.setArchived(shelved.id, true)
            assertEquals(listOf(kept.id), j.matches(archived = false).map { it.id })
            assertEquals(listOf(shelved.id), j.matches(archived = true).map { it.id })
            assertEquals(listOf(kept.id, shelved.id), j.matches().map { it.id }, "everything, for the export")
            assertTrue(j.match(shelved.id).isArchived)
            assertEquals(listOf(60), j.entries(shelved.id).map { it.visitTotal }, "the visit is untouched")

            j.setArchived(shelved.id, false)
            assertFalse(j.match(shelved.id).isArchived)
            assertFailsWith<JournalException.MatchNotFound> { j.setArchived(MatchId("nope"), true) }
        }
    }

    @Test fun theShelfSurvivesReopening() {
        val id: MatchId
        open().use { j ->
            id = j.createMatch(NewMatch("A", "B")).id
            j.setArchived(id, true)
        }
        open().use { j ->
            assertTrue(j.match(id).isArchived)
            assertTrue(j.matches(archived = false).isEmpty())
        }
    }

    @Test fun deletingAMatchTakesItsVisitsAndNothingElse() {
        open().use { j ->
            val doomed = j.createMatch(NewMatch("A", "B"))
            val kept = j.createMatch(NewMatch("C", "D"))
            j.append(visit(Seat.HOME, 180), doomed.id)
            j.append(visit(Seat.AWAY, 60), doomed.id)
            j.append(visit(Seat.HOME, 100), kept.id)

            assertEquals(2, j.deleteMatch(doomed.id), "it says how many darts went with it")
            assertEquals(listOf(kept.id), j.matches().map { it.id })
            assertFailsWith<JournalException.MatchNotFound> { j.match(doomed.id) }
            assertTrue(j.entries(doomed.id).isEmpty())
            assertEquals(listOf(100), j.entries(kept.id).map { it.visitTotal })
            assertFailsWith<JournalException.MatchNotFound> { j.deleteMatch(doomed.id) }
        }
    }

    /**
     * The delete a person asks for is the ONLY delete. A bare `DELETE FROM journal` still aborts,
     * and so does a delete of another match's rows while a purge is running — which is the
     * difference between narrowing the rule and removing it.
     */
    @Test fun aPurgeUnlocksOnlyTheMatchItNames() {
        open().use { j ->
            val named = j.createMatch(NewMatch("A", "B"))
            val other = j.createMatch(NewMatch("C", "D"))
            j.append(visit(Seat.HOME, 60), named.id)
            j.append(visit(Seat.HOME, 41), other.id)

            raw("INSERT OR REPLACE INTO meta (key, value) VALUES ('purging', '${named.id.value}');")
            val blocked = assertFailsWith<JournalException.Sqlite> {
                raw("DELETE FROM journal WHERE match_id = '${other.id.value}';")
            }
            assertContains(blocked.message ?: "", "append-only")
            assertEquals(listOf(41), j.entries(other.id).map { it.visitTotal })

            raw("DELETE FROM meta WHERE key = 'purging';")
            assertFailsWith<JournalException.Sqlite> {
                raw("DELETE FROM journal WHERE match_id = '${named.id.value}';")
            }
        }
    }

    // MARK: a replay returns what was stored

    /**
     * The server has answered replays this way since the command path shipped — *"a replay returns
     * the stored response, including a stored refusal"* — and the journal did not. A duplicate
     * command id hit the UNIQUE constraint and reached the player as *"Not saved, so not
     * recorded"* for a visit that **was** saved, which is the worst shape a durability error can
     * have.
     */
    @Test fun aReplayedVisitReturnsTheStoredRowAndWritesNothing() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            val first = j.append(visit(Seat.HOME, 60), m.id, commandId = "cmd-1")
            val again = j.append(visit(Seat.HOME, 60), m.id, commandId = "cmd-1")
            assertEquals(first, again, "the stored row, returned verbatim")
            assertEquals(1, j.entries(m.id).size, "and nothing was written a second time")
            assertEquals(1L, j.entries(m.id).single().deviceSeq, "so the sequence did not advance")
        }
    }

    /** Two different commands claiming one id is corruption, not a retry, and is refused. */
    @Test fun aCommandIdOfferedForADifferentCommandIsRefused() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            j.append(visit(Seat.HOME, 60), m.id, commandId = "cmd-1")
            val e = assertFailsWith<JournalException.CommandIdReused> {
                j.append(visit(Seat.AWAY, 100), m.id, commandId = "cmd-1")
            }
            assertEquals("cmd-1", e.commandId)
            assertEquals(1, j.entries(m.id).size, "and nothing was written")
        }
    }

    /**
     * A replay is answered **before** the ending is checked. A retry of a visit that landed must
     * not be refused on the ground that the match has since been retired — the row is already
     * there, and telling the caller otherwise is the same lie the UNIQUE constraint used to tell.
     */
    @Test fun aReplayIsAnsweredEvenAfterTheMatchHasEnded() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            val landed = j.append(visit(Seat.HOME, 60), m.id, commandId = "cmd-1")
            j.end(m.id, Ending.Retired(Seat.AWAY))
            assertEquals(landed, j.append(visit(Seat.HOME, 60), m.id, commandId = "cmd-1"))
            // A genuinely new visit is still refused, which is the rule the replay must not weaken.
            assertFailsWith<JournalException.AlreadyEnded> { j.append(visit(Seat.AWAY, 60), m.id) }
        }
    }

    /** The other three writes answer a replay too: a retraction, an attestation and an ending. */
    @Test fun everyWriteAnswersAReplay() {
        open().use { j ->
            val m = threeVisits(j)
            val undo = j.retractLastVisit(m.id, commandId = "undo-1")
            assertEquals(undo, j.retractLastVisit(m.id, commandId = "undo-1"))

            val said = j.attest(m.id, Seat.HOME, agrees = true, commandId = "att-1")
            assertEquals(said, j.attest(m.id, Seat.HOME, agrees = true, commandId = "att-1"))

            val over = j.end(m.id, Ending.Abandoned, commandId = "end-1")
            assertEquals(over, j.end(m.id, Ending.Abandoned, commandId = "end-1"))
            // Not a licence to end twice: a SECOND ending, with its own id, is still refused.
            assertFailsWith<JournalException.AlreadyEnded> { j.end(m.id, Ending.Retired(Seat.HOME)) }

            assertEquals(6, j.entries(m.id).size, "three visits, an undo, an attestation, an ending")
        }
    }

    /**
     * The instant a write returns is the instant the journal holds.
     *
     * It was not. The returned entry carried the caller's nanoseconds while the stored row carried
     * milliseconds, so a replay handed back a row that differed from the one the first call
     * returned — by a value nothing in the app could see and every comparison could. Found by the
     * replay tests above and pinned here, because the property is worth naming.
     */
    @Test fun theInstantReturnedIsTheInstantStored() {
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"))
            val precise = Instant.parse("2026-09-07T14:30:05.250999999Z")
            val written = j.append(visit(Seat.HOME, 60), m.id, occurredAt = precise)
            assertEquals(j.entries(m.id).single(), written)
            assertEquals(Instant.parse("2026-09-07T14:30:05.250Z"), written.occurredAt)
        }
    }

    // MARK: the two platforms store the same words

    /**
     * **The stored vocabulary is the contract between the platforms.** A journal written on an
     * iPhone and read on a Pixel is the point of ADR-006; if one wrote `RETIREMENT` and the other
     * `retirement`, every ending would read back as a row the other build cannot interpret — which
     * the reader is careful to refuse, so the failure would be silent and total.
     *
     * `tools/check_journal_parity.py` holds the schema and the triggers against the Swift source on
     * every push. This holds the enum spellings, which live in Kotlin naming and must serialise to
     * the iOS ones.
     */
    @Test fun theStoredWordsAreTheOnesTheOtherPlatformWrites() {
        assertEquals(
            listOf("visit", "retraction", "confirmation", "contest", "retirement", "abandonment", "unknown"),
            JournalEntry.Kind.entries.map { it.stored },
        )
        assertEquals(listOf("home", "away"), Seat.entries.map { it.stored })
        assertEquals("home", Seat.HOME.playerId.value)
        open().use { j ->
            val m = j.createMatch(
                NewMatch("A", "B", inRule = InRule.DOUBLE, outRule = OutRule.MASTER, legsMode = StructureMode.FIRST_TO),
            )
            val row = raw1(
                "SELECT in_rule, out_rule, legs_mode, throw_first FROM local_match WHERE match_id = '${m.id.value}';",
            )
            assertEquals(listOf("double", "master", "firstTo", "home"), row)
        }
    }

    /** A timestamp round-trips through the format the iOS journal writes. */
    @Test fun timestampsAreWrittenInTheFormatTheOtherPlatformReads() {
        val when0 = Instant.parse("2026-09-07T14:30:05.250Z")
        assertEquals("2026-09-07T14:30:05.250Z", Journal.iso.format(when0))
        open().use { j ->
            val m = j.createMatch(NewMatch("A", "B"), startedAt = when0)
            assertEquals(when0, j.match(m.id).startedAt)
            val e = j.append(visit(Seat.HOME, 60), m.id, occurredAt = when0)
            assertEquals(when0, j.entries(m.id).single().occurredAt)
            assertEquals(when0, e.occurredAt)
        }
    }

    // MARK: raw access, for the tests that have to go behind the API

    /** Runs SQL on a second connection, so a trigger's abort is what fails rather than the API. */
    private fun raw(sql: String) {
        DriverManager.getConnection("jdbc:sqlite:$path").use { c ->
            try {
                c.createStatement().use { it.execute(sql) }
            } catch (e: Exception) {
                throw JournalException.Sqlite(e.message ?: sql)
            }
        }
    }

    private fun raw1(sql: String): List<String?> =
        DriverManager.getConnection("jdbc:sqlite:$path").use { c ->
            c.createStatement().use { s ->
                s.executeQuery(sql).use { r ->
                    assertTrue(r.next())
                    (1..r.metaData.columnCount).map { r.getString(it) }
                }
            }
        }

    @Test fun aMatchCarriesItsPlayersAndAnOlderOneReadsBackWithout() {
        open().use { j ->
            val named = j.createMatch(NewMatch("Ann", "Ben", homePlayerId = "p1", awayPlayerId = "p2"))
            assertEquals("p1", j.match(named.id).playerId(Seat.HOME))
            assertEquals("p2", j.match(named.id).playerId(Seat.AWAY))
            val anonymous = j.createMatch(NewMatch("Cara", "Dai"))
            assertNull(j.match(anonymous.id).playerId(Seat.HOME), "null is a real answer, never a guess")
            assertNotNull(j.match(anonymous.id).startedAt)
        }
    }
}
