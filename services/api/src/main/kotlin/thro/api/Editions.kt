package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * A knockout run on THRØ (PD-109): the HTTP shape over the event lifecycle in [Competitions].
 *
 * **What was there.** `Competitions` opened an edition, took entries, checked a competitor in (issuing the scoring
 * grant that lets them score all day with no signal — ADR-006), and made the first-round draw; `Events` put open
 * editions on the notice on the door and `Discovery` said who could play them. None of it could be reached by an
 * organiser or a player. This is the reachable half: who may call what, and what the event's page says.
 *
 * **What it does not do.** Later rounds. The domain draws round one and lets a tie cite the match it was played in;
 * advancing winners is not in the domain and is not pretended here. An edition on THRØ today is a first round, drawn
 * and scored, with the organiser running the rest by hand.
 */
public class Editions(
    private val connection: Connection, private val now: () -> Instant = Instant::now,
    /**
     * Check-in writes two tables owned by two roles: the grant is trust's, the check-in row is competition's. The
     * request switches role between them, named as "trust" and "competition"; a caller with one role for everything
     * (a test on the owner) passes nothing.
     */
    private val asRole: (String) -> Unit = {},
) {

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    /** How long before the start a player may check in: the door opens the morning of the event. */
    private val checkInWindow: Duration = Duration.ofHours(12)
    private val rel get() = Relations(connection)

    private fun runs(by: UUID, event: UUID) = rel.decide(by, "event.manage", ObjectRef(ObjectType.EVENT, event.toString())).allowed

    public data class Tie(val tieId: UUID, val round: Int, val position: Int, val homeId: UUID, val home: String?, val awayId: UUID?, val away: String?, val isBye: Boolean, val matchId: UUID?,
                          val winnerId: UUID? = null, val outcome: String? = null, val note: String? = null)
    public data class You(val entered: Boolean, val checkedIn: Boolean)
    public data class View(
        val eventId: UUID, val name: String, val startsAt: Instant, val sessionEndsAt: Instant, val venueId: UUID?, val venue: String?, val locality: String?,
        val venueLabel: String?, val entrantKind: String, val access: String, val state: String, val entriesCloseAt: Instant?, val capacity: Int?,
        val entries: Int, val you: You?, val ties: List<Tie>,
    )

    private fun row(eventId: UUID, viewer: UUID?): View? = connection.prepareStatement(
        """SELECT e.name, e.starts_at, e.session_ends_at, v.venue_id, v.name, v.locality, e.venue_label, e.entrant_kind, e.access, e.state,
                  e.entries_close_at, e.capacity,
                  (SELECT count(*) FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL),
                  (SELECT count(*) FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL AND en.player_id = ?),
                  (SELECT count(*) FROM competition.check_in ci WHERE ci.event_id = e.event_id AND ci.player_id = ?)
             FROM competition.event e LEFT JOIN competition.venue v ON v.venue_id = e.venue_id AND v.visibility = 'public'
            WHERE e.event_id = ?""",
    ).use { ps ->
        ps.setObject(1, viewer); ps.setObject(2, viewer); ps.setObject(3, eventId)
        ps.executeQuery().use { rs ->
            if (!rs.next()) null
            else View(
                eventId, rs.getString(1), rs.getTimestamp(2).toInstant(), rs.getTimestamp(3).toInstant(), rs.getObject(4) as UUID?, rs.getString(5), rs.getString(6),
                rs.getString(7), rs.getString(8), rs.getString(9), rs.getString(10), rs.getTimestamp(11)?.toInstant(), rs.getObject(12) as Int?,
                rs.getInt(13), viewer?.let { You(rs.getInt(14) > 0, rs.getInt(15) > 0) }, emptyList(),
            )
        }
    }

    private fun ties(eventId: UUID): List<Tie> = connection.prepareStatement(
        """SELECT t.fixture_id, t.round_number, t.position, t.home_id, t.away_id, t.is_bye, t.match_id, t.winner_id, t.outcome, t.note,
                  (SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> ? THEN a.display_name END
                     FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                    WHERE c.player_id = t.home_id AND c.revoked_at IS NULL),
                  (SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> ? THEN a.display_name END
                     FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                    WHERE c.player_id = t.away_id AND c.revoked_at IS NULL)
             FROM competition.bracket_tie t WHERE t.event_id = ? ORDER BY t.round_number, t.position""",
    ).use { ps ->
        ps.setString(1, Accounts.PLACEHOLDER_NAME); ps.setString(2, Accounts.PLACEHOLDER_NAME); ps.setObject(3, eventId)
        ps.executeQuery().use { rs ->
            generateSequence {
                if (!rs.next()) null
                else Tie(rs.getObject(1) as UUID, rs.getInt(2), rs.getInt(3), rs.getObject(4) as UUID, rs.getString(11), rs.getObject(5) as UUID?, rs.getString(12), rs.getBoolean(6), rs.getObject(7) as UUID?,
                         rs.getObject(8) as UUID?, rs.getString(9), rs.getString(10))
            }.toList()
        }
    }

    /** The event's page: for anybody; `you` only with a session. */
    public fun view(eventId: UUID, viewer: UUID?): View {
        val v = row(eventId, viewer) ?: throw Refused("THRØ has no such event.", 404)
        return if (v.state in setOf("drawn", "in_progress", "complete")) v.copy(ties = ties(eventId)) else v
    }

    // --- the organiser --------------------------------------------------------------------------------------------

    public fun open(by: UUID, name: String, startsAt: Instant, sessionEndsAt: Instant, venueId: UUID?, venueLabel: String?, entriesCloseAt: Instant?, capacity: Int?): View {
        val title = name.trim()
        if (title.length !in 2..80) throw Refused("An event has a name, two to eighty characters.", 400)
        if (!sessionEndsAt.isAfter(startsAt)) throw Refused("The session ends after it starts.", 400)
        if (!startsAt.isAfter(now())) throw Refused("The event starts in the future.", 400)
        if (entriesCloseAt != null && entriesCloseAt.isAfter(startsAt)) throw Refused("Entries close before the event starts.", 400)
        if (capacity != null && capacity < 2) throw Refused("A knockout has at least two places.", 400)
        if (venueId != null && !connection.prepareStatement("SELECT 1 FROM competition.venue WHERE venue_id = ?").use { ps -> ps.setObject(1, venueId); ps.executeQuery().use { it.next() } }) {
            throw Refused("THRØ has no such venue.", 400)
        }
        val id = UUID.randomUUID()
        Competitions(connection).openEvent(id, title, startsAt, sessionEndsAt, venueLabel?.trim()?.takeIf { it.isNotEmpty() }, venueId, entriesCloseAt = entriesCloseAt, capacity = capacity)
        rel.grant(by, "organiser", ObjectRef(ObjectType.EVENT, id.toString()), by = by)
        return view(id, by)
    }

    public data class Mine(val eventId: UUID, val name: String, val startsAt: Instant, val state: String, val entries: Int)

    public fun mine(by: UUID): List<Mine> = connection.prepareStatement(
        """SELECT e.event_id, e.name, e.starts_at, e.state, (SELECT count(*) FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL)
             FROM authz.relation r JOIN competition.event e ON e.event_id::text = r.object_id
            WHERE r.subject_id = ? AND r.relation = 'organiser' AND r.object_type = 'event' AND r.revoked_at IS NULL
            ORDER BY e.starts_at DESC""",
    ).use { ps ->
        ps.setObject(1, by)
        ps.executeQuery().use { rs -> generateSequence { if (!rs.next()) null else Mine(rs.getObject(1) as UUID, rs.getString(2), rs.getTimestamp(3).toInstant(), rs.getString(4), rs.getInt(5)) }.toList() }
    }

    public fun close(eventId: UUID, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser closes its entries.", 403)
        if (v.state != "open") throw Refused("Entries are not open; the event is ${v.state.replace('_', ' ')}.", 409)
        connection.prepareStatement("UPDATE competition.event SET state = 'entries_closed' WHERE event_id = ? AND state = 'open'").use { ps -> ps.setObject(1, eventId); ps.executeUpdate() }
        return view(eventId, by)
    }

    public fun draw(eventId: UUID, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser makes the draw.", 403)
        if (v.state !in setOf("open", "entries_closed")) throw Refused("The draw was already made; the event is ${v.state.replace('_', ' ')}.", 409)
        if (v.entries < 2) throw Refused("A draw needs at least two entrants; this event has ${v.entries}.", 409)
        try { Competitions(connection).draw(eventId) } catch (e: IllegalArgumentException) { throw Refused(e.message ?: "The draw could not be made.", 409) }
        return view(eventId, by)
    }

    // --- rounds (PD-111): a tie is decided, and the organiser advances --------------------------------------------

    private fun tie(eventId: UUID, tieId: UUID): Tie = ties(eventId).firstOrNull { it.tieId == tieId } ?: throw Refused("THRØ has no such tie in this event.", 404)

    private fun decide(tieId: UUID, winner: UUID, outcome: String, note: String?, by: UUID, matchId: UUID? = null) {
        val n = connection.prepareStatement(
            """UPDATE competition.bracket_tie SET winner_id = ?, outcome = ?, note = ?, decided_by = ?, decided_at = clock_timestamp(), match_id = coalesce(?, match_id)
                WHERE fixture_id = ? AND winner_id IS NULL""",
        ).use { ps -> ps.setObject(1, winner); ps.setString(2, outcome); ps.setString(3, note); ps.setObject(4, by); ps.setObject(5, matchId); ps.setObject(6, tieId); ps.executeUpdate() }
        if (n == 0) throw Refused("This tie was decided a moment ago.", 409)
        connection.prepareStatement("UPDATE competition.event SET state = 'in_progress' WHERE event_id = (SELECT event_id FROM competition.bracket_tie WHERE fixture_id = ?) AND state = 'drawn'")
            .use { ps -> ps.setObject(1, tieId); ps.executeUpdate() }
    }

    /** The organiser's word: a walkover or an award, with a note that says why. Never a played result — that is the match's. */
    public fun declare(eventId: UUID, tieId: UUID, winnerId: UUID, outcome: String, note: String?, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser declares a tie.", 403)
        if (outcome !in setOf("walkover", "awarded")) throw Refused("A declared outcome is a walkover or an award; a played tie cites its match.", 400)
        if (note.isNullOrBlank()) throw Refused("A declared outcome says why.", 400)
        val t = tie(eventId, tieId)
        if (t.isBye) throw Refused("A bye is not decided; its one side goes through by construction.", 409)
        if (winnerId != t.homeId && winnerId != t.awayId) throw Refused("The winner is one of the tie's two sides.", 400)
        if (t.winnerId != null) throw Refused("This tie is decided: ${t.outcome}. A decision is not a field to point elsewhere.", 409)
        if (v.state !in setOf("drawn", "in_progress")) throw Refused("The event is ${v.state.replace('_', ' ')}.", 409)
        decide(tieId, winnerId, outcome, note.trim().take(280), by)
        return view(eventId, by)
    }

    /**
     * A tie played on THRØ names its match, once, by somebody who played it or the organiser; the winner is read from
     * the match's own record (`MatchRecords.replay`, the one derivation), never typed.
     */
    public fun citeTie(eventId: UUID, tieId: UUID, matchId: UUID, by: UUID): View {
        val v = view(eventId, by)
        val t = tie(eventId, tieId)
        if (t.isBye) throw Refused("A bye has no match.", 409)
        val match = Matches(connection).load(matchId) ?: throw Refused("THRØ has no such match.", 404)
        if (by !in match.participants && !runs(by, eventId)) throw Refused("Only somebody who played the match, or the organiser, cites it.", 403)
        if (match.participants != setOf(t.homeId, t.awayId)) throw Refused("That match was not between this tie's two players.", 409)
        if (t.winnerId != null) throw Refused("This tie is decided: ${t.outcome}.", 409)
        if (v.state !in setOf("drawn", "in_progress")) throw Refused("The event is ${v.state.replace('_', ' ')}.", 409)
        val replayed = MatchRecords(connection).replay(matchId) ?: throw Refused("That match has no record to read.", 409)
        val winnerSeat = replayed.winner ?: throw Refused("That match has no winner yet: it is not finished, or it was abandoned.", 409)
        val winner = if (winnerSeat == Seat.HOME) match.homeId else match.awayId
        decide(tieId, winner, "played", null, by, matchId)
        return view(eventId, by)
    }

    /**
     * Once every tie in the current round is decided, the next round is drawn from the winners in position order
     * — (1 v 2), (3 v 4) — and a round of one decided tie completes the event. Byes go through by construction.
     */
    public fun advance(eventId: UUID, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser advances a round.", 403)
        if (v.state !in setOf("drawn", "in_progress")) throw Refused("The event is ${v.state.replace('_', ' ')}; there is no round to advance.", 409)
        val all = ties(eventId)
        val round = all.maxOf { it.round }
        val current = all.filter { it.round == round }
        val winners = current.map { t -> if (t.isBye) t.homeId else t.winnerId }
        val undecided = winners.count { it == null }
        if (undecided > 0) throw Refused("Round $round has $undecided undecided tie${if (undecided == 1) "" else "s"}; every tie is decided before the next round is drawn.", 409)
        val through = winners.map { it!! }
        if (through.size == 1) {
            connection.prepareStatement("UPDATE competition.event SET state = 'complete' WHERE event_id = ? AND state IN ('drawn','in_progress')").use { ps -> ps.setObject(1, eventId); ps.executeUpdate() }
            return view(eventId, by)
        }
        connection.prepareStatement("INSERT INTO competition.bracket_tie (fixture_id, event_id, round_number, position, home_id, away_id, is_bye) VALUES (?, ?, ?, ?, ?, ?, false)").use { ps ->
            through.chunked(2).forEachIndexed { i, pair ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, eventId); ps.setInt(3, round + 1); ps.setInt(4, i + 1); ps.setObject(5, pair[0]); ps.setObject(6, pair[1]); ps.addBatch()
            }
            ps.executeBatch()
        }
        return view(eventId, by)
    }

    // --- the player -----------------------------------------------------------------------------------------------

    public fun enter(eventId: UUID, player: UUID): View {
        val v = view(eventId, player)
        if (v.access != "open") throw Refused("This event is ${v.access.replace('_', ' ')}: entry is by the organiser.", 403)
        if (v.state != "open") throw Refused("Entries are closed.", 409)
        if (v.entriesCloseAt != null && !now().isBefore(v.entriesCloseAt)) throw Refused("Entries closed at ${v.entriesCloseAt}.", 409)
        if (v.entrantKind != "player") throw Refused("This event is entered as a ${v.entrantKind}, not a single player.", 409)
        if (v.you?.entered == true) throw Refused("You are already entered.", 409)
        if (v.capacity != null && v.entries >= v.capacity) throw Refused("This event is full: ${v.capacity} places, all taken.", 409)
        // A withdrawn entry comes back rather than being duplicated: one row per competitor per event is the schema's rule.
        val revived = connection.prepareStatement("UPDATE competition.entry SET withdrawn_at = NULL, entered_at = clock_timestamp() WHERE event_id = ? AND player_id = ? AND withdrawn_at IS NOT NULL")
            .use { ps -> ps.setObject(1, eventId); ps.setObject(2, player); ps.executeUpdate() }
        if (revived == 0) Competitions(connection).enter(eventId, player)
        return view(eventId, player)
    }

    public fun withdraw(eventId: UUID, player: UUID): View {
        val v = view(eventId, player)
        if (v.state !in setOf("open", "entries_closed")) throw Refused("The draw is made; withdrawing now is for the organiser to record.", 409)
        val n = connection.prepareStatement("UPDATE competition.entry SET withdrawn_at = clock_timestamp() WHERE event_id = ? AND player_id = ? AND withdrawn_at IS NULL")
            .use { ps -> ps.setObject(1, eventId); ps.setObject(2, player); ps.executeUpdate() }
        if (n == 0) throw Refused("You are not entered.", 409)
        return view(eventId, player)
    }

    public data class Checked(val grantId: UUID, val expiresAt: Instant)

    /**
     * The entrant checks in from their own phone, on the day. The grant is issued under the organiser of record, and
     * is what the evidence their phone records is annotated with.
     */
    public fun checkIn(eventId: UUID, player: UUID, device: UUID): Checked {
        val v = view(eventId, player)
        if (v.you?.entered != true) throw Refused("Only an entrant checks in.", 409)
        if (v.state == "cancelled" || v.state == "complete") throw Refused("This event is ${v.state}.", 409)
        val at = now()
        if (at.isBefore(v.startsAt.minus(checkInWindow))) throw Refused("Check-in opens twelve hours before the event starts, on ${v.startsAt.minus(checkInWindow)}.", 409)
        if (at.isAfter(v.sessionEndsAt)) throw Refused("The session has ended.", 409)
        val organiser = connection.prepareStatement("SELECT subject_id FROM authz.relation WHERE object_type = 'event' AND object_id = ? AND relation = 'organiser' AND revoked_at IS NULL ORDER BY granted_at LIMIT 1")
            .use { ps -> ps.setString(1, eventId.toString()); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else player } }
        // The grant first, as trust (it supersedes any earlier grant to this phone, which is a read of trust's table);
        // then the check-in row, as competition, pointing at the grant. The same two writes `Competitions.checkIn`
        // makes, split only by the role that may make each.
        asRole("trust")
        val grantId = Grants(connection).issue(eventId = eventId, actorId = player, deviceId = device, actorRole = "participant", sessionEndsAt = v.sessionEndsAt, issuedBy = organiser)
        val expires = connection.prepareStatement("SELECT expires_at FROM trust.scoring_grant WHERE grant_id = ?")
            .use { ps -> ps.setObject(1, grantId); ps.executeQuery().use { rs -> rs.next(); rs.getTimestamp(1).toInstant() } }
        asRole("competition")
        connection.prepareStatement(
            """INSERT INTO competition.check_in (event_id, competitor_id, device_id, grant_id, player_id) VALUES (?, ?, ?, ?, ?)
               ON CONFLICT (event_id, player_id, device_id) DO UPDATE SET grant_id = EXCLUDED.grant_id, competitor_id = EXCLUDED.competitor_id, checked_in_at = clock_timestamp()""",
        ).use { ps -> ps.setObject(1, eventId); ps.setObject(2, player); ps.setObject(3, device); ps.setObject(4, grantId); ps.setObject(5, player); ps.executeUpdate() }
        return Checked(grantId, expires)
    }

    // --- words ----------------------------------------------------------------------------------------------------

    public fun json(v: View): String {
        val q = thro.api.http.Contract::q
        fun t(i: Instant?) = i?.let { "\"$it\"" } ?: "null"
        val spots = v.capacity?.let { (it - v.entries).coerceAtLeast(0) }
        return """{"eventId":"${v.eventId}","name":${q(v.name)},"startsAt":"${v.startsAt}","sessionEndsAt":"${v.sessionEndsAt}",""" +
            """"venueId":${v.venueId?.let { "\"$it\"" } ?: "null"},"venue":${v.venue?.let(q) ?: "null"},"locality":${v.locality?.let(q) ?: "null"},"venueLabel":${v.venueLabel?.let(q) ?: "null"},""" +
            """"entrantKind":${q(v.entrantKind)},"access":${q(v.access)},"state":${q(v.state)},"entriesCloseAt":${t(v.entriesCloseAt)},"capacity":${v.capacity ?: "null"},""" +
            """"entries":${v.entries},"spotsRemaining":${spots ?: "null"},"you":${v.you?.let { """{"entered":${it.entered},"checkedIn":${it.checkedIn}}""" } ?: "null"},""" +
            """"draw":[${v.ties.joinToString(",") { tie ->
                """{"tieId":"${tie.tieId}","round":${tie.round},"position":${tie.position},"homeId":"${tie.homeId}","home":${tie.home?.let(q) ?: "null"},""" +
                    """"awayId":${tie.awayId?.let { "\"$it\"" } ?: "null"},"away":${tie.away?.let(q) ?: "null"},"isBye":${tie.isBye},"matchId":${tie.matchId?.let { "\"$it\"" } ?: "null"},""" +
                    """"winnerId":${(if (tie.isBye) tie.homeId else tie.winnerId)?.let { "\"$it\"" } ?: "null"},"outcome":${(tie.outcome ?: if (tie.isBye) "bye" else null)?.let(q) ?: "null"},"note":${tie.note?.let(q) ?: "null"}}"""
            }}],"winnerId":${champion(v)?.let { "\"$it\"" } ?: "null"}}"""
    }

    /** The event's winner: the one decided tie of its last round, once the event is complete. */
    private fun champion(v: View): UUID? {
        if (v.state != "complete" || v.ties.isEmpty()) return null
        val last = v.ties.maxOf { it.round }
        return v.ties.filter { it.round == last }.singleOrNull()?.let { if (it.isBye) it.homeId else it.winnerId }
    }

    public fun json(mine: List<Mine>): String {
        val q = thro.api.http.Contract::q
        return """{"events":[${mine.joinToString(",") { """{"eventId":"${it.eventId}","name":${q(it.name)},"startsAt":"${it.startsAt}","state":${q(it.state)},"entries":${it.entries}}""" }}]}"""
    }

    public fun json(c: Checked): String = """{"grantId":"${c.grantId}","expiresAt":"${c.expiresAt}"}"""
}
