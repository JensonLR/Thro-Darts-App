package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID

/**
 * Consent to be named, and what a public screen may therefore show (PD-088).
 *
 * The founder's decision was *"if it's legal all games should be live shown"*, and the whole of the
 * engineering is in the conditional. V045 puts the line in the schema —
 * `identity.player_may_be_shown_live` names adults who have said so themselves, and nobody else. This
 * file is what asks the question and what publishes the answer.
 *
 * **Nothing here ever guesses.** A board that showed a name it was not sure about would be worse than a
 * board with no names, because the room cannot tell the difference between a name THRØ was entitled to
 * show and one it was not.
 */
public class Consent(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public enum class Scope(public val stored: String) {
        /** Being named on a public page: static, and about membership. */
        LISTING("listing"),

        /**
         * Being named on a screen while playing. Asked for separately from listing because it is a
         * different exposure: it publishes where somebody is at the time, not a fact about a season.
         */
        LIVE("live"),
        ;

        public companion object {
            public fun of(s: String?): Scope? = entries.firstOrNull { it.stored == s }
        }
    }

    public data class Answer(val scope: Scope, val given: Boolean, val refusedBecause: String? = null)

    /**
     * The person says yes or no, for themselves.
     *
     * **`self` only, and no route takes a `basis`.** A guardian consent is a real thing the schema
     * supports and it is recorded by a named human being through the secretary, never by a caller
     * asserting it over HTTP — an endpoint that accepted `basis: "guardian"` would be an endpoint that
     * turns an unverified claim into a database row saying a guardian agreed.
     *
     * Withdrawing revokes rather than removes: `revoked_at` is set and the row stays, so *"they said yes
     * in March and no in June"* is answerable. A consent you cannot show the history of is not a consent
     * record, it is a flag.
     */
    public fun say(accountId: UUID, scope: Scope, yes: Boolean): Answer {
        if (!yes) {
            connection.prepareStatement(
                "UPDATE identity.consent_record SET revoked_at = ?, revoked_by = ? " +
                    "WHERE account_id = ? AND scope = ? AND basis = 'self' AND revoked_at IS NULL",
            ).use { ps ->
                ps.setObject(1, java.sql.Timestamp.from(now())); ps.setObject(2, accountId)
                ps.setObject(3, accountId); ps.setString(4, scope.stored); ps.executeUpdate()
            }
            return Answer(scope, given = false)
        }

        // Live is for adults. Refusing here as well as in the gate is deliberate: the gate stops a name
        // reaching a screen, and this stops a record existing that says a child agreed to something
        // THRØ would never act on. The second is the one somebody reads in a subject access request.
        if (scope == Scope.LIVE) {
            val band = connection.prepareStatement("SELECT age_band FROM identity.account WHERE account_id = ?")
                .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { if (it.next()) it.getString(1) else null } }
            if (band != "adult") {
                return Answer(scope, given = false, refusedBecause = WHY_NOT_LIVE)
            }
        }

        connection.prepareStatement(
            "INSERT INTO identity.consent_record (account_id, basis, scope, given_by, artefact_ref) " +
                "VALUES (?, 'self', ?, ?, 'asked_in_the_app') ON CONFLICT DO NOTHING",
        ).use { ps ->
            ps.setObject(1, accountId); ps.setString(2, scope.stored); ps.setObject(3, accountId)
            ps.executeUpdate()
        }
        return Answer(scope, given = true)
    }

    /** What this account has agreed to right now, so a settings screen can show it rather than assume. */
    public fun given(accountId: UUID): Set<Scope> {
        val out = mutableSetOf<Scope>()
        connection.prepareStatement(
            "SELECT scope FROM identity.consent_record " +
                "WHERE account_id = ? AND basis = 'self' AND revoked_at IS NULL",
        ).use { ps ->
            ps.setObject(1, accountId)
            ps.executeQuery().use { rs -> while (rs.next()) Scope.of(rs.getString(1))?.let(out::add) }
        }
        return out
    }

    public companion object {
        /**
         * Said to the person, not logged. Somebody under 18 who presses this is entitled to know it is a
         * rule about age rather than a fault of theirs, and entitled to know it will change.
         */
        public const val WHY_NOT_LIVE: String =
            "A live screen can be seen by anyone in the room, so THRØ only names players who are 18 " +
                "or over and have said yes. Your results are published the same as everybody else's."
    }
}

/**
 * What a public screen may show of a league night.
 *
 * **Teams always, people sometimes.** Every row here names the two teams, because a league's own
 * published competition is public and that is the whole of PD-054. Whether a *person* is named is asked
 * per player, of the schema, every time — never cached, because consent is withdrawable and a board that
 * held yesterday's answer would keep showing somebody who has since said no.
 */
public class LiveBoard(private val connection: Connection) {

    /** One match in play, as a public screen may have it. */
    public data class Panel(
        val matchId: UUID,
        val homeTeam: String?,
        val awayTeam: String?,
        val venue: String?,
        /** The player's name where THRØ may show it, and null where it may not. Never a placeholder. */
        val homeName: String?,
        val awayName: String?,
        val homeRemaining: Int,
        val awayRemaining: Int,
        val homeLegs: Int,
        val awayLegs: Int,
        /** "home", "away", or null between legs and once it is over. */
        val thrower: String?,
        val startedAt: Instant,
    ) {
        /** True when neither player may be named — the board still has a game, played by two teams. */
        public val teamsOnly: Boolean get() = homeName == null && awayName == null
    }

