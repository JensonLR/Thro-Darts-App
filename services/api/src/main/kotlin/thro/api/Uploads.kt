package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.engine.Command
import thro.engine.Dart
import thro.engine.Darts
import thro.engine.Engine
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId
import thro.engine.VisitReading

/**
 * Sending a match to THRØ (PD-040).
 *
 * **The phone sends its journal, not a summary.** Every row the device wrote, in `deviceSeq` order,
 * visits and the retractions that struck them. A retraction becomes a `VisitRetracted` event whose
 * `corrects_event_id` names the visit it undid (V032), so the server holds the same account of the
 * night the board showed: a struck figure, still there, with the figure that replaced it after it.
 * Sending a replayed total instead would be the app deciding what happened and discarding the record
 * PD-004 exists to keep.
 *
 * **Idempotent and resumable by construction, not by cleverness.** `evidence.event` is unique on
 * `(match_id, device_id, device_seq)`. The same upload twice is the same rows; a phone that lost
 * signal half way sends the lot again and only the missing half lands. Nothing is last-write-wins
 * because nothing is written twice.
 *
 * **The opponent is a competitor with no name.** On a phone the other player is usually a local name
 * and nothing else — no account, no consent — so THRØ mints an unclaimed `competition.player` for
 * that seat and stores no name for them at all (PD-009, PD-014). They can claim it later by a code.
 *
 * **And it arrives self-reported.** PD-011 wants both players to confirm a result; an upload from
 * one phone is one player's word, recorded as exactly that and evidence of nothing more.
 *
 * **A match that ended short arrives as it ended (PD-016, V034).** The journal's retirement or
 * abandonment row becomes a `MatchEndedShort` event, last in the stream, and nothing is added after
 * it — so THRØ never holds a record saying a match is still going when the people in it stopped.
 *
 * **And it is played again before it is kept (OD-023).** Self-reported is one player's word about what
 * happened, not licence to store what cannot have happened. The journal is replayed through the engine
 * the phone ran — every visit still standing after its retractions, in order — and a visit the engine
 * refuses is refused here, in a sentence naming its row. What is stored is what the engine said: the
 * effect, and for a visit sent as darts, the total and dart counts it derived. A visit the scorer struck
 * need not stand, and is kept whatever the engine made of it, because the board showed it.
 */
public class Uploads(private val connection: Connection, private val now: () -> Instant = { Instant.now() }) {

    /** One row of a device's journal, as the phone wrote it. */
    public data class Row(
        val deviceSeq: Long,
        /** `visit`, `retraction`, or an ending: `retirement` (by [seat]) or `abandonment` (by nobody). */
        val kind: String,
        /** The seat that threw: `home` or `away`. */
        val seat: String,
        /**
         * The visit's total. Null on a retraction, which scores nothing, and may be null on a visit sent as
         * [darts], whose total the engine derives. When both are sent they must agree.
         */
        val visitTotal: Int?,
        /** On a retraction, the `deviceSeq` of the visit it strikes. */
        val correctsSeq: Long?,
        val occurredAt: Instant,
        val occurredTz: String,
        /** The darts of a visit, in order, when the phone recorded them (OD-023). The row is then a RecordDarts. */
        val darts: List<Dart>? = null,
    )

    public sealed interface Result {
        public data class Stored(
            val matchId: UUID,
            val opponentId: UUID,
            val visits: Int,
            val retractions: Int,
            /** Rows that were already here — a resumed upload, or the same one sent twice. */
            val alreadyHeld: Int,
            val opened: Boolean,
            /** How the match ended, when this call stored its ending: `retired` or `abandoned`. */
            val ending: String? = null,
        ) : Result

        public data class Refused(val why: String) : Result
    }

