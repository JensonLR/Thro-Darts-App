package thro.journal

import thro.engine.Effect
import thro.engine.Engine
import thro.engine.InRule
import thro.engine.MatchState
import thro.engine.OutRule
import thro.engine.Outcome
import thro.engine.StructureMode
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * ADR-006's on-device journal, for Android.
 *
 * **Why this exists.** Gate 5 has read "on-device journal built on iOS … Android not started" since
 * the journal shipped. This is the Android half, and it is the same journal rather than a second
 * one: the same schema, the same append-only triggers, the same per-device gapless sequence, the
 * same replay through the engine, the same refusal to interpret a row a later build wrote. ADR-002
 * argues the domain is one domain rendered on several platforms; a journal that agreed with the
 * iOS one only by convention would be the counter-example.
 *
 * **The durability rule is unchanged and non-negotiable**: the command is flushed to the journal
 * BEFORE it is applied and acknowledged. The engine — pure, in memory — says whether a command is
 * valid; if it is, this journal commits it; only then does a screen update. Rendering first and
 * persisting second loses a dart on any crash between, and the player notices when the scores
 * disagree with the board.
 *
 * **Two things this package does not prove, and says so rather than implying otherwise:**
 *
 *  1. **It is not Android's SQLite.** These tests run on `org.xerial:sqlite-jdbc`, a JVM build.
 *     Android ships its own SQLite behind `android.database.sqlite`, with its own defaults and its
 *     own version. What is proved here is the schema, the triggers, the replay and the API — the
 *     parts that are the domain. What is not proved is how a device's storage behaves.
 *  2. **No durability number is claimed.** ADR-006's P95 of 1.64 ms is an iPhone measurement of an
 *     Apple barrier that Android has no equivalent for. `DurabilityConfiguration` explains what is
 *     asked for and what can honestly be verified; the equivalent measurement on a real Android
 *     device is outstanding.
 *
 * This module reaches the engine and SQLite and nothing else. LATENCY_BUDGETS.md makes the
 * network-independence of scoring a structural requirement, and the module graph is where it is
 * enforced: there is no network module here for this to depend on.
 */
