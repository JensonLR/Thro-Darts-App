package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.engine.MatchFormat

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
 */
public class Uploads(private val connection: Connection, private val now: () -> Instant = { Instant.now() }) {

    /** One row of a device's journal, as the phone wrote it. */
    public data class Row(
        val deviceSeq: Long,
        /** `visit` or `retraction`. */
        val kind: String,
        /** The seat that threw: `home` or `away`. */
        val seat: String,
        /** The visit's total. Null on a retraction, which scores nothing. */
        val visitTotal: Int?,
        /** On a retraction, the `deviceSeq` of the visit it strikes. */
        val correctsSeq: Long?,
        val occurredAt: Instant,
        val occurredTz: String,
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
        for (row in rows) {
            if (row.deviceSeq <= previous) return Result.Refused("the rows are not in the order the device wrote them")
            previous = row.deviceSeq
            when (row.kind) {
                "visit" -> {
                    val total = row.visitTotal ?: return Result.Refused("a visit with no total is not a visit")
                    if (total < 0 || total > 180) return Result.Refused("no three darts score $total")
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
            }

            val correlation = UUID.randomUUID()
            val bySeq = HashMap<Long, UUID>()     // device_seq -> event id, for a retraction to point at
            var visits = 0; var retractions = 0; var already = 0
            for (row in rows) {
                val eventId = UUID.randomUUID()
                val corrects = row.correctsSeq?.let { bySeq[it] ?: eventIdOf(matchId, deviceId, it) }
                if (row.kind == "retraction" && corrects == null) {
                    connection.rollback()
                    return Result.Refused("a retraction strikes a visit THRØ does not hold")
                }
                val wrote = append(eventId, matchId, deviceId, row, uploaderPlayerId, correlation, corrects)
                if (wrote) {
                    if (row.kind == "visit") visits++ else retractions++
                } else {
                    already++
                }
                bySeq[row.deviceSeq] = eventIdOf(matchId, deviceId, row.deviceSeq) ?: eventId
            }
            connection.commit()
            return Result.Stored(matchId, opponentId, visits, retractions, already, opened)
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

    /** Appends one row. False when that place in the device's sequence is already filled — a resend. */
    private fun append(
        eventId: UUID, matchId: UUID, deviceId: UUID, row: Row,
        actor: UUID, correlation: UUID, corrects: UUID?,
    ): Boolean {
        val type = if (row.kind == "visit") "VisitRecorded" else "VisitRetracted"
        val payload = if (row.kind == "visit") {
            """{"player":"${row.seat}","visitTotal":${row.visitTotal},"dartsUsed":null,"dartsAtDouble":null,"effect":"uploaded"}"""
        } else {
            """{"player":"${row.seat}","retracts":${row.correctsSeq}}"""
        }
        return connection.prepareStatement(
            """
            INSERT INTO evidence.event
              (event_id, match_id, device_id, device_seq, event_type, schema_version,
               correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload,
               authority, corrects_event_id)
            VALUES (?, ?, ?, ?, ?, 1, ?, ?, 'participant', ?, ?, ?::jsonb, 'ungranted', ?)
            ON CONFLICT (match_id, device_id, device_seq) DO NOTHING
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, eventId); ps.setObject(2, matchId); ps.setObject(3, deviceId)
            ps.setLong(4, row.deviceSeq); ps.setString(5, type)
            ps.setObject(6, correlation); ps.setObject(7, actor)
            ps.setObject(8, java.sql.Timestamp.from(row.occurredAt)); ps.setString(9, row.occurredTz)
            ps.setString(10, payload); ps.setObject(11, corrects)
            ps.executeUpdate() == 1
        }
    }
}