    /**
     * Receive a match. Either the whole journal applies or none of it does.
     *
     * [uploaderPlayerId] is the caller's own competitor; [seat] is which seat they sat in, so the
     * other one is the competitor THRØ mints. A second upload of the same match by the same device
     * adds whatever is missing and changes nothing that is there.
     */
    public fun receive(
        uploaderPlayerId: UUID,
        deviceId: UUID,
        matchId: UUID,
        seat: String,
        format: MatchFormat,
        rows: List<Row>,
    ): Result {
        if (seat != "home" && seat != "away") return Result.Refused("a seat is home or away, never a person")
        if (rows.isEmpty()) return Result.Refused("that match has nothing in it to send")
        if (rows.size > MAX_ROWS) return Result.Refused("that match has more rows than THRØ accepts in one go")

        // The journal is a sequence. Out of order, or two rows claiming one place in it, and this is
        // not a journal — it is a bag of events with a story attached.
        var previous = 0L
        var ended = false
        for (row in rows) {
            if (row.deviceSeq <= previous) return Result.Refused("the rows are not in the order the device wrote them")
            previous = row.deviceSeq
            // An ending is the last thing a device writes about a match — the journal refuses anything
            // after one — so a journal with a row after its ending is not a journal.
            if (ended) return Result.Refused("nothing comes after the end of a match")
            when (row.kind) {
                "visit" -> {
                    val darts = row.darts
                    if (darts == null) {
                        val total = row.visitTotal ?: return Result.Refused("a visit with no total is not a visit")
                        if (total < 0 || total > 180) return Result.Refused("no three darts score $total")
                    } else if (darts.isEmpty() || darts.size > Darts.HAND) {
                        return Result.Refused("a visit is one to three darts, and row ${row.deviceSeq} has ${darts.size}")
                    }
                    if (row.seat != "home" && row.seat != "away") return Result.Refused("a visit is thrown from a seat, home or away")
                }
                "retraction" -> {
                    val strikes = row.correctsSeq ?: return Result.Refused("a retraction has to say what it strikes")
                    // Backwards only. A retraction of something the device had not written yet is
                    // not a retraction, it is a claim about the future.
                    if (strikes >= row.deviceSeq) return Result.Refused("a retraction strikes something written before it")
                    if (rows.none { it.deviceSeq == strikes && it.kind == "visit" }) {
                        return Result.Refused("a retraction strikes a visit that is not in this match")
                    }
                }
                "retirement" -> {
                    if (row.seat != "home" && row.seat != "away") {
                        return Result.Refused("a retirement says which seat retired, home or away")
                    }
                    ended = true
                }
                "abandonment" -> ended = true
                else -> return Result.Refused("THRØ does not know how to store a ${row.kind}")
            }
        }

        val wasAutoCommit = connection.autoCommit
        connection.autoCommit = false
        try {
            val existing = Matches(connection).load(matchId)
            var opened = false
            val opponentId: UUID
            if (existing == null) {
                opponentId = mintOpponent(uploaderPlayerId)
                val home = if (seat == "home") uploaderPlayerId else opponentId
                val away = if (seat == "home") opponentId else uploaderPlayerId
                Matches(connection).open(matchId, home, away, format, selfReported = true)
                opened = true
            } else {
                // A second upload has to be the same match, sent by somebody who played in it.
                val mine = existing.idFor(seat)
                if (mine != uploaderPlayerId) {
                    return Result.Refused("that match is already here, and you are not in that seat of it").also {
                        connection.rollback()
                    }
                }
                opponentId = existing.idFor(if (seat == "home") "away" else "home")
                    ?: return Result.Refused("that match has no other seat").also { connection.rollback() }
                // A resend of a match that has ended is fine: every row is already here and lands as
                // nothing. A NEW row after the end is refused in words here, before the trigger that
                // would refuse it anyway (V034) turns it into a fault.
                if (hasEnded(matchId) && rows.any { eventIdOf(matchId, deviceId, it.deviceSeq) == null }) {
                    connection.rollback()
                    return Result.Refused("that match has ended, so nothing more can be added to it")
                }
            }

            // The journal as it will stand once this upload lands, played through the engine under the
            // match's own rules — the stored ones when it is already here, since those are what it was
            // opened under and what every other replay reads.
            val judged = when (val j = judge(existing?.format ?: format, matchId, deviceId, rows)) {
                is Judgement.Refused -> { connection.rollback(); return Result.Refused(j.why) }
                is Judgement.Stands -> j
            }

            val correlation = UUID.randomUUID()
            val bySeq = HashMap<Long, UUID>()     // device_seq -> event id, for a retraction to point at
            var visits = 0; var retractions = 0; var already = 0; var ending: String? = null
            for (row in rows) {
                val eventId = UUID.randomUUID()
                val corrects = row.correctsSeq?.let { bySeq[it] ?: eventIdOf(matchId, deviceId, it) }
                if (row.kind == "retraction" && corrects == null) {
                    connection.rollback()
                    return Result.Refused("a retraction strikes a visit THRØ does not hold")
                }
                val wrote = append(eventId, matchId, deviceId, row, uploaderPlayerId, correlation, corrects, judged.said[row.deviceSeq])
                if (wrote) {
                    when (row.kind) {
                        "visit" -> visits++
                        "retraction" -> retractions++
                        "retirement" -> ending = "retired"
                        else -> ending = "abandoned"
                    }
                } else {
                    already++
                }
                bySeq[row.deviceSeq] = eventIdOf(matchId, deviceId, row.deviceSeq) ?: eventId
            }
            connection.commit()
            return Result.Stored(matchId, opponentId, visits, retractions, already, opened, ending)
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = wasAutoCommit
        }
    }

