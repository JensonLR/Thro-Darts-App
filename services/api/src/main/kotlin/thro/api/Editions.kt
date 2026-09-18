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
                          val winnerId: UUID? = null, val outcome: String? = null, val note: String? = null, val board: String? = null)
    public data class You(val entered: Boolean, val checkedIn: Boolean)
    /** [playerId] is the competitor's id whatever its kind — kept under that key for the phone and the web that read it. */
    public data class Entrant(val playerId: UUID, val name: String?, val checkedIn: Boolean, val seed: Int?, val kind: String = "player")
    public data class View(
        val eventId: UUID, val name: String, val startsAt: Instant, val sessionEndsAt: Instant, val venueId: UUID?, val venue: String?, val locality: String?,
        val venueLabel: String?, val entrantKind: String, val access: String, val state: String, val entriesCloseAt: Instant?, val capacity: Int?,
        val entries: Int, val you: You?, val ties: List<Tie>,
        /** Who is entered — for the organiser only; the public page counts and names nobody before the draw. */
        val entrants: List<Entrant>? = null,
    )

    private fun row(eventId: UUID, viewer: UUID?): View? = connection.prepareStatement(
        """SELECT e.name, e.starts_at, e.session_ends_at, v.venue_id, v.name, v.locality, e.venue_label, e.entrant_kind, e.access, e.state,
                  e.entries_close_at, e.capacity,
                  (SELECT count(*) FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL),
                  (SELECT count(*) FROM competition.entry en WHERE en.event_id = e.event_id AND en.withdrawn_at IS NULL
                     AND (en.player_id = ? OR en.pair_id IN (SELECT pair_id FROM competition.pair WHERE player_a = ? OR player_b = ?)
                          OR en.team_id IN (SELECT team_id FROM competition.team_membership WHERE player_id = ? AND valid_until IS NULL AND status = 'active'))),
                  (SELECT count(*) FROM competition.check_in ci JOIN competition.entry en ON en.event_id = ci.event_id AND en.competitor_id = ci.competitor_id AND en.withdrawn_at IS NULL
                    WHERE ci.event_id = e.event_id AND (ci.player_id = ? OR en.pair_id IN (SELECT pair_id FROM competition.pair WHERE player_a = ? OR player_b = ?)
                          OR en.team_id IN (SELECT team_id FROM competition.team_membership WHERE player_id = ? AND valid_until IS NULL AND status = 'active')))
             FROM competition.event e LEFT JOIN competition.venue v ON v.venue_id = e.venue_id AND v.visibility = 'public'
            WHERE e.event_id = ?""",
    ).use { ps ->
        for (i in 1..8) ps.setObject(i, viewer)
        ps.setObject(9, eventId)
        ps.executeQuery().use { rs ->
            if (!rs.next()) null
            else View(
                eventId, rs.getString(1), rs.getTimestamp(2).toInstant(), rs.getTimestamp(3).toInstant(), rs.getObject(4) as UUID?, rs.getString(5), rs.getString(6),
                rs.getString(7), rs.getString(8), rs.getString(9), rs.getString(10), rs.getTimestamp(11)?.toInstant(), rs.getObject(12) as Int?,
                rs.getInt(13), viewer?.let { You(rs.getInt(14) > 0, rs.getInt(15) > 0) }, emptyList(),
            )
        }
    }

    /**
     * A competitor's name, whatever it is: a player where THRØ may name them, a pair as "A & B" (each half where THRØ
     * may name them), a team by its name. The one SQL for the three, so no page names somebody another page hides.
     */
    private val placeholderLit = "'" + Accounts.PLACEHOLDER_NAME.replace("'", "''") + "'"
    private val competitorName = """(
        SELECT coalesce(
          (SELECT tm.name FROM competition.team tm WHERE tm.team_id = %s),
          -- The two halves in the order they were typed (PD-133), not the order their ids sort in. `typed_first`
          -- is null on a pair made before V057, and those read in the normalised order as they always did.
          (SELECT concat_ws(' & ',
                    coalesce((SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> $placeholderLit THEN a.display_name END
                                FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                               WHERE c.player_id = h.first_id AND c.revoked_at IS NULL),
                             -- A walk-up half of a pair (PD-130), named exactly as a walk-up alone is.
                             (SELECT CASE WHEN g.name IS NOT NULL AND (g.may_be_named OR %o) THEN g.name ELSE 'A guest' END FROM competition.guest g WHERE g.player_id = h.first_id),
                             'A player'),
                    coalesce((SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> $placeholderLit THEN a.display_name END
                                FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                               WHERE c.player_id = h.second_id AND c.revoked_at IS NULL),
                             (SELECT CASE WHEN g.name IS NOT NULL AND (g.may_be_named OR %o) THEN g.name ELSE 'A guest' END FROM competition.guest g WHERE g.player_id = h.second_id),
                             'A player'))
             FROM competition.pair pr
             CROSS JOIN LATERAL (SELECT CASE WHEN pr.typed_first = pr.player_b THEN pr.player_b ELSE pr.player_a END AS first_id,
                                        CASE WHEN pr.typed_first = pr.player_b THEN pr.player_a ELSE pr.player_b END AS second_id) h
            WHERE pr.pair_id = %s),
          (SELECT CASE WHEN identity.player_may_be_disclosed(c.player_id) AND a.display_name <> $placeholderLit THEN a.display_name END
             FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
            WHERE c.player_id = %s AND c.revoked_at IS NULL),
          -- A walk-up (PD-124): the name the organiser typed, for the organiser; for anybody else only where the organiser
          -- said this adult is happy to be on the draw; and "A guest" once the name is forgotten.
          (SELECT CASE WHEN g.name IS NOT NULL AND (g.may_be_named OR %o) THEN g.name ELSE 'A guest' END
             FROM competition.guest g WHERE g.player_id = %s)))""".replace("\$placeholderLit", "'" + Accounts.PLACEHOLDER_NAME.replace("'", "''") + "'")
    private fun nameOf(column: String, forOrganiser: Boolean = false) = competitorName.replace("%s", column).replace("%o", if (forOrganiser) "true" else "false")

    private fun ties(eventId: UUID, forOrganiser: Boolean = false): List<Tie> = connection.prepareStatement(
        """SELECT t.fixture_id, t.round_number, t.position, t.home_id, t.away_id, t.is_bye, t.match_id, t.winner_id, t.outcome, t.note,
                  ${nameOf("t.home_id", forOrganiser)}, ${nameOf("t.away_id", forOrganiser)}, b.label
             FROM competition.bracket_tie t LEFT JOIN competition.board b ON b.board_id = t.board_id
            WHERE t.event_id = ? ORDER BY t.round_number, t.position""",
    ).use { ps ->
        ps.setObject(1, eventId)
        ps.executeQuery().use { rs ->
            generateSequence {
                if (!rs.next()) null
                else Tie(rs.getObject(1) as UUID, rs.getInt(2), rs.getInt(3), rs.getObject(4) as UUID, rs.getString(11), rs.getObject(5) as UUID?, rs.getString(12), rs.getBoolean(6), rs.getObject(7) as UUID?,
                         rs.getObject(8) as UUID?, rs.getString(9), rs.getString(10), rs.getString(13))
            }.toList()
        }
    }

    private fun entrants(eventId: UUID): List<Entrant> = connection.prepareStatement(
        // A walk-up is there, or the organiser could not have typed their name: present, and of the kind "guest".
        """SELECT en.competitor_id, en.seed,
                  EXISTS (SELECT 1 FROM competition.check_in ci WHERE ci.event_id = en.event_id AND ci.competitor_id = en.competitor_id)
                    OR EXISTS (SELECT 1 FROM competition.guest g WHERE g.player_id = en.competitor_id)
                    -- A pair with a walk-up in it (PD-130) is here for the same reason.
                    OR EXISTS (SELECT 1 FROM competition.pair pr JOIN competition.guest g ON g.player_id IN (pr.player_a, pr.player_b) WHERE pr.pair_id = en.competitor_id),
                  ${nameOf("en.competitor_id", forOrganiser = true)},
                  CASE WHEN EXISTS (SELECT 1 FROM competition.guest g WHERE g.player_id = en.competitor_id) THEN 'guest' ELSE en.entrant_kind END
             FROM competition.entry en WHERE en.event_id = ? AND en.withdrawn_at IS NULL ORDER BY en.seed NULLS LAST, en.entered_at""",
    ).use { ps ->
        ps.setObject(1, eventId)
        ps.executeQuery().use { rs -> generateSequence { if (!rs.next()) null else Entrant(rs.getObject(1) as UUID, rs.getString(4), rs.getBoolean(3), rs.getObject(2) as Int?, rs.getString(5)) }.toList() }
    }

    /** The event's page: for anybody; `you` only with a session; the entrants only for whoever runs it. */
    public fun view(eventId: UUID, viewer: UUID?): View {
        val v = row(eventId, viewer) ?: throw Refused("THRØ has no such event.", 404)
        val organiser = viewer != null && runs(viewer, eventId)
        val withTies = if (v.state in setOf("drawn", "in_progress", "complete")) v.copy(ties = ties(eventId, organiser)) else v
        return if (organiser) withTies.copy(entrants = entrants(eventId)) else withTies
    }

    // --- the organiser --------------------------------------------------------------------------------------------

    public fun open(by: UUID, name: String, startsAt: Instant, sessionEndsAt: Instant, venueId: UUID?, venueLabel: String?, entriesCloseAt: Instant?, capacity: Int?, access: String = "open", entrantKind: String = "player"): View {
        val title = name.trim()
        val entrants = when (entrantKind) { "player" -> thro.competition.EntrantKind.PLAYER; "pair" -> thro.competition.EntrantKind.PAIR; "team" -> thro.competition.EntrantKind.TEAM
            else -> throw Refused("An event is entered by players, pairs or teams; '$entrantKind' is none of those.", 400) }
        val kind = when (access) { "open" -> thro.competition.EventAccess.OPEN; "invitational" -> thro.competition.EventAccess.INVITATIONAL
            else -> throw Refused("THRØ runs open and invitational events; '$access' is neither.", 400) }
        if (title.length !in 2..80) throw Refused("An event has a name, two to eighty characters.", 400)
        if (!sessionEndsAt.isAfter(startsAt)) throw Refused("The session ends after it starts.", 400)
        if (!startsAt.isAfter(now())) throw Refused("The event starts in the future.", 400)
        if (entriesCloseAt != null && entriesCloseAt.isAfter(startsAt)) throw Refused("Entries close before the event starts.", 400)
        if (capacity != null && capacity < 2) throw Refused("A knockout has at least two places.", 400)
        if (venueId != null && !connection.prepareStatement("SELECT 1 FROM competition.venue WHERE venue_id = ?").use { ps -> ps.setObject(1, venueId); ps.executeQuery().use { it.next() } }) {
            throw Refused("THRØ has no such venue.", 400)
        }
        val id = UUID.randomUUID()
        Competitions(connection).openEvent(id, title, startsAt, sessionEndsAt, venueLabel?.trim()?.takeIf { it.isNotEmpty() }, venueId, entrantKind = entrants, access = kind, entriesCloseAt = entriesCloseAt, capacity = capacity)
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

    /**
     * Entering, in the event's own kind. A player enters themselves (open events) or the organiser enters one by id;
     * a pair is a player with a partner, or the organiser's two ids — both stand entered, and neither may be in
     * another pair here; a team is entered by whoever runs it, or the organiser, and every active member stands entered.
     */
    public fun enter(eventId: UUID, player: UUID, by: UUID = player, partner: UUID? = null, pairIds: List<UUID>? = null, teamId: UUID? = null): View {
        val v = view(eventId, by)
        val organiser = runs(by, eventId)
        if (v.state != "open") throw Refused("Entries are closed.", 409)
        if (!organiser && v.entriesCloseAt != null && !now().isBefore(v.entriesCloseAt)) throw Refused("Entries closed at ${v.entriesCloseAt}.", 409)
        if (v.capacity != null && v.entries >= v.capacity) throw Refused("This event is full: ${v.capacity} places, all taken.", 409)
        fun revive(competitor: UUID): Boolean = connection.prepareStatement("UPDATE competition.entry SET withdrawn_at = NULL, entered_at = clock_timestamp() WHERE event_id = ? AND competitor_id = ? AND withdrawn_at IS NOT NULL")
            .use { ps -> ps.setObject(1, eventId); ps.setObject(2, competitor); ps.executeUpdate() } > 0
        val comp = Competitions(connection)
        when (v.entrantKind) {
            "player" -> {
                if (partner != null || pairIds != null || teamId != null) throw Refused("This event is entered by single players.", 400)
                if (by != player) {
                    if (!organiser) throw Refused("Only the event's organiser enters somebody else.", 403)
                    if (!playerExists(player)) throw Refused("THRØ has no such player.", 404)
                } else if (v.access != "open") throw Refused("This event is ${v.access.replace('_', ' ')}: entry is by the organiser.", 403)
                if (v.you?.entered == true && by == player) throw Refused("You are already entered.", 409)
                if (isEntered(eventId, player)) throw Refused("That player is already entered.", 409)
                if (!revive(player)) comp.enter(eventId, player)
            }
            "pair" -> {
                val two = when {
                    pairIds != null -> { if (!organiser) throw Refused("Only the event's organiser enters a pair by ids.", 403); pairIds }
                    partner != null -> { if (v.access != "open") throw Refused("This event is ${v.access.replace('_', ' ')}: entry is by the organiser.", 403); listOf(player, partner) }
                    else -> throw Refused("A pair event is entered with a partner: name them.", 400)
                }
                if (two.size != 2 || two[0] == two[1]) throw Refused("A pair is two different players.", 400)
                if (!two.all { playerExists(it) }) throw Refused("THRØ has no such player.", 404)
                if (two.any { isEntered(eventId, it) }) throw Refused("One of them is already in a pair here.", 409)
                val pairId = connection.prepareStatement("SELECT pair_id FROM competition.pair WHERE player_a = least(?::uuid, ?::uuid) AND player_b = greatest(?::uuid, ?::uuid)")
                    .use { ps -> ps.setObject(1, two[0]); ps.setObject(2, two[1]); ps.setObject(3, two[0]); ps.setObject(4, two[1]); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }
                    ?: Organisations(connection).createPair(two[0], two[1])
                if (!revive(pairId)) comp.enter(eventId, thro.competition.Entrant.Pair(pairId.toString(), two[0].toString(), two[1].toString()))
            }
            "team" -> {
                val team = teamId ?: throw Refused("A team event is entered by a team: name it.", 400)
                if (!organiser && !rel.decide(by, "team.manage", ObjectRef(ObjectType.TEAM, team.toString())).allowed) throw Refused("Only whoever runs the team enters it.", 403)
                if (!connection.prepareStatement("SELECT 1 FROM competition.team WHERE team_id = ? AND dissolved_at IS NULL").use { ps -> ps.setObject(1, team); ps.executeQuery().use { it.next() } }) throw Refused("THRØ has no such team.", 404)
                if (isEntered(eventId, team)) throw Refused("That team is already entered.", 409)
                if (!revive(team)) comp.enter(eventId, thro.competition.Entrant.Team(team.toString()))
            }
        }
        return view(eventId, by)
    }

    /**
     * A walk-up (PD-124): somebody in the pub with no account, added by the organiser by name. A player like any other
     * in the draw; decided by hand, because nobody scores for them on THRØ. [mayBeNamed] is the organiser's word that
     * this is an adult who is happy to be named on the public draw; without it the name is the organiser's alone.
     */
    public fun enterGuest(eventId: UUID, name: String, mayBeNamed: Boolean, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser adds a walk-up.", 403)
        if (v.entrantKind != "player") throw Refused(
            if (v.entrantKind == "pair") "A pairs night takes a walk-up with a partner: two names, or a name and somebody on THRØ."
            else "A walk-up is one name, and this event is entered by teams. Walk-ups are for singles and pairs nights.", 400)
        roomFor(v)
        together { Competitions(connection).enter(eventId, guestPlayer(eventId, name, mayBeNamed, by)) }
        return view(eventId, by)
    }

    /**
     * A pair with a walk-up in it (PD-130), which is most pairs on a blind-draw night: two names, or one name and a
     * partner who is on THRØ. Each walk-up is a guest exactly as on a singles night — the organiser's to see, public
     * only where the organiser says so, forgotten thirty days on — and the pair is a pair like any other in the draw.
     */
    public fun enterGuestPair(eventId: UUID, names: List<String>, partner: UUID?, mayBeNamed: Boolean, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser adds a walk-up.", 403)
        if (v.entrantKind != "pair") throw Refused("Two names are a pair, and this event is entered by ${v.entrantKind}s.", 400)
        val wanted = if (partner == null) 2 else 1
        if (names.size != wanted) throw Refused("A pair is two: two names, or one name and a partner on THRØ.", 400)
        if (names.map { it.trim().lowercase() }.distinct().size != names.size) throw Refused("A pair is two different people: tell them apart.", 400)
        roomFor(v)
        if (partner != null) {
            if (!playerExists(partner)) throw Refused("THRØ has no such player.", 404)
            if (isEntered(eventId, partner)) throw Refused("They are already in a pair here.", 409)
        }
        // All of it or none: a pair refused for its second name must not leave its first on the night as a stray walk-up.
        together {
            val two = names.map { guestPlayer(eventId, it, mayBeNamed, by) } + listOfNotNull(partner)
            val pairId = Organisations(connection).createPair(two[0], two[1])
            Competitions(connection).enter(eventId, thro.competition.Entrant.Pair(pairId.toString(), two[0].toString(), two[1].toString()))
        }
        return view(eventId, by)
    }

    private fun <T> together(block: () -> T): T {
        if (!connection.autoCommit) return block()   // already inside somebody's transaction: theirs to end
        connection.autoCommit = false
        try { val out = block(); connection.commit(); return out }
        catch (e: Exception) { connection.rollback(); throw e }
        finally { connection.autoCommit = true }
    }

    private fun playerExists(id: UUID) = connection.prepareStatement("SELECT 1 FROM competition.player WHERE player_id = ?").use { ps -> ps.setObject(1, id); ps.executeQuery().use { it.next() } }

    private fun roomFor(v: View) {
        if (v.state != "open") throw Refused("Entries are closed.", 409)
        if (v.capacity != null && v.entries >= v.capacity) throw Refused("This event is full: ${v.capacity} places, all taken.", 409)
    }

    /** A walk-up's player and guest row: the name checked, told apart from the night's others, and kept for thirty days. */
    private fun guestPlayer(eventId: UUID, name: String, mayBeNamed: Boolean, by: UUID): UUID {
        val clean = name.trim()
        if (clean.isEmpty() || clean.codePointCount(0, clean.length) > 60) throw Refused("A walk-up's name is 1 to 60 characters.", 400)
        if (clean.any { it.isISOControl() || it.category == CharCategory.FORMAT }) throw Refused("A name has no control or formatting characters.", 400)
        val taken = connection.prepareStatement("SELECT 1 FROM competition.guest WHERE event_id = ? AND lower(btrim(name)) = lower(?)")
            .use { ps -> ps.setObject(1, eventId); ps.setString(2, clean); ps.executeQuery().use { it.next() } }
        if (taken) throw Refused("There is already a $clean on this night. Add something that tells them apart.", 409)
        val player = Organisations(connection).createPlayer("organiser", by)
        connection.prepareStatement("INSERT INTO competition.guest (player_id, event_id, name, may_be_named, added_by, added_at) VALUES (?, ?, ?, ?, ?, ?)").use { ps ->
            ps.setObject(1, player); ps.setObject(2, eventId); ps.setString(3, clean); ps.setBoolean(4, mayBeNamed); ps.setObject(5, by)
            ps.setTimestamp(6, java.sql.Timestamp.from(now())); ps.executeUpdate()
        }
        return player
    }

    private fun isEntered(eventId: UUID, id: UUID): Boolean = connection.prepareStatement(
        """SELECT 1 FROM competition.entry en WHERE en.event_id = ? AND en.withdrawn_at IS NULL
            AND (en.competitor_id = ? OR en.pair_id IN (SELECT pair_id FROM competition.pair WHERE player_a = ? OR player_b = ?))""",
    ).use { ps -> ps.setObject(1, eventId); ps.setObject(2, id); ps.setObject(3, id); ps.setObject(4, id); ps.executeQuery().use { it.next() } }

    /** The entry a person stands in: their own, their pair's, or a team's they are a member of. */
    private fun entryOf(eventId: UUID, player: UUID): Pair<UUID, String>? = connection.prepareStatement(
        """SELECT en.competitor_id, en.entrant_kind FROM competition.entry en WHERE en.event_id = ? AND en.withdrawn_at IS NULL
            AND (en.player_id = ? OR en.pair_id IN (SELECT pair_id FROM competition.pair WHERE player_a = ? OR player_b = ?)
                 OR en.team_id IN (SELECT team_id FROM competition.team_membership WHERE player_id = ? AND valid_until IS NULL AND status = 'active'))
            LIMIT 1""",
    ).use { ps -> for (i in 2..5) ps.setObject(i, player); ps.setObject(1, eventId); ps.executeQuery().use { rs -> if (rs.next()) (rs.getObject(1) as UUID) to rs.getString(2) else null } }

    /** The organiser's seed on an entry, unique in the event, before the draw. */
    public fun seed(eventId: UUID, competitor: UUID, seed: Int?, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser seeds it.", 403)
        if (seed != null && seed < 1) throw Refused("A seed is a positive number.", 400)
        if (v.state !in setOf("open", "entries_closed")) throw Refused("The draw is made; seeds are not changed after it.", 409)
        val n = try {
            connection.prepareStatement("UPDATE competition.entry SET seed = ? WHERE event_id = ? AND competitor_id = ? AND withdrawn_at IS NULL")
                .use { ps -> if (seed == null) ps.setNull(1, java.sql.Types.INTEGER) else ps.setInt(1, seed); ps.setObject(2, eventId); ps.setObject(3, competitor); ps.executeUpdate() }
        } catch (e: org.postgresql.util.PSQLException) { throw Refused("Another entrant already has seed $seed.", 409) }
        if (n == 0) throw Refused("That entrant is not in this event.", 404)
        return view(eventId, by)
    }

    /** The organiser names the boards; a tie is sent to one. */
    public fun boards(eventId: UUID, labels: List<String>, by: UUID): List<String> {
        view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser names the boards.", 403)
        val clean = labels.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        if (clean.isEmpty()) throw Refused("Name at least one board.", 400)
        connection.prepareStatement("INSERT INTO competition.board (board_id, event_id, label) VALUES (?, ?, ?) ON CONFLICT (event_id, label) DO NOTHING").use { ps ->
            for (label in clean) { ps.setObject(1, UUID.randomUUID()); ps.setObject(2, eventId); ps.setString(3, label.take(40)); ps.addBatch() }
            ps.executeBatch()
        }
        return boardLabels(eventId)
    }

    public fun boardLabels(eventId: UUID): List<String> = connection.prepareStatement("SELECT label FROM competition.board WHERE event_id = ? ORDER BY label")
        .use { ps -> ps.setObject(1, eventId); ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getString(1) else null }.toList() } }

    public fun sendToBoard(eventId: UUID, tieId: UUID, label: String, by: UUID): View {
        view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser sends a tie to a board.", 403)
        val board = connection.prepareStatement("SELECT board_id FROM competition.board WHERE event_id = ? AND label = ?")
            .use { ps -> ps.setObject(1, eventId); ps.setString(2, label.trim()); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }
            ?: throw Refused("This event has no board called ${label.trim()}.", 404)
        val n = connection.prepareStatement("UPDATE competition.bracket_tie SET board_id = ? WHERE fixture_id = ? AND event_id = ?")
            .use { ps -> ps.setObject(1, board); ps.setObject(2, tieId); ps.setObject(3, eventId); ps.executeUpdate() }
        if (n == 0) throw Refused("THRØ has no such tie in this event.", 404)
        return view(eventId, by)
    }

    /** The organiser takes an entry out, before the draw. The row is kept with the time, as a withdrawal is. */
    public fun remove(eventId: UUID, player: UUID, by: UUID): View {
        val v = view(eventId, by)
        if (!runs(by, eventId)) throw Refused("Only the event's organiser removes an entry.", 403)
        if (v.state !in setOf("open", "entries_closed")) throw Refused("The draw is made; a player in it is not removed, they are decided against.", 409)
        val n = connection.prepareStatement("UPDATE competition.entry SET withdrawn_at = clock_timestamp() WHERE event_id = ? AND player_id = ? AND withdrawn_at IS NULL")
            .use { ps -> ps.setObject(1, eventId); ps.setObject(2, player); ps.executeUpdate() }
        if (n == 0) throw Refused("That player is not entered.", 409)
        return view(eventId, by)
    }

    public fun withdraw(eventId: UUID, player: UUID): View {
        val v = view(eventId, player)
        if (v.state !in setOf("open", "entries_closed")) throw Refused("The draw is made; withdrawing now is for the organiser to record.", 409)
        val (competitor, kind) = entryOf(eventId, player) ?: throw Refused("You are not entered.", 409)
        if (kind == "team" && !rel.decide(player, "team.manage", ObjectRef(ObjectType.TEAM, competitor.toString())).allowed) throw Refused("Only whoever runs the team withdraws it.", 403)
        val n = connection.prepareStatement("UPDATE competition.entry SET withdrawn_at = clock_timestamp() WHERE event_id = ? AND competitor_id = ? AND withdrawn_at IS NULL")
            .use { ps -> ps.setObject(1, eventId); ps.setObject(2, competitor); ps.executeUpdate() }
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
        val (competitor, _) = entryOf(eventId, player) ?: throw Refused("Only an entrant checks in.", 409)
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
        ).use { ps -> ps.setObject(1, eventId); ps.setObject(2, competitor); ps.setObject(3, device); ps.setObject(4, grantId); ps.setObject(5, player); ps.executeUpdate() }
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
                    """"winnerId":${(if (tie.isBye) tie.homeId else tie.winnerId)?.let { "\"$it\"" } ?: "null"},"outcome":${(tie.outcome ?: if (tie.isBye) "bye" else null)?.let(q) ?: "null"},"note":${tie.note?.let(q) ?: "null"},"board":${tie.board?.let(q) ?: "null"}}"""
            }}],"winnerId":${champion(v)?.let { "\"$it\"" } ?: "null"},"entrants":${v.entrants?.let { list ->
                "[" + list.joinToString(",") { """{"playerId":"${it.playerId}","name":${it.name?.let(q) ?: "null"},"checkedIn":${it.checkedIn},"seed":${it.seed ?: "null"},"kind":${q(it.kind)}}""" } + "]"
            } ?: "null"},"boards":[${boardLabels(v.eventId).joinToString(",") { q(it) }}]}"""
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