    /**
     * Every match in this season that has begun and has not finished.
     *
     * "Begun" is *a visit exists*, not *a fixture's kick-off time has passed* — a fixture nobody turned
     * up to is not a live game, and putting it on a wall with two dashes on it would be the screen
     * asserting something it does not know.
     *
     * **Where the scores come from.** Each match is replayed through the engine from its evidence, the
     * same replay a match record uses. The board used to read `read.visit` and `read.leg`, projections
     * nothing in production has ever written — and its query also named two columns V018 had removed, so
     * it failed before reaching them. Between the two, no season's screen ever drew a game. Replaying the
     * evidence costs one read per match, at most twenty, and it is right by construction: a leg that has
     * just ended shows the new leg's starting scores, a visit entered as darts replays as darts, and a
     * league that keeps the darts before a bust has its own rule applied (OD-023).
     *
     * **"Not finished"** is three things now, where it was one: no result recorded against the fixture,
     * the match not won and not ended short, and something thrown in the last [QUIET_AFTER]. The second
     * and third are what a pub screen needs and the first alone missed: a match that was finished, or
     * put down and never ended, stayed "playing now" until a secretary entered the result, which could
     * be days.
     */
    public fun inPlay(seasonId: UUID, limit: Int = 20): List<Panel> {
        class Row(
            val match: UUID, val homeTeam: String?, val awayTeam: String?, val venue: String?,
            val homeName: String?, val awayName: String?, val openedAt: Instant,
        )
        val rows = mutableListOf<Row>()
        connection.prepareStatement(SQL).use { ps ->
            ps.setObject(1, seasonId)
            ps.setLong(2, QUIET_AFTER.seconds)
            ps.setInt(3, limit)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    rows += Row(
                        match = rs.getObject("match_id") as UUID,
                        homeTeam = rs.getString("home_team"),
                        awayTeam = rs.getString("away_team"),
                        venue = rs.getString("venue"),
                        homeName = rs.getString("home_name"),
                        awayName = rs.getString("away_name"),
                        openedAt = rs.getTimestamp("opened_at").toInstant(),
                    )
                }
            }
        }
        val records = MatchRecords(connection)
        return rows.mapNotNull { row ->
            val replayed = records.replay(row.match) ?: return@mapNotNull null
            if (replayed.state.isComplete || replayed.ending != null) return@mapNotNull null
            val state = replayed.state
            Panel(
                matchId = row.match,
                homeTeam = row.homeTeam,
                awayTeam = row.awayTeam,
                venue = row.venue,
                homeName = row.homeName,
                awayName = row.awayName,
                homeRemaining = state.remaining[Seat.home] ?: state.format.startingScore,
                awayRemaining = state.remaining[Seat.away] ?: state.format.startingScore,
                homeLegs = state.legsWonTotal[Seat.home] ?: 0,
                awayLegs = state.legsWonTotal[Seat.away] ?: 0,
                thrower = state.thrower?.value,
                startedAt = row.openedAt,
            )
        }
    }

    public companion object {
        /**
         * How long a match may go without a dart before a public screen stops calling it live. A league
         * night has gaps between legs and between games; it does not have three-hour ones. A match put down
         * and never ended is a thing that happened, not a game in play.
         */
        public val QUIET_AFTER: java.time.Duration = java.time.Duration.ofHours(3)

        /**
         * The fixtures in play, as the read role may see them. Scores are NOT here — see [inPlay].
         *
         * Names are asked of `identity.live_name` (V060), which answers only where the player has said a
         * live screen may show them. The read role cannot see a column of `identity`, and does not need to.
         */
        internal const val SQL: String = """
            SELECT f.match_id,
                   CASE WHEN ht.visibility = 'public' THEN ht.name END AS home_team,
                   CASE WHEN at.visibility = 'public' THEN at.name END AS away_team,
                   ven.name AS venue,
                   identity.live_name(m.home_id) AS home_name,
                   identity.live_name(m.away_id) AS away_name,
                   m.opened_at
              FROM competition.league_fixture f
              JOIN evidence.match m       ON m.match_id = f.match_id
              JOIN competition.team ht    ON ht.team_id = f.home_team_id
              JOIN competition.team at    ON at.team_id = f.away_team_id
              LEFT JOIN competition.venue ven ON ven.venue_id = f.venue_id AND ven.visibility = 'public'
             WHERE f.league_season_id = ?
               AND f.match_id IS NOT NULL
               -- Begun, and not gone quiet: a dart thrown, and one thrown recently, by the server's clock.
               AND (SELECT max(e.received_at) FROM evidence.event e
                     WHERE e.match_id = f.match_id AND e.event_type = 'VisitRecorded')
                   > clock_timestamp() - make_interval(secs => ?)
               -- And no result recorded against the fixture: the live outcome, exactly as the tallies define
               -- it (V041, V042) — unsuperseded.
               AND NOT EXISTS (
                     SELECT 1 FROM competition.league_fixture_outcome o
                      WHERE o.fixture_id = f.fixture_id
                        AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                                         WHERE s.supersedes_outcome_id = o.outcome_id))
             ORDER BY m.opened_at DESC
             LIMIT ?
        """
    }
}