    /** How many rows one call will take. A pub match is tens; this is a bound, not a target. */
    public companion object { public const val MAX_ROWS: Int = 2_000 }

    // --- the pieces ------------------------------------------------------------------------------

    /**
     * The other seat: a competitor with no name, no account and no claim. It is the honest record of
     * somebody THRØ has never met — and it is what the other player claims later if they want it.
     */
    private fun mintOpponent(by: UUID): UUID =
        // `competition.mint_competitor` (V032), not an INSERT: the match role owns the evidence
        // schema and nothing else, and giving it standing INSERT on `player` would let the thing
        // that writes visits invent people at any time. This invents exactly one, unclaimed.
        connection.prepareStatement("SELECT competition.mint_competitor(?)").use { ps ->
            ps.setObject(1, by)
            ps.executeQuery().use { rs -> check(rs.next()) { "mint_competitor returned nothing" }; rs.getObject(1) as UUID }
        }

    private fun eventIdOf(matchId: UUID, deviceId: UUID, seq: Long): UUID? =
        connection.prepareStatement(
            "SELECT event_id FROM evidence.event WHERE match_id = ? AND device_id = ? AND device_seq = ?",
        ).use { ps ->
            ps.setObject(1, matchId); ps.setObject(2, deviceId); ps.setLong(3, seq)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null }
        }

    /** Whether this match's stream already holds its ending (V034). */
    private fun hasEnded(matchId: UUID): Boolean =
        connection.prepareStatement("SELECT 1 FROM evidence.event WHERE match_id = ? AND event_type = 'MatchEndedShort'")
            .use { ps -> ps.setObject(1, matchId); ps.executeQuery().use { it.next() } }

    /** Appends one row. False when that place in the device's sequence is already filled — a resend. */
    private fun append(
        eventId: UUID, matchId: UUID, deviceId: UUID, row: Row,
        actor: UUID, correlation: UUID, corrects: UUID?, said: Said?,
    ): Boolean {
        val type = when (row.kind) {
            "visit" -> "VisitRecorded"
            "retraction" -> "VisitRetracted"
            else -> "MatchEndedShort"
        }
        val payload = when (row.kind) {
            // What the engine said, not "uploaded": the effect, and for a visit sent as darts what they
            // came to. A struck visit the engine refused keeps the refusal's reason beside it.
            "visit" -> {
                // Only a row whose place is already held goes unjudged, and the insert below would land it
                // as nothing; saying so here keeps a resend from being judged against what it claims.
                val s = said ?: return false
                Visits.payload(row.seat, s.command, s.reading, s.effect,
                               extra = s.refused?.let { "\"refused\":\"$it\"," } ?: "")
            }
            "retraction" -> """{"player":"${row.seat}","retracts":${row.correctsSeq}}"""
            // The seat that retired. The winner is the other one, and is not stored twice (V034).
            "retirement" -> """{"ending":"retired","seat":"${row.seat}"}"""
            else -> """{"ending":"abandoned"}"""
        }
        return connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload,
               authority, corrects_event_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'participant', ?, ?, ?::jsonb, 'ungranted', ?)
            ON CONFLICT (match_id, device_id, device_seq) DO NOTHING
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId); ps.setObject(2, matchId); ps.setObject(3, deviceId)
            ps.setLong(4, row.deviceSeq); ps.setString(5, type)
            ps.setInt(6, said?.let { Visits.schemaOf(it.command) } ?: Visits.TOTAL_SCHEMA)
            ps.setObject(7, correlation); ps.setObject(8, actor)
            ps.setObject(9, java.sql.Timestamp.from(row.occurredAt)); ps.setString(10, row.occurredTz)
            ps.setString(11, payload); ps.setObject(12, corrects)
            ps.executeUpdate() == 1
        }
    }

    // --- the replay ------------------------------------------------------------------------------

    /** What the engine said about one visit row: the command it was, and the effect it had. */
    private class Said(val command: Command, val effect: String, val reading: VisitReading?, val refused: String? = null)

    private sealed interface Judgement {
        class Stands(val said: Map<Long, Said>) : Judgement
        class Refused(val why: String) : Judgement
    }

    /** One row of the device's journal as it will stand: held already, or arriving now. */
    private class Entry(val seq: Long, val kind: String, val command: Command?, val strikes: Long?, val arriving: Boolean,
                        val sentTotal: Int? = null)

    private fun commandOf(row: Row): Command =
        row.darts?.let { Command.RecordDarts(PlayerId(row.seat), it) }
            ?: Command.RecordVisit(PlayerId(row.seat), row.visitTotal!!, null, null)

    /**
     * Plays the journal through the engine, as it will stand once [rows] land beside what this device has
     * already sent. A row already held wins its place, exactly as the insert's ON CONFLICT does, so a resend
     * is judged against what is here and not against what it claims.
     *
     * Two walks. The first is the night as the board showed it, row by row, a retraction putting the board
     * back to the visits still standing: that is the effect a visit had when it was thrown, and the one a
     * struck visit keeps. The second is the record — every visit not struck, in order — and it is the one
     * that has to hold: a standing visit arriving now that the engine refuses refuses the upload. One that
     * is already held and does not replay is left as it is (THRØ held uploads before it replayed them), and
     * counts for nothing, as every reader already treats it.
     */
    private fun judge(format: MatchFormat, matchId: UUID, deviceId: UUID, rows: List<Row>): Judgement {
        val journal = sortedMapOf<Long, Entry>()
        for (row in rows) {
            journal[row.deviceSeq] = when (row.kind) {
                "visit" -> Entry(row.deviceSeq, "visit", commandOf(row), null, arriving = true, sentTotal = row.visitTotal)
                "retraction" -> Entry(row.deviceSeq, "retraction", null, row.correctsSeq, arriving = true)
                else -> Entry(row.deviceSeq, "ending", null, null, arriving = true)
            }
        }
        connection.prepareStatement(
            "SELECT device_seq, event_type, payload::text FROM evidence.event WHERE match_id = ? AND device_id = ? ORDER BY device_seq",
        ).use { ps ->
            ps.setObject(1, matchId); ps.setObject(2, deviceId)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val seq = rs.getLong(1)
                    val payload = Json.parseObject(rs.getString(3))
                    journal[seq] = when (rs.getString(2)) {
                        "VisitRecorded" -> Entry(seq, "visit", Visits.commandOf(payload), null, arriving = false)
                        "VisitRetracted" -> Entry(seq, "retraction", null, (payload["retracts"] as? Number)?.toLong(), arriving = false)
                        else -> Entry(seq, "other", null, null, arriving = false)
                    }
                }
            }
        }
        val struck = journal.values.mapNotNull { it.strikes }.toSet()
        val said = HashMap<Long, Said>()
        fun start() = MatchState.start(format, Seat.home, Seat.away)
        fun replay(visits: List<Entry>): MatchState = visits.fold(start()) { st, v ->
            (Engine.apply(st, v.command!!) as? Outcome.Accepted)?.state ?: st
        }

        // The night as the board showed it.
        var state = start()
        val standing = mutableListOf<Entry>()
        for (e in journal.values) {
            when (e.kind) {
                "visit" -> {
                    val cmd = e.command ?: continue
                    when (val out = Engine.apply(state, cmd)) {
                        is Outcome.Accepted -> {
                            state = out.state; standing += e
                            if (e.arriving) {
                                contradicts(e, cmd, out.reading)?.let { return Judgement.Refused(it) }
                                said[e.seq] = Said(cmd, Visits.effectName(out.effect), out.reading)
                            }
                        }
                        is Outcome.Rejected ->
                            if (e.arriving) said[e.seq] = Said(cmd, "refused", null, refused = out.reason.name)
                    }
                }
                "retraction" -> {
                    standing.removeAll { it.seq == e.strikes }
                    state = replay(standing)
                }
            }
        }

        // The record, which has to hold.
        state = start()
        for (e in journal.values) {
            if (e.kind != "visit" || e.seq in struck) continue
            val cmd = e.command ?: continue
            when (val out = Engine.apply(state, cmd)) {
                is Outcome.Rejected -> if (e.arriving) {
                    return Judgement.Refused("the visit at row ${e.seq} cannot have happened: ${Visits.sentence(out.reason, cmd)}")
                }
                is Outcome.Accepted -> {
                    state = out.state
                    if (!e.arriving) continue
                    contradicts(e, cmd, out.reading)?.let { return Judgement.Refused(it) }
                    said[e.seq] = Said(cmd, Visits.effectName(out.effect), out.reading)
                }
            }
        }
        return Judgement.Stands(said)
    }

    /**
     * A row that sent both a total and its darts, where the two disagree. The phone's total is a claim about the
     * darts, and the engine has the darts: a disagreement is a journal that contradicts itself, and THRØ does not
     * pick one of its two accounts to believe.
     */
    private fun contradicts(e: Entry, cmd: Command, reading: VisitReading?): String? {
        if (cmd !is Command.RecordDarts || e.sentTotal == null) return null
        val derived = reading?.visitTotal ?: return null
        return if (derived == e.sentTotal) null
        else "the visit at row ${e.seq} says ${e.sentTotal}, but ${Visits.describe(cmd)} scores $derived"
    }
}
