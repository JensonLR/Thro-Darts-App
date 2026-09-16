package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID
import thro.rating.Display
import thro.rating.EvidenceRow
import thro.rating.Glicko2Model
import thro.rating.LedgerLine
import thro.rating.PlayerId
import thro.rating.Projection
import thro.rating.Publication
import thro.rating.RatingModel
import thro.rating.Snapshot
import thro.rating.Watermark

/**
 * The provisional rating, materialised (PD-105).
 *
 * **Lazy, and as of a watermark.** A rating is a projection over eligible evidence (ADR-009), replayed rather than
 * nudged, so a corrected match ripples to everybody downstream of it. It is recomputed when somebody asks and the
 * evidence has moved past the snapshot's watermark, in this connection as `app_rating` — the role that may write the
 * rating tables and nothing else. At today's volumes a replay is milliseconds; when it is not, this is the one place
 * that changes.
 *
 * **What is eligible.** A match scored on THRØ that finished with a winner and stands as *recorded* (scored live) or
 * *confirmed* (sent from a phone and agreed by the other seat). A self-reported match nobody confirmed, a disputed
 * one, an abandoned one, and a league's declared result (which is never evidence, PD-055) are not.
 */
public class Ratings(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public companion object {
        public val MODEL: Glicko2Model = Glicko2Model()
        /** The row `rating.published_model` needs a publisher for; the decision is PD-105's, and this names it. */
        private val DECIDED_BY: UUID = UUID.fromString("00000000-0000-0000-0000-000000000105")
    }

    /** One match line. The opponent is an id here; naming them is the read role's, after the replay (see [json]). */
    public data class Line(val matchId: UUID, val at: Watermark, val delta: Double, val opponent: UUID,
                           val opponentRating: Double?, val ownRatingBefore: Double?, val expected: Double?, val won: Boolean)
    public data class Answer(val player: UUID, val display: Display, val snapshot: Snapshot?, val lines: List<Line>, val asOf: Watermark)

    /** The player's rating as it stands, replayed first if the evidence has moved. */
    public fun of(player: UUID): Answer {
        ensureCurrent()
        val snapshot = snapshotOf(player)
        val lines = linesOf(player)
        return Answer(player, Display.of(snapshot, MODEL), snapshot, lines, snapshot?.asOf ?: evidenceWatermark())
    }

    // --- materialising ------------------------------------------------------------------------------------------

    private fun ensureCurrent() {
        val evidence = evidenceWatermark()
        val have = snapshotWatermark()
        if (have != null && have >= evidence) return
        replayTo(evidence)
    }

    private fun replayTo(asOf: Watermark) {
        val rows = eligibleRows()
        val replay = Projection.replay(rows, MODEL, asOf)
        val wasAuto = connection.autoCommit
        connection.autoCommit = false
        try {
            publishModel()
            connection.prepareStatement("DELETE FROM rating.snapshot WHERE model_id = ?").use { ps -> ps.setString(1, MODEL.id); ps.executeUpdate() }
            connection.prepareStatement("DELETE FROM rating.ledger WHERE model_id = ?").use { ps -> ps.setString(1, MODEL.id); ps.executeUpdate() }
            // Every player who has evidence gets a snapshot at this watermark, so "is it current" is one comparison; a
            // player with no qualifying match gets none, which reads as unrated.
            connection.prepareStatement(
                """INSERT INTO rating.snapshot (player_id, model_id, model_version, parameter_hash, scale_epoch, as_of_commit_xid, as_of_global_seq,
                                                rating, confidence, matches_counted, computed_at, published, dispersion, pool)
                   VALUES (?, ?, ?, ?, ?, ?::text::xid8, ?, ?, ?, ?, ?, ?, ?, ?)""",
            ).use { ps ->
                for (s in replay.snapshots) {
                    ps.setObject(1, UUID.fromString(s.player.value)); ps.setString(2, s.modelId); ps.setString(3, s.modelVersion)
                    ps.setString(4, s.parameterHash); ps.setInt(5, s.scaleEpoch); ps.setString(6, asOf.commitXid.toString()); ps.setLong(7, asOf.globalSeq)
                    ps.setObject(8, s.rating); ps.setDouble(9, s.confidence); ps.setInt(10, s.matchesCounted); ps.setTimestamp(11, Timestamp.from(now()))
                    ps.setBoolean(12, s.published); ps.setObject(13, s.dispersion); ps.setInt(14, s.pool)
                    ps.addBatch()
                }
                ps.executeBatch()
            }
            connection.prepareStatement(
                """INSERT INTO rating.ledger (ledger_id, player_id, model_id, at_commit_xid, at_global_seq, cause, match_id, delta, explanation)
                   VALUES (?, ?, ?, ?::text::xid8, ?, ?, ?, ?, ?::jsonb)""",
            ).use { ps ->
                for (l in replay.ledger) {
                    ps.setObject(1, UUID.randomUUID()); ps.setObject(2, UUID.fromString(l.player.value)); ps.setString(3, MODEL.id)
                    ps.setString(4, l.at.commitXid.toString()); ps.setLong(5, l.at.globalSeq); ps.setString(6, l.cause.name.lowercase())
                    ps.setObject(7, l.matchId?.let(UUID::fromString)); ps.setDouble(8, l.delta); ps.setString(9, explanationJson(l))
                    ps.addBatch()
                }
                ps.executeBatch()
            }
            connection.commit()
        } catch (e: Exception) {
            connection.rollback(); throw e
        } finally {
            connection.autoCommit = wasAuto
        }
    }

    /** Exactly one model is published; the check that guards it is the rating package's, not this file's. */
    private fun publishModel() {
        val published = connection.prepareStatement("SELECT model_id FROM rating.published_model").use { ps ->
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getString(1) else null }.toSet() }
        }
        when (val r = Publication.check(MODEL, published)) {
            is Publication.Result.Refused -> throw IllegalStateException(r.why)
            Publication.Result.Allowed -> {}
        }
        if (MODEL.id !in published) {
            connection.prepareStatement("DELETE FROM rating.published_model").use { it.executeUpdate() }
            connection.prepareStatement("INSERT INTO rating.published_model (model_id, model_version, scale_epoch, published_by) VALUES (?, ?, 1, ?)")
                .use { ps -> ps.setString(1, MODEL.id); ps.setString(2, MODEL.version); ps.setObject(3, DECIDED_BY); ps.executeUpdate() }
        }
    }

    private fun explanationJson(l: LedgerLine): String {
        val e = l.explanation ?: return "null"
        return """{"opponent":"${e.opponent.value}","opponentRating":${e.opponentRatingAtTheTime ?: "null"},"opponentConfidence":${e.opponentConfidenceAtTheTime},""" +
            """"ownRating":${e.ownRatingAtTheTime ?: "null"},"expected":${e.predictedProbability ?: "null"},"outcome":${e.realisedOutcome},"model":${thro.api.http.Contract.q(e.modelVersion)}}"""
    }

    // --- the evidence view ---------------------------------------------------------------------------------------

    /** Every finished match on THRØ as the model sees it: who, the outcome, and whether it qualifies. */
    private fun eligibleRows(): List<EvidenceRow> {
        val matches = connection.prepareStatement(
            """SELECT m.match_id, m.home_id, m.away_id, max(e.commit_xid::text::bigint), max(e.global_seq)
                 FROM evidence.match m JOIN evidence.event e ON e.match_id = m.match_id
                GROUP BY m.match_id, m.home_id, m.away_id""",
        ).use { ps ->
            ps.executeQuery().use { rs ->
                generateSequence { if (rs.next()) listOf(rs.getObject(1), rs.getObject(2), rs.getObject(3), rs.getLong(4), rs.getLong(5)) else null }.toList()
            }
        }
        val records = MatchRecords(connection, now)
        return matches.mapNotNull { m ->
            val replayed = records.replay(m[0] as UUID) ?: return@mapNotNull null
            val winner = replayed.winner ?: return@mapNotNull null
            EvidenceRow(
                matchId = (m[0] as UUID).toString(), at = Watermark(m[3] as Long, m[4] as Long),
                home = PlayerId((m[1] as UUID).toString()), away = PlayerId((m[2] as UUID).toString()),
                homeScore = if (winner == Seat.HOME) 1.0 else 0.0,
                legsHome = replayed.legs[Seat.HOME] ?: 0, legsAway = replayed.legs[Seat.AWAY] ?: 0,
                qualifying = replayed.standing == "recorded" || replayed.standing == "confirmed",
            )
        }
    }

    private fun evidenceWatermark(): Watermark =
        connection.prepareStatement("SELECT coalesce(max(commit_xid::text::bigint), 0), coalesce(max(global_seq), 0) FROM evidence.event").use { ps ->
            ps.executeQuery().use { rs -> rs.next(); Watermark(rs.getLong(1), rs.getLong(2)) }
        }

    private fun snapshotWatermark(): Watermark? =
        connection.prepareStatement("SELECT as_of_commit_xid::text::bigint, as_of_global_seq FROM rating.snapshot WHERE model_id = ? LIMIT 1").use { ps ->
            ps.setString(1, MODEL.id)
            ps.executeQuery().use { rs -> if (rs.next()) Watermark(rs.getLong(1), rs.getLong(2)) else null }
        }

    private fun snapshotOf(player: UUID): Snapshot? =
        connection.prepareStatement(
            """SELECT model_version, parameter_hash, scale_epoch, as_of_commit_xid::text::bigint, as_of_global_seq, rating, confidence, matches_counted,
                      published, dispersion, pool
                 FROM rating.snapshot WHERE player_id = ? AND model_id = ?""",
        ).use { ps ->
            ps.setObject(1, player); ps.setString(2, MODEL.id)
            ps.executeQuery().use { rs ->
                if (!rs.next()) null else Snapshot(
                    player = PlayerId(player.toString()), modelId = MODEL.id, modelVersion = rs.getString(1), parameterHash = rs.getString(2),
                    scaleEpoch = rs.getInt(3), asOf = Watermark(rs.getLong(4), rs.getLong(5)),
                    rating = rs.getObject(6) as Double?, confidence = rs.getDouble(7), matchesCounted = rs.getInt(8), published = rs.getBoolean(9),
                    dispersion = rs.getObject(10) as Double?, pool = rs.getInt(11),
                )
            }
        }

    /** The player's match lines, newest first. Ids only: this runs as the rating role, which reads no names. */
    private fun linesOf(player: UUID): List<Line> =
        connection.prepareStatement(
            """SELECT l.match_id, l.at_commit_xid::text::bigint, l.at_global_seq, l.delta, l.explanation::text
                 FROM rating.ledger l WHERE l.player_id = ? AND l.model_id = ? AND l.cause = 'match'
                ORDER BY l.at_commit_xid DESC, l.at_global_seq DESC, l.match_id""",
        ).use { ps ->
            ps.setObject(1, player); ps.setString(2, MODEL.id)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null else {
                        val e = Json.parseObject(rs.getString(5))
                        val opponent = UUID.fromString(e["opponent"] as String)
                        Line(
                            matchId = rs.getObject(1) as UUID, at = Watermark(rs.getLong(2), rs.getLong(3)), delta = rs.getDouble(4),
                            opponent = opponent,
                            opponentRating = (e["opponentRating"] as? Number)?.toDouble(), ownRatingBefore = (e["ownRating"] as? Number)?.toDouble(),
                            expected = (e["expected"] as? Number)?.toDouble(), won = ((e["outcome"] as? Number)?.toDouble() ?: 0.0) >= 0.5,
                        )
                    }
                }.toList()
            }
        }

    /**
     * A name where THRØ may show one (V016): an adult with their own live consent, and never the placeholder.
     * **Runs as the read role**, never the rating one, which a schema property keeps out of `identity` altogether.
     */
    public fun nameOf(player: UUID): String? =
        connection.prepareStatement(
            """SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> ? THEN a.display_name END
                 FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                WHERE c.player_id = ? AND c.revoked_at IS NULL""",
        ).use { ps ->
            ps.setString(1, Accounts.PLACEHOLDER_NAME); ps.setObject(2, player)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null }
        }

    /** Whether THRØ may show this player to others at all — the same rule as a roster. */
    public fun mayBeShown(player: UUID): Boolean =
        connection.prepareStatement("SELECT identity.player_may_be_disclosed(?)").use { ps ->
            ps.setObject(1, player); ps.executeQuery().use { rs -> rs.next() && rs.getBoolean(1) }
        }

    // --- words ----------------------------------------------------------------------------------------------------

    /**
     * The JSON a phone reads. The display is one of three shapes and nothing else; each line carries the frozen facts
     * and a sentence from a bounded vocabulary — never a model internal.
     */
    public fun json(a: Answer, names: Map<UUID, String?>): String {
        val q = thro.api.http.Contract::q
        val display = when (val d = a.display) {
            Display.Unrated -> """{"kind":"unrated","matches":0,"comparedAcross":0}"""
            is Display.Provisional -> """{"kind":"provisional","low":${d.low},"high":${d.high},"matches":${d.matches},"comparedAcross":${d.pool}}"""
            is Display.Established -> """{"kind":"established","value":${d.value},"plusMinus":${d.plusMinus},"matches":${d.matches},"comparedAcross":${d.pool}}"""
        }
        val lines = a.lines.joinToString(",") { l ->
            val name = names[l.opponent]
            val who = name?.let { q(it) } ?: "null"
            val rated = l.opponentRating?.let { Math.round(it) }
            val words = buildString {
                append(if (l.won) "Beat " else "Lost to ")
                append(name ?: "an opponent")
                if (rated != null) append(", rated about $rated")
                append(". ")
                val e = l.expected
                append(when {
                    e == null -> ""
                    l.won && e < 0.35 -> "An upset in your favour."
                    l.won && e > 0.65 -> "Expected, so it moved you a little."
                    !l.won && e > 0.65 -> "An upset against you."
                    !l.won && e < 0.35 -> "Expected, so it moved you a little."
                    else -> "An even contest."
                })
            }.trim()
            """{"matchId":"${l.matchId}","outcome":${q(if (l.won) "won" else "lost")},"delta":${Math.round(l.delta)},"opponent":$who,""" +
                """"opponentRating":${rated ?: "null"},"expected":${l.expected?.let { "%.2f".format(it) } ?: "null"},"words":${q(words)}}"""
        }
        return """{"playerId":"${a.player}","model":${q(MODEL.id)},"version":${q(MODEL.version)},"stage":${q(MODEL.stage.name.lowercase())},""" +
            """"display":$display,"asOf":{"commit":${a.asOf.commitXid},"seq":${a.asOf.globalSeq}},"lines":[$lines]}"""
    }
}
