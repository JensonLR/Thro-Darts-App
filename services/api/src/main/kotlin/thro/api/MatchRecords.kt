package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID
import thro.engine.Command
import thro.engine.Engine
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.Outcome
import thro.engine.PlayerId

/**
 * A match on THRØ once it has been sent (PD-043): the code the sender makes for the other seat, the
 * claim the other player makes with it, the answer they give for the result, and what either of them
 * reads back.
 *
 * **Nothing here rewrites evidence.** A claim is a row in `competition.seat_claim`; an answer is an event
 * appended to the trust stream; a match's legs, winner and standing are read from the log every time and
 * stored nowhere, so none of them can drift from it. The only thing a code changes is itself: it is used,
 * once.
 */
public class MatchRecords(private val connection: Connection, private val now: () -> Instant = { Instant.now() }) {

    /** A refusal a person is shown as it stands, and the status that goes with it. */
    public class Refused(public val why: String, public val status: Int = 422) : Exception(why)

    public data class Code(val code: String, val seat: String, val expiresAt: Instant)

    public data class SeatLine(
        val seat: String,
        /** The seat the reader sits in. */
        val you: Boolean,
        /** The person's name, where THRØ may show it (V016) and they have given one. */
        val name: String?,
        /** Nobody holds this seat yet: the sender can make a code for it. */
        val claimable: Boolean,
    )

    public data class Summary(
        val matchId: UUID,
        val openedAt: Instant,
        val format: MatchFormat,
        val selfReported: Boolean,
        val seats: List<SeatLine>,
        val legs: Map<String, Int>,
        val visits: Int,
        /** `retired` or `abandoned` when the match ended short (V034); null otherwise. */
        val ending: String?,
        /** The seat that retired, when one did. */
        val retired: String?,
        /** The seat that won, when one did: the engine's answer, or the other seat of a retirement. */
        val winner: String?,
        /**
         * The seat whose player sent the match — the one whose word it is, who may give a code for the
         * other seat and may not answer for it. Null for a match scored on THRØ as it was played.
         */
        val sentBy: String?,
        /** Each seat's latest answer for the result: `confirmed`, `contested`, or null. */
        val answers: Map<String, String?>,
        /** `self-reported`, `confirmed`, `disputed`, or `recorded` for a match scored on THRØ as it went. */
        val standing: String,
    )

    public companion object {
        public val CODE_TTL: Duration = Duration.ofDays(7)
        private val SEATS = listOf(Seat.HOME, Seat.AWAY)
        private val RECORD = setOf("VisitRecorded", "VisitRetracted", "MatchEndedShort")
        private fun other(seat: String) = if (seat == Seat.HOME) Seat.AWAY else Seat.HOME

        /** Case, spaces and dashes are not part of a code. */
        public fun normalise(raw: String): String = raw.uppercase().filter { !it.isWhitespace() && it != '-' }

        /**
         * The device an answer is written under: stable for a phone, and never the phone's own journal
         * device. A phone that answered for a match and later sent more of that match's journal would
         * otherwise have its answer and its next visit claim one place in the device sequence — and the
         * visit, resent, would land as nothing.
         */
        public fun answerDevice(phone: UUID): UUID = UUID.nameUUIDFromBytes("thro-answer:$phone".toByteArray())
    }

    // --- whose seat ---------------------------------------------------------------------------------