public class Journal private constructor(
    private val connection: Connection,
    public val configuration: DurabilityConfiguration,
    deviceId: DeviceId,
    superseded: DeviceId?,
) : AutoCloseable {

    /**
     * The identity every row in this journal is written under.
     *
     * It belongs to the journal, not to the caller. The first open writes the identity it was
     * given; every open after that reads back the one already there and uses it, whatever it was
     * passed. A caller's copy can be lost while the file survives — a restore that brings back the
     * data directory but not the preferences, say — and a new identity would restart `device_seq`
     * at 1 for a match that already had rows. ADR-006's gapless per-device sequence is what a server
     * uses to notice a device is missing events; one device would arrive as two, each with its own
     * sequence and neither with a gap to report.
     */
    public val deviceId: DeviceId = deviceId

    /**
     * The identity the caller asked for, when the journal already had a different one. Nothing is
     * rewritten and nothing is refused — the rows are still this device's rows — but the
     * disagreement is a fact about this install and is not swallowed.
     */
    public val deviceIdSupersededCallers: DeviceId? = superseded

    override fun close() {
        connection.close()
    }

    public companion object {
        /** Opens (creating if needed) the journal at [path] and verifies the configuration. */
        public fun open(
            path: String,
            deviceId: DeviceId,
            configuration: DurabilityConfiguration = DurabilityConfiguration.candidate,
        ): Journal {
            val connection = try {
                DriverManager.getConnection("jdbc:sqlite:$path")
            } catch (e: Exception) {
                throw JournalException.Sqlite("could not open $path: ${e.message}")
            }
            try {
                connection.autoCommit = true
                configure(connection, configuration)
                migrate(connection)
                val settled = settleDeviceId(connection, deviceId)
                return Journal(connection, configuration, settled.first, settled.second)
            } catch (e: Throwable) {
                // Anything that throws during setup leaves no Journal to close the handle, so it is
                // closed here. Not in a `finally`: the success path must keep it open.
                runCatching { connection.close() }
                throw e
            }
        }

        // MARK: configuration

        internal fun configure(c: Connection, config: DurabilityConfiguration) {
            exec(c, "PRAGMA journal_mode = ${config.journalMode};")
            exec(c, "PRAGMA synchronous = ${config.synchronous};")
            exec(c, "PRAGMA foreign_keys = ON;")
            verifyInForce(c, config)
        }

        /**
         * Reads back what the database actually reports. `PRAGMA journal_mode = WAL` returns the
         * mode in force rather than failing, so a configuration that is not read back is a
         * configuration that is assumed.
         */
        internal fun verifyInForce(c: Connection, config: DurabilityConfiguration) {
            // PRAGMA synchronous reads back as a number: OFF 0, NORMAL 1, FULL 2, EXTRA 3.
            val synchronous = mapOf("OFF" to "0", "NORMAL" to "1", "FULL" to "2", "EXTRA" to "3")
            val expected = listOf(
                "journal_mode" to config.journalMode.lowercase(),
                "synchronous" to (synchronous[config.synchronous.uppercase()] ?: config.synchronous),
            )
            for ((name, want) in expected) {
                val got = pragmaValue(c, name)?.lowercase() ?: "(no value)"
                if (got != want) {
                    throw JournalException.ConfigurationNotInForce(name, want, got)
                }
            }
        }

        internal fun pragmaValue(c: Connection, name: String): String? =
            c.createStatement().use { s ->
                s.executeQuery("PRAGMA $name;").use { r -> if (r.next()) r.getString(1) else null }
            }

        internal fun exec(c: Connection, sql: String) {
            try {
                c.createStatement().use { it.execute(sql) }
            } catch (e: Exception) {
                throw JournalException.Sqlite(e.message ?: sql)
            }
        }

        // MARK: schema

        internal fun migrate(c: Connection) {
            exec(
                c,
                """
                CREATE TABLE IF NOT EXISTS local_match (
                  match_id       TEXT PRIMARY KEY,
                  home_name      TEXT NOT NULL,
                  away_name      TEXT NOT NULL,
                  starting_score INTEGER NOT NULL,
                  out_rule       TEXT NOT NULL,
                  legs_mode      TEXT NOT NULL,
                  legs_target    INTEGER NOT NULL,
                  throw_first    TEXT NOT NULL,
                  started_at     TEXT NOT NULL,
                  device_id      TEXT NOT NULL,
                  in_rule        TEXT NOT NULL DEFAULT 'straight',
                  home_player_id TEXT,
                  away_player_id TEXT,
                  archived_at    TEXT
                );
                """.trimIndent(),
            )
            // The journal's own facts about itself. Small on purpose: the only thing in it is the
            // identity every row is written under, which must not live anywhere the file can
            // outlive — plus the transient purge key `deleteMatch` sets inside its transaction.
            exec(
                c,
                """
                CREATE TABLE IF NOT EXISTS meta (
                  key   TEXT PRIMARY KEY,
                  value TEXT NOT NULL
                );
                """.trimIndent(),
            )
            exec(
                c,
                """
                CREATE TABLE IF NOT EXISTS journal (
                  match_id        TEXT NOT NULL REFERENCES local_match(match_id),
                  device_id       TEXT NOT NULL,
                  device_seq      INTEGER NOT NULL,
                  command_id      TEXT NOT NULL UNIQUE,
                  kind            TEXT NOT NULL DEFAULT 'visit',
                  seat            TEXT NOT NULL,
                  visit_total     INTEGER NOT NULL,
                  darts_used      INTEGER,
                  darts_at_double INTEGER,
                  corrects_seq    INTEGER,
                  occurred_at     TEXT NOT NULL,
                  PRIMARY KEY (match_id, device_id, device_seq)
                );
                """.trimIndent(),
            )
            // Append-only, enforced by the database rather than by discipline.
            //
            // **Nothing may ever edit a row.** That is the whole of the journal's trustworthiness
            // and it is unconditional: a visit that was recorded stays exactly as it was recorded,
            // and a correction is a new row that supersedes it (PD-004).
            exec(
                c,
                """
                CREATE TRIGGER IF NOT EXISTS journal_append_only_update BEFORE UPDATE ON journal
                BEGIN SELECT RAISE(ABORT, 'journal is append-only'); END;
                """.trimIndent(),
            )
            // **Deleting is narrower than it looks (PD-026).** It refuses every DELETE except the
            // rows of the one match a purge is currently naming, which only `deleteMatch` sets and
            // only inside its own transaction. With no `purging` row the subquery is NULL and
            // `IS NOT NULL` is true, so every delete raises exactly as it did before.
            exec(c, "DROP TRIGGER IF EXISTS journal_append_only_delete;")
            exec(
                c,
                """
                CREATE TRIGGER journal_append_only_delete BEFORE DELETE ON journal
                WHEN OLD.match_id IS NOT (SELECT value FROM meta WHERE key = 'purging')
                BEGIN SELECT RAISE(ABORT, 'journal is append-only'); END;
                """.trimIndent(),
            )
        }

        internal fun settleDeviceId(c: Connection, asked: DeviceId): Pair<DeviceId, DeviceId?> {
            val existing = c.prepareStatement("SELECT value FROM meta WHERE key = 'device_id';").use { s ->
                s.executeQuery().use { r -> if (r.next()) r.getString(1) else null }
            }
            if (existing == null) {
                c.prepareStatement("INSERT INTO meta (key, value) VALUES ('device_id', ?);").use { s ->
                    s.setString(1, asked.value)
                    s.executeUpdate()
                }
                return asked to null
            }
            return DeviceId(existing) to (if (existing == asked.value) null else asked)
        }

        // MARK: reading rows

        /**
         * The same instant format `ThroJournal` writes: ISO-8601 with fractional seconds and a Z,
         * so a row written by one platform reads back on the other.
         */
        internal val iso: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(java.time.ZoneOffset.UTC)

        internal fun instant(text: String): Instant =
            runCatching { Instant.parse(text) }.getOrElse { Instant.EPOCH }

        internal fun optionalInt(r: ResultSet, column: Int): Int? {
            val v = r.getInt(column)
            return if (r.wasNull()) null else v
        }

        internal fun optionalLong(r: ResultSet, column: Int): Long? {
            val v = r.getLong(column)
            return if (r.wasNull()) null else v
        }

        // MARK: pure readings of a row set, shared with iOS line for line

        /** How this match ended short, if it did. */
        public fun ending(entries: List<JournalEntry>): Ending? {
            // The earliest ending wins. `end` refuses a second one, so there is normally only ever
            // one; reading the earliest rather than the latest means a file that somehow carries
            // two still answers with the ending that actually stopped play.
            val row = entries.filter { it.kind.endsTheMatch }.minByOrNull { it.deviceSeq } ?: return null
            return if (row.kind == JournalEntry.Kind.RETIREMENT) Ending.Retired(row.seat) else Ending.Abandoned
        }

        /**
         * Reads the attestations for a match and works out whether they still apply.
         *
         * Staleness is decided by `device_seq` alone: it is monotonic per device, so on the one
         * phone that scored this match it is a total order, and "a scoring row came after the last
         * attestation" is exactly "somebody changed the result after agreeing it".
         */
        public fun standing(entries: List<JournalEntry>): Standing {
            val attestations = entries.filter {
                it.kind == JournalEntry.Kind.CONFIRMATION || it.kind == JournalEntry.Kind.CONTEST
            }
            val lastAttestation = attestations.maxOfOrNull { it.deviceSeq }
                ?: return Standing(emptySet(), emptySet(), stale = false)
            // Anything that changes what the result IS — a visit, a retraction, or an ending —
            // overtakes an agreement. Retiring after both players confirmed a scoreline hands the
            // match to somebody neither of them agreed had won it.
            val changedAfter = entries.any { it.kind.changesTheResult && it.deviceSeq > lastAttestation }
            // The last word each player said. Somebody who contests and then agrees has agreed.
            val latest = mutableMapOf<Seat, JournalEntry>()
            for (a in attestations.sortedBy { it.deviceSeq }) latest[a.seat] = a
            return Standing(
                confirmed = latest.filterValues { it.kind == JournalEntry.Kind.CONFIRMATION }.keys.toSet(),
                contested = latest.filterValues { it.kind == JournalEntry.Kind.CONTEST }.keys.toSet(),
                stale = changedAfter,
            )
        }

        /** The visits that stand: rows of kind `visit` that no retraction supersedes, in order. */
        public fun standingVisits(entries: List<JournalEntry>): List<JournalEntry> {
            // Only a retraction supersedes; an attestation's corrects_seq is null, and a row of a
            // kind this build cannot read is not allowed to strike a visit it cannot be shown to
            // refer to.
            val superseded = entries
                .filter { it.kind == JournalEntry.Kind.RETRACTION }
                .mapNotNull { it.correctsSeq }
                .toSet()
            return entries.filter { it.kind.isScoring && it.deviceSeq !in superseded }
        }
    }

    /** What the database reports for each configured pragma, right now. */
    public val configurationInForce: Map<String, String>
        get() = listOf("journal_mode", "synchronous").associateWith {
            pragmaValue(connection, it) ?: "(no value)"
        }

    // MARK: - matches

    public fun createMatch(
        m: NewMatch,
        id: MatchId = MatchId(UUID.randomUUID().toString()),
        startedAt: Instant = Instant.now(),
    ): MatchRecord {
        connection.prepareStatement(
            """
            INSERT INTO local_match (match_id, home_name, away_name, starting_score, out_rule, legs_mode,
                                     legs_target, throw_first, started_at, device_id, in_rule,
                                     home_player_id, away_player_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """.trimIndent(),
        ).use { s ->
            s.setString(1, id.value)
            s.setString(2, m.homeName)
            s.setString(3, m.awayName)
            s.setInt(4, m.startingScore)
            s.setString(5, m.outRule.name.lowercase())
            s.setString(6, if (m.legsMode == StructureMode.BEST_OF) "bestOf" else "firstTo")
            s.setInt(7, m.legsTarget)
            s.setString(8, m.throwFirst.stored)
            s.setString(9, iso.format(startedAt))
            s.setString(10, deviceId.value)
            s.setString(11, m.inRule.name.lowercase())
            s.setString(12, m.homePlayerId)
            s.setString(13, m.awayPlayerId)
            s.executeUpdate()
        }
        return match(id)
    }

    public fun match(id: MatchId): MatchRecord {
        connection.prepareStatement("SELECT $MATCH_COLUMNS FROM local_match WHERE match_id = ?;").use { s ->
            s.setString(1, id.value)
            s.executeQuery().use { r -> if (r.next()) return record(r) }
        }
        throw JournalException.MatchNotFound(id.value)
    }

    /**
     * Every match on this device, newest first.
     *
     * [archived] null means all of them — which is what a history and an export want, and why
     * archiving is safe: putting a match away never changes a figure. False is Home's list, true is
     * the shelf (PD-026).
     */
    public fun matches(archived: Boolean? = null): List<MatchRecord> {
        val filter = when (archived) {
            null -> ""
            true -> "WHERE archived_at IS NOT NULL "
            false -> "WHERE archived_at IS NULL "
        }
        val out = mutableListOf<MatchRecord>()
        connection.prepareStatement(
            "SELECT $MATCH_COLUMNS FROM local_match ${filter}ORDER BY started_at DESC, rowid DESC;",
        ).use { s ->
            s.executeQuery().use { r -> while (r.next()) out.add(record(r)) }
        }
        return out
    }

    /**
     * Puts a match away, or brings it back (PD-026). Reversible on purpose: nothing leaves the
     * journal, the export still carries it, and every figure still counts it — because it happened.
     */
    public fun setArchived(id: MatchId, archived: Boolean, at: Instant = Instant.now()) {
        val changed = connection.prepareStatement(
            "UPDATE local_match SET archived_at = ? WHERE match_id = ?;",
        ).use { s ->
            if (archived) s.setString(1, iso.format(at)) else s.setNull(1, java.sql.Types.VARCHAR)
            s.setString(2, id.value)
            s.executeUpdate()
        }
        if (changed == 0) throw JournalException.MatchNotFound(id.value)
    }

    /**
     * Removes a match and every visit in it, permanently (PD-026).
     *
     * **This is the only delete in the system and it is not a correction.** A correction is a new
     * row that supersedes an old one, and the journal will still never let anything edit a visit.
     * This is a person taking a whole match off their own device.
     *
     * @return how many journal rows went with it, so a caller can say what was actually lost.
     */
    public fun deleteMatch(id: MatchId): Int {
        exec(connection, "BEGIN IMMEDIATE;")
        try {
            val rows = connection.prepareStatement(
                "SELECT COUNT(*) FROM journal WHERE match_id = ?;",
            ).use { s ->
                s.setString(1, id.value)
                s.executeQuery().use { r -> if (r.next()) r.getInt(1) else 0 }
            }
            // The one key that opens the delete trigger, set and cleared inside this transaction —
            // so a crash mid-purge rolls the key back with the rows, and nothing can find the
            // journal unlocked afterwards.
            connection.prepareStatement(
                "INSERT OR REPLACE INTO meta (key, value) VALUES ('purging', ?);",
            ).use { s -> s.setString(1, id.value); s.executeUpdate() }
            connection.prepareStatement("DELETE FROM journal WHERE match_id = ?;").use { s ->
                s.setString(1, id.value)
                s.executeUpdate()
            }
            exec(connection, "DELETE FROM meta WHERE key = 'purging';")
            val removed = connection.prepareStatement("DELETE FROM local_match WHERE match_id = ?;").use { s ->
                s.setString(1, id.value)
                s.executeUpdate()
            }
            exec(connection, "COMMIT;")
            if (removed == 0) throw JournalException.MatchNotFound(id.value)
            return rows
        } catch (e: Throwable) {
            runCatching { exec(connection, "ROLLBACK;") }
            throw e
        }
    }

    // MARK: - the journal

    /**
     * Appends one command the engine has already accepted. Returns only after the transaction has
     * committed — that is the durability rule, and it is why a screen must not update until this
     * returns.
     */
    public fun append(
        command: thro.engine.Command,
        matchId: MatchId,
        occurredAt: Instant = Instant.now(),
        commandId: String = UUID.randomUUID().toString(),
    ): JournalEntry {
        val visit = command as? thro.engine.Command.RecordVisit
            ?: throw JournalException.Sqlite("unsupported command")
        val seat = Seat.of(visit.player)
            ?: throw JournalException.Sqlite("player ${visit.player.value} is not a seat in a local match")

        exec(connection, "BEGIN IMMEDIATE;")
        try {
            // A retired or abandoned match takes no more darts (PD-016). Inside the transaction, so
            // the check and the insert cannot be separated by another writer.
            ending(entriesUnlocked(matchId))?.let { throw JournalException.AlreadyEnded(it) }
            val next = nextSeq(matchId)
            connection.prepareStatement(
                """
                INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total,
                                     darts_used, darts_at_double, occurred_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """.trimIndent(),
            ).use { s ->
                s.setString(1, matchId.value)
                s.setString(2, deviceId.value)
                s.setLong(3, next)
                s.setString(4, commandId)
                s.setString(5, seat.stored)
                s.setInt(6, visit.visitTotal)
                if (visit.dartsUsed != null) s.setInt(7, visit.dartsUsed!!) else s.setNull(7, java.sql.Types.INTEGER)
                if (visit.dartsAtDouble != null) {
                    s.setInt(8, visit.dartsAtDouble!!)
                } else {
                    s.setNull(8, java.sql.Types.INTEGER)
                }
                s.setString(9, iso.format(occurredAt))
                s.executeUpdate()
            }
            // COMMIT is where the barrier happens.
            exec(connection, "COMMIT;")
            return JournalEntry(
                matchId, deviceId, next, commandId, JournalEntry.Kind.VISIT, seat,
                visit.visitTotal, visit.dartsUsed, visit.dartsAtDouble, null, occurredAt,
            )
        } catch (e: Throwable) {
            runCatching { exec(connection, "ROLLBACK;") }
            throw e
        }
    }

    /**
     * Strikes the most recent standing visit by appending a retraction that supersedes it. Nothing
     * is deleted: the struck row stays, replay skips it, and the statistics never see it (PD-004).
     */
    public fun retractLastVisit(
        matchId: MatchId,
        occurredAt: Instant = Instant.now(),
        commandId: String = UUID.randomUUID().toString(),
    ): JournalEntry {
        exec(connection, "BEGIN IMMEDIATE;")
        try {
            val all = entriesUnlocked(matchId)
            // An ended match is closed to corrections too (PD-016). Undoing the last visit of a
            // retired match would change the scoreline behind a result already given to somebody.
            ending(all)?.let { throw JournalException.AlreadyEnded(it) }
            val target = standingVisits(all).lastOrNull() ?: throw JournalException.NothingToRetract()
            val next = nextSeq(matchId)
            insertNonScoring(
                matchId, next, commandId, JournalEntry.Kind.RETRACTION, target.seat,
                target.deviceSeq, occurredAt,
            )
            exec(connection, "COMMIT;")
            return JournalEntry(
                matchId, deviceId, next, commandId, JournalEntry.Kind.RETRACTION, target.seat,
                0, null, null, target.deviceSeq, occurredAt,
            )
        } catch (e: Throwable) {
            runCatching { exec(connection, "ROLLBACK;") }
            throw e
        }
    }

    /**
     * Records that a player agrees, or does not agree, with the result as it currently stands
     * (PD-011).
     *
     * **This is an assertion by a person, not corroboration by a second device.** Two people at one
     * phone is the weakest form of the trust model's `participant-confirmed`, and every screen that
     * shows it says so. Written as an ordinary append, so it is durable on the same terms as a
     * visit and cannot be edited afterwards.
     */
    public fun attest(
        matchId: MatchId,
        seat: Seat,
        agrees: Boolean,
        occurredAt: Instant = Instant.now(),
        commandId: String = UUID.randomUUID().toString(),
    ): JournalEntry {
        val kind = if (agrees) JournalEntry.Kind.CONFIRMATION else JournalEntry.Kind.CONTEST
        exec(connection, "BEGIN IMMEDIATE;")
        try {
            val next = nextSeq(matchId)
            insertNonScoring(matchId, next, commandId, kind, seat, null, occurredAt)
            exec(connection, "COMMIT;")
            return JournalEntry(matchId, deviceId, next, commandId, kind, seat, 0, null, null, null, occurredAt)
        } catch (e: Throwable) {
            runCatching { exec(connection, "ROLLBACK;") }
            throw e
        }
    }

    /**
     * Closes a match that will not be played out (PD-016).
     *
     * **An ending is final.** Nothing here retracts it, and `append` refuses a visit afterwards.
     * That is a deliberate departure from PD-004, which makes a mis-keyed *visit* undoable: a visit
     * is a transcription and an ending is a declaration, taken behind a confirmation on the screen.
     * If an ending could be undone the match could un-end, and "the result" would be a claim that
     * moves — precisely what the attestation in PD-011 exists to pin down.
     */
    public fun end(
        matchId: MatchId,
        ending: Ending,
        occurredAt: Instant = Instant.now(),
        commandId: String = UUID.randomUUID().toString(),
    ): JournalEntry {
        exec(connection, "BEGIN IMMEDIATE;")
        try {
            ending(entriesUnlocked(matchId))?.let { throw JournalException.AlreadyEnded(it) }
            val next = nextSeq(matchId)
            // An abandonment has no seat, and the column will not take a null. HOME is written as a
            // placeholder and is NEVER read back for an abandonment — `ending` branches on the kind
            // before it looks at the seat. A test proves the placeholder is inert by storing the
            // other one and reading the same answer, which is stronger than this comment.
            val seat = (ending as? Ending.Retired)?.by ?: Seat.HOME
            insertNonScoring(matchId, next, commandId, ending.kind, seat, null, occurredAt)
            exec(connection, "COMMIT;")
            return JournalEntry(
                matchId, deviceId, next, commandId, ending.kind, seat, 0, null, null, null, occurredAt,
            )
        } catch (e: Throwable) {
            runCatching { exec(connection, "ROLLBACK;") }
            throw e
        }
    }

    /** How this match ended short, if it did. Null means it is still open or was played out. */
    public fun ending(matchId: MatchId): Ending? = ending(entries(matchId))

    /** Who stands behind the result as it is recorded right now. */
    public fun standing(matchId: MatchId): Standing = standing(entries(matchId))

    /** Every committed row for a match, in the order committed on this device. */
    public fun entries(matchId: MatchId): List<JournalEntry> = entriesUnlocked(matchId)

    private fun entriesUnlocked(matchId: MatchId): List<JournalEntry> {
        val out = mutableListOf<JournalEntry>()
        connection.prepareStatement(
            """
            SELECT match_id, device_id, device_seq, command_id, seat, visit_total, darts_used,
                   darts_at_double, occurred_at, kind, corrects_seq
            FROM journal WHERE match_id = ? ORDER BY rowid;
            """.trimIndent(),
        ).use { s ->
            s.setString(1, matchId.value)
            s.executeQuery().use { r ->
                while (r.next()) {
                    out.add(
                        JournalEntry(
                            matchId = MatchId(r.getString(1)),
                            deviceId = DeviceId(r.getString(2)),
                            deviceSeq = r.getLong(3),
                            commandId = r.getString(4),
                            // NOT a fallback to a visit. A kind this build does not know is a row it
                            // cannot interpret, and interpreting it as a visit would put a score in
                            // the match that nobody threw.
                            kind = JournalEntry.Kind.of(r.getString(10)),
                            seat = Seat.of(r.getString(5)) ?: Seat.HOME,
                            visitTotal = r.getInt(6),
                            dartsUsed = optionalInt(r, 7),
                            dartsAtDouble = optionalInt(r, 8),
                            correctsSeq = optionalLong(r, 11),
                            occurredAt = instant(r.getString(9)),
                        ),
                    )
                }
            }
        }
        return out
    }

    /**
     * Folds the journal through the engine and returns the state it rebuilds, with each visit as
     * the engine saw it. A rejection during replay is corruption and is thrown, never skipped.
     */
    public fun replayVisits(id: MatchId): Pair<MatchState, List<ReplayedVisit>> {
        val record = match(id)
        var state = record.initialState
        val visits = mutableListOf<ReplayedVisit>()
        val ordinal = mutableMapOf<Pair<Seat, Int>, Int>()

        val all = entries(id)
        // A row this build cannot interpret might have been a visit. Replaying around it would
        // produce a state that looks right and is not, so the journal says so instead.
        all.firstOrNull { it.kind == JournalEntry.Kind.UNKNOWN }?.let {
            throw JournalException.ReplayRejected(it.deviceSeq, "UNKNOWN_ROW_KIND")
        }
        for (e in standingVisits(all)) {
            val command = e.command ?: continue
            val leg = state.currentLeg
            val before = state.remaining[e.seat.playerId] ?: 0
            when (val outcome = Engine.apply(state, command)) {
                is Outcome.Accepted -> {
                    val n = (ordinal[e.seat to leg] ?: 0) + 1
                    ordinal[e.seat to leg] = n
                    val bust = outcome.effect == Effect.BUST
                    val wonLeg = outcome.effect == Effect.LEG_WON ||
                        outcome.effect == Effect.SET_WON ||
                        outcome.effect == Effect.MATCH_WON
                    visits.add(
                        ReplayedVisit(
                            seat = e.seat,
                            legOrdinal = leg,
                            visitOrdinal = n,
                            visitTotal = e.visitTotal,
                            dartsUsed = e.dartsUsed,
                            dartsAtDouble = e.dartsAtDouble,
                            remainingBefore = before,
                            remainingAfter = outcome.state.remaining[e.seat.playerId] ?: 0,
                            bust = bust,
                            wonLeg = wonLeg,
                        ),
                    )
                    state = outcome.state
                }
                is Outcome.Rejected -> throw JournalException.ReplayRejected(e.deviceSeq, outcome.reason.name)
            }
        }
        return state to visits
    }

    public fun replay(id: MatchId): MatchState = replayVisits(id).first

    // MARK: - helpers

    private fun nextSeq(matchId: MatchId): Long =
        connection.prepareStatement(
            "SELECT COALESCE(MAX(device_seq), 0) + 1 FROM journal WHERE match_id = ? AND device_id = ?;",
        ).use { s ->
            s.setString(1, matchId.value)
            s.setString(2, deviceId.value)
            s.executeQuery().use { r -> if (r.next()) r.getLong(1) else 1L }
        }

    private fun insertNonScoring(
        matchId: MatchId,
        seq: Long,
        commandId: String,
        kind: JournalEntry.Kind,
        seat: Seat,
        correctsSeq: Long?,
        occurredAt: Instant,
    ) {
        connection.prepareStatement(
            """
            INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, visit_total,
                                 darts_used, darts_at_double, corrects_seq, occurred_at)
            VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?, ?);
            """.trimIndent(),
        ).use { s ->
            s.setString(1, matchId.value)
            s.setString(2, deviceId.value)
            s.setLong(3, seq)
            s.setString(4, commandId)
            s.setString(5, kind.stored)
            s.setString(6, seat.stored)
            if (correctsSeq != null) s.setLong(7, correctsSeq) else s.setNull(7, java.sql.Types.INTEGER)
            s.setString(8, iso.format(occurredAt))
            s.executeUpdate()
        }
    }

    private fun record(r: ResultSet): MatchRecord = MatchRecord(
        id = MatchId(r.getString(1)),
        homeName = r.getString(2),
        awayName = r.getString(3),
        startingScore = r.getInt(4),
        inRule = InRule.entries.firstOrNull { it.name.lowercase() == r.getString(10) } ?: InRule.STRAIGHT,
        outRule = OutRule.entries.firstOrNull { it.name.lowercase() == r.getString(5) } ?: OutRule.DOUBLE,
        legsMode = if (r.getString(6) == "firstTo") StructureMode.FIRST_TO else StructureMode.BEST_OF,
        legsTarget = r.getInt(7),
        throwFirst = Seat.of(r.getString(8)) ?: Seat.HOME,
        startedAt = instant(r.getString(9)),
        homePlayerId = r.getString(11),
        awayPlayerId = r.getString(12),
        archivedAt = r.getString(13)?.let { instant(it) },
    )
}

/**
 * Named, in this order, so a column added by ALTER cannot silently shift the ones below it.
 * `SELECT *` was doing exactly that on iOS, and adding `in_rule` for double-in is the change that
 * would have found it.
 */
private const val MATCH_COLUMNS =
    "match_id, home_name, away_name, starting_score, out_rule, legs_mode, legs_target, " +
        "throw_first, started_at, in_rule, home_player_id, away_player_id, archived_at"