    /** The seat [player] sits in — directly, or by a seat they claimed (V037) — or null. */
    public fun seatOf(matchId: UUID, player: UUID): String? =
        connection.prepareStatement("SELECT competition.seat_of(?, ?)").use { ps ->
            ps.setObject(1, matchId); ps.setObject(2, player)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null }
        }

    /**
     * The seat whose player sent the match: the one hand on its match stream. Null for a match scored on
     * THRØ by more than one, which is not a match anybody sent.
     */
    private fun senderSeat(match: MatchAggregate): String? {
        val actors = connection.prepareStatement(
            "SELECT DISTINCT actor_id FROM evidence.event WHERE match_id = ? AND event_type IN ('VisitRecorded','VisitRetracted','MatchEndedShort')",
        ).use { ps ->
            ps.setObject(1, match.matchId)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getObject(1) as UUID else null }.toList() }
        }
        return when (actors.singleOrNull()) {
            null -> null
            match.homeId -> Seat.HOME
            match.awayId -> Seat.AWAY
            else -> null
        }
    }

    private fun claimedAtAll(competitor: UUID): Boolean =
        connection.prepareStatement("SELECT 1 FROM identity.player_claim WHERE player_id = ? AND revoked_at IS NULL")
            .use { ps -> ps.setObject(1, competitor); ps.executeQuery().use { it.next() } }

    private fun seatClaimedBy(matchId: UUID, seat: String): UUID? =
        connection.prepareStatement("SELECT player_id FROM competition.seat_claim WHERE match_id = ? AND seat = ?")
            .use { ps ->
                ps.setObject(1, matchId); ps.setString(2, seat)
                ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null }
            }

    // --- the code -----------------------------------------------------------------------------------

    /**
     * A code for the other seat of a match [player] sent. The seat has to be one THRØ holds no person for
     * yet — minted with the upload and claimed by nobody — and a live code for it is handed back rather
     * than a second one made, so asking twice across a table cannot make two.
     */
    public fun codeFor(player: UUID, matchId: UUID): Code {
        val match = Matches(connection).load(matchId) ?: throw Refused("That match is not one you sent.", 404)
        val mine = when (player) { match.homeId -> Seat.HOME; match.awayId -> Seat.AWAY; else -> null }
        if (mine == null || senderSeat(match) != mine) throw Refused("That match is not one you sent.", 404)
        if (!selfReported(matchId)) {
            throw Refused("Codes are for matches sent from a phone. This one was scored on THRØ as it was played.")
        }
        val seat = other(mine)
        if (claimedAtAll(match.idFor(seat)!!) || seatClaimedBy(matchId, seat) != null) {
            throw Refused("The other seat is already somebody's, so there is nothing to give a code for.")
        }
        val at = now()
        connection.prepareStatement(
            """SELECT code, expires_at FROM competition.match_claim_code
                WHERE match_id = ? AND seat = ? AND used_at IS NULL AND expires_at > ?
                ORDER BY created_at DESC LIMIT 1""",
        ).use { ps ->
            ps.setObject(1, matchId); ps.setString(2, seat); ps.setTimestamp(3, Timestamp.from(at))
            ps.executeQuery().use { rs -> if (rs.next()) return Code(rs.getString(1), seat, rs.getTimestamp(2).toInstant()) }
        }
        val expires = at.plus(CODE_TTL)
        repeat(5) {
            val code = Friends.newCode()
            val made = connection.prepareStatement(
                """INSERT INTO competition.match_claim_code (code, match_id, seat, made_by, created_at, expires_at)
                   VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (code) DO NOTHING""",
            ).use { ps ->
                ps.setString(1, code); ps.setObject(2, matchId); ps.setString(3, seat); ps.setObject(4, player)
                ps.setTimestamp(5, Timestamp.from(at)); ps.setTimestamp(6, Timestamp.from(expires))
                ps.executeUpdate()
            }
            if (made == 1) return Code(code, seat, expires)
        }
        error("could not mint a match code")
    }

    /** Enters a match code: the seat it was made for becomes [player]'s. Returns the match. */
    public fun claim(player: UUID, rawCode: String): UUID {
        val code = normalise(rawCode)
        if (!Regex("^[A-HJ-NP-Z2-9]{8}$").matches(code)) {
            throw Refused("That is not a THRØ match code: eight letters and numbers.")
        }
        val wasAutoCommit = connection.autoCommit
        connection.autoCommit = false
        try {
            class Held(val matchId: UUID, val seat: String, val madeBy: UUID, val expiresAt: Instant, val used: Boolean)
            val held = connection.prepareStatement(
                "SELECT match_id, seat, made_by, expires_at, used_at FROM competition.match_claim_code WHERE code = ? FOR UPDATE",
            ).use { ps ->
                ps.setString(1, code)
                ps.executeQuery().use { rs ->
                    if (rs.next()) Held(rs.getObject(1) as UUID, rs.getString(2), rs.getObject(3) as UUID,
                                        rs.getTimestamp(4).toInstant(), rs.getTimestamp(5) != null) else null
                }
            } ?: throw Refused("No match code like that. Check it with the player who gave it to you.")
            if (held.used) throw Refused("That code has been used already. Ask for a new one.")
            if (!held.expiresAt.isAfter(now())) throw Refused("That code has expired. Ask for a new one.")
            if (held.madeBy == player) throw Refused("That is the code you made. Give it to the player you played.")
            if (seatOf(held.matchId, player) != null) throw Refused("You are already in that match.")
            val match = Matches(connection).load(held.matchId) ?: throw Refused("That match is not on THRØ any more.")
            if (claimedAtAll(match.idFor(held.seat)!!) || seatClaimedBy(held.matchId, held.seat) != null) {
                throw Refused("That seat is already somebody's.")
            }
            val at = Timestamp.from(now())
            connection.prepareStatement("UPDATE competition.match_claim_code SET used_by = ?, used_at = ? WHERE code = ?")
                .use { ps -> ps.setObject(1, player); ps.setTimestamp(2, at); ps.setString(3, code); ps.executeUpdate() }
            connection.prepareStatement(
                "INSERT INTO competition.seat_claim (match_id, seat, player_id, code, claimed_at) VALUES (?, ?, ?, ?, ?)",
            ).use { ps ->
                ps.setObject(1, held.matchId); ps.setString(2, held.seat); ps.setObject(3, player)
                ps.setString(4, code); ps.setTimestamp(5, at)
                ps.executeUpdate()
            }
            connection.commit()
            return held.matchId
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = wasAutoCommit
        }
    }

    // --- the answer ---------------------------------------------------------------------------------

    /**
     * The other player's answer for the result. [player] must sit in the match and must not be the one
     * who sent it: the sender's word IS the match, and a player agreeing with themselves is not a second
     * opinion. Appended to the trust stream; every answer is kept, and the latest is the one that stands.
     */
    public fun answer(player: UUID, matchId: UUID, phone: UUID, agree: Boolean) {
        val match = Matches(connection).load(matchId) ?: throw Refused("That match is not yours to answer for.", 404)
        val seat = seatOf(matchId, player) ?: throw Refused("That match is not yours to answer for.", 404)
        if (!selfReported(matchId)) {
            throw Refused("That match was scored on THRØ as it was played, so there is nothing to confirm.")
        }
        if (senderSeat(match) == seat) {
            throw Refused("You sent this match, so it is your word already. The other player answers for it.")
        }
        if (endingOf(matchId)?.first == "abandoned") throw Refused("An abandoned match has no result to confirm.")
        val type = if (agree) "ResultConfirmed" else "ResultContested"
        val device = answerDevice(phone)
        repeat(3) {
            val seq = connection.prepareStatement(
                "SELECT coalesce(max(device_seq), 0) + 1 FROM evidence.event WHERE match_id = ? AND device_id = ?",
            ).use { ps -> ps.setObject(1, matchId); ps.setObject(2, device); ps.executeQuery().use { rs -> rs.next(); rs.getLong(1) } }
            val wrote = connection.prepareStatement(
                """
                INSERT INTO evidence.event
                  (event_id, match_id, device_id, device_seq, event_type, schema_version, correlation_id,
                   actor_id, actor_role, occurred_at, occurred_tz, payload, authority)
                VALUES (?, ?, ?, ?, ?, 1, ?, ?, 'participant', ?, 'Europe/London', ?::jsonb, 'ungranted')
                ON CONFLICT (match_id, device_id, device_seq) DO NOTHING
                """.trimIndent(),
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, matchId); ps.setObject(3, device); ps.setLong(4, seq)
                ps.setString(5, type); ps.setObject(6, UUID.randomUUID()); ps.setObject(7, player)
                ps.setTimestamp(8, Timestamp.from(now())); ps.setString(9, """{"seat":"$seat"}""")
                ps.executeUpdate()
            }
            if (wrote == 1) return
        }
        throw Refused("That answer could not be recorded just now. Try again.", 409)
    }

    private fun selfReported(matchId: UUID): Boolean =
        connection.prepareStatement("SELECT self_reported FROM evidence.match WHERE match_id = ?")
            .use { ps -> ps.setObject(1, matchId); ps.executeQuery().use { rs -> rs.next() && rs.getBoolean(1) } }

    /** How the match ended short, if it did: `retired` or `abandoned`, and the seat that retired. */
    private fun endingOf(matchId: UUID): Pair<String, String?>? =
        connection.prepareStatement(
            "SELECT payload->>'ending', payload->>'seat' FROM evidence.event WHERE match_id = ? AND event_type = 'MatchEndedShort' LIMIT 1",
        ).use { ps -> ps.setObject(1, matchId); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) to rs.getString(2) else null } }

    // --- what either of them reads ------------------------------------------------------------------

    /** The match as [viewer] may read it — only a player in it may — or null. */
    public fun summary(matchId: UUID, viewer: UUID): Summary? {
        val you = seatOf(matchId, viewer) ?: return null
        val match = Matches(connection).load(matchId) ?: return null
        val (openedAt, selfReported) = connection.prepareStatement("SELECT opened_at, self_reported FROM evidence.match WHERE match_id = ?")
            .use { ps -> ps.setObject(1, matchId); ps.executeQuery().use { rs -> rs.next(); rs.getTimestamp(1).toInstant() to rs.getBoolean(2) } }

        class Row(val id: UUID, val type: String, val payload: Map<String, Any?>, val corrects: UUID?)
        val log = connection.prepareStatement(
            "SELECT event_id, event_type, payload::text, corrects_event_id FROM evidence.event WHERE match_id = ? ORDER BY commit_xid, global_seq",
        ).use { ps ->
            ps.setObject(1, matchId)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (rs.next()) Row(rs.getObject(1) as UUID, rs.getString(2), Json.parseObject(rs.getString(3)), rs.getObject(4) as UUID?) else null
                }.toList()
            }
        }

        // The record, replayed: every visit not struck, through the engine, as the board showed it. A
        // visit the engine refuses is still evidence; it simply counts for nothing, as it did at the oche.
        val struck = log.filter { it.type == "VisitRetracted" }.mapNotNull { it.corrects }.toSet()
        var state = MatchState.start(match.format, Seat.home, Seat.away)
        var visits = 0
        for (row in log) {
            if (row.type != "VisitRecorded" || row.id in struck) continue
            val seat = row.payload["player"] as? String ?: continue
            val total = (row.payload["visitTotal"] as? Number)?.toInt() ?: continue
            val visit = Command.RecordVisit(PlayerId(seat), total,
                                            (row.payload["dartsUsed"] as? Number)?.toInt(),
                                            (row.payload["dartsAtDouble"] as? Number)?.toInt())
            val outcome = Engine.apply(state, visit)
            if (outcome is Outcome.Accepted) { state = outcome.state; visits++ }
        }
        val ended = log.firstOrNull { it.type == "MatchEndedShort" }
        val how = ended?.payload?.get("ending") as? String
        val retired = if (how == "retired") ended?.payload?.get("seat") as? String else null
        val winner = when {
            retired != null -> other(retired)
            how == "abandoned" -> null
            else -> state.winner?.value
        }

        // Each seat's latest answer, where it still answers for the record as it now stands: agreeing
        // to a record that has changed since is not agreeing to this one (PD-011), so an answer given
        // before the last change reads as no answer, and the other player is asked again.
        val lastChange = log.indexOfLast { it.type in RECORD }
        val answers = mutableMapOf<String, String?>(Seat.HOME to null, Seat.AWAY to null)
        log.forEachIndexed { i, row ->
            if (row.type == "ResultConfirmed" || row.type == "ResultContested") {
                val seat = row.payload["seat"] as? String ?: return@forEachIndexed
                answers[seat] = when {
                    i < lastChange -> null
                    row.type == "ResultConfirmed" -> "confirmed"
                    else -> "contested"
                }
            }
        }
        val sender = senderSeat(match)
        val standing = when {
            !selfReported -> "recorded"
            "contested" in answers.values -> "disputed"
            sender != null && answers[other(sender)] == "confirmed" -> "confirmed"
            else -> "self-reported"
        }

        // Claimable means a code could be made for it: the seat opposite the sender, of a match sent
        // from a phone, that nobody holds yet. Not "held by no account" — the first version said
        // that, and a sender whose competitor had no account read their own seat as up for grabs.
        val seats = SEATS.map { seat ->
            val competitor = match.idFor(seat)!!
            val claimedBy = seatClaimedBy(matchId, seat)
            SeatLine(seat = seat, you = seat == you, name = nameOf(claimedBy ?: competitor),
                     claimable = selfReported && sender != null && seat != sender && claimedBy == null && !claimedAtAll(competitor))
        }
        return Summary(
            matchId = matchId, openedAt = openedAt, format = match.format, selfReported = selfReported, seats = seats,
            legs = mapOf(Seat.HOME to (state.legsWonTotal[Seat.home] ?: 0), Seat.AWAY to (state.legsWonTotal[Seat.away] ?: 0)),
            visits = visits, ending = how, retired = retired, winner = winner, sentBy = sender, answers = answers, standing = standing,
        )
    }

    /** The matches [viewer] sits in — sent by them, or claimed — newest first. */
    public fun mine(viewer: UUID, limit: Int = 30): List<Summary> {
        val ids = connection.prepareStatement(
            """SELECT match_id FROM (
                 SELECT m.match_id, m.opened_at FROM evidence.match m WHERE m.home_id = ? OR m.away_id = ?
                 UNION
                 SELECT m.match_id, m.opened_at FROM competition.seat_claim s JOIN evidence.match m ON m.match_id = s.match_id
                  WHERE s.player_id = ?
               ) mine ORDER BY opened_at DESC LIMIT ?""",
        ).use { ps ->
            ps.setObject(1, viewer); ps.setObject(2, viewer); ps.setObject(3, viewer); ps.setInt(4, limit)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getObject(1) as UUID else null }.toList() }
        }
        return ids.mapNotNull { summary(it, viewer) }
    }

    /** A person's display name, where THRØ may show it (V016) and they have given one; null otherwise. */
    private fun nameOf(player: UUID): String? =
        connection.prepareStatement(
            """SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> ? THEN a.display_name END
                 FROM identity.player_claim c
                 JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                WHERE c.player_id = ? AND c.revoked_at IS NULL""",
        ).use { ps ->
            ps.setString(1, Accounts.PLACEHOLDER_NAME); ps.setObject(2, player)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null }
        }

    // --- the wire -----------------------------------------------------------------------------------

    private fun q(v: String?): String = if (v == null) "null" else "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    public fun json(c: Code): String = """{"code":"${c.code}","seat":"${c.seat}","expiresAt":"${c.expiresAt}"}"""

    public fun json(s: Summary): String {
        val f = s.format
        val seats = s.seats.joinToString(",") { """{"seat":"${it.seat}","you":${it.you},"name":${q(it.name)},"claimable":${it.claimable}}""" }
        return """{"matchId":"${s.matchId}","openedAt":"${s.openedAt}",""" +
            """"format":{"startingScore":${f.startingScore},"inRule":"${f.inRule.name.lowercase()}","outRule":"${f.outRule.name.lowercase()}",""" +
            """"legsMode":"${f.legs.mode.name.lowercase()}","legsTarget":${f.legs.target},"throwFirst":"${f.throwFirst.value}"},""" +
            """"selfReported":${s.selfReported},"seats":[$seats],"legs":{"home":${s.legs[Seat.HOME]},"away":${s.legs[Seat.AWAY]}},""" +
            """"visits":${s.visits},"ending":${q(s.ending)},"retired":${q(s.retired)},"winner":${q(s.winner)},"sentBy":${q(s.sentBy)},""" +
            """"answers":{"home":${q(s.answers[Seat.HOME])},"away":${q(s.answers[Seat.AWAY])}},"standing":"${s.standing}"}"""
    }

    public fun json(list: List<Summary>): String = """{"matches":[${list.joinToString(",") { json(it) }}]}"""
}
