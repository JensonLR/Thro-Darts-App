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
     */
    public fun inPlay(seasonId: UUID, limit: Int = 20): List<Panel> {
        val out = mutableListOf<Panel>()
        connection.prepareStatement(SQL).use { ps ->
            ps.setObject(1, seasonId)
            ps.setInt(2, limit)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    out += Panel(
                        matchId = rs.getObject("match_id") as UUID,
                        homeTeam = rs.getString("home_team"),
                        awayTeam = rs.getString("away_team"),
                        venue = rs.getString("venue"),
                        homeName = rs.getString("home_name"),
                        awayName = rs.getString("away_name"),
                        homeRemaining = rs.getInt("home_remaining"),
                        awayRemaining = rs.getInt("away_remaining"),
                        homeLegs = rs.getInt("home_legs"),
                        awayLegs = rs.getInt("away_legs"),
                        thrower = rs.getString("thrower"),
                        startedAt = rs.getTimestamp("opened_at").toInstant(),
                    )
                }
            }
        }
        return out
    }

    private companion object {
        /**
         * One query, because the alternative is a name-resolution round trip per player and a board that
         * asks twenty questions to draw four rows.
         *
         * The name columns are `CASE WHEN identity.player_may_be_shown_live(...) THEN … END`, so an
         * unnamed player is a SQL NULL and not an empty string: there is no path by which forgetting a
         * check produces a name, only one by which it produces nothing.
         *
         * A private team is still a row (PD-056's reasoning, applied here): hiding the fixture would
         * leave a hole in the night, and its name is simply null.
         */
        const val SQL = """
            WITH live AS (
              SELECT f.match_id, f.venue_id,
                     ht.name AS home_team_name, ht.visibility AS home_vis,
                     at.name AS away_team_name, at.visibility AS away_vis,
                     m.home_id, m.away_id, m.home_name, m.away_name,
                     m.starting_score, m.opened_at
                FROM competition.league_fixture f
                JOIN evidence.match m       ON m.match_id = f.match_id
                JOIN competition.team ht    ON ht.team_id = f.home_team_id
                JOIN competition.team at    ON at.team_id = f.away_team_id
               WHERE f.league_season_id = ?
                 AND f.match_id IS NOT NULL
                 -- Begun: somebody has thrown.
                 AND EXISTS (SELECT 1 FROM read.visit v WHERE v.match_id = f.match_id)
                 -- And not finished: no outcome recorded against the fixture.
                 -- The live outcome, exactly as the tallies define it (V041, V042): unsuperseded.
                 AND NOT EXISTS (
                       SELECT 1 FROM competition.league_fixture_outcome o
                        WHERE o.fixture_id = f.fixture_id
                          AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                                           WHERE s.supersedes_outcome_id = o.outcome_id))
            ),
            latest AS (
              SELECT v.match_id, v.thrower_id, v.remaining_after,
                     row_number() OVER (PARTITION BY v.match_id, v.thrower_id ORDER BY v.leg_ordinal DESC, v.visit_ordinal DESC) AS rn
                FROM read.visit v
                JOIN live l ON l.match_id = v.match_id
               WHERE v.superseded_by IS NULL
            ),
            legs AS (
              SELECT g.match_id, g.winner_id, count(*) AS won
                FROM read.leg g JOIN live l ON l.match_id = g.match_id
               WHERE g.winner_id IS NOT NULL
               GROUP BY g.match_id, g.winner_id
            ),
            -- Whose throw it is, from the visits themselves rather than from a stored pointer: the
            -- projection has no "current thrower" column and inventing one would be a second place for
            -- the truth to live. In the newest leg, whoever has thrown fewer visits is up; level means
            -- the leg's starter. A leg already won has nobody at the oche, and says so with a null.
            current_leg AS (
              SELECT v.match_id, max(v.leg_ordinal) AS leg_ordinal
                FROM read.visit v JOIN live l ON l.match_id = v.match_id
               WHERE v.superseded_by IS NULL
               GROUP BY v.match_id
            ),
            turn AS (
              SELECT cl.match_id,
                     CASE
                       WHEN g.winner_id IS NOT NULL THEN NULL
                       WHEN count(*) FILTER (WHERE v.thrower_id = l.home_id)
                          > count(*) FILTER (WHERE v.thrower_id = l.away_id) THEN 'away'
                       WHEN count(*) FILTER (WHERE v.thrower_id = l.away_id)
                          > count(*) FILTER (WHERE v.thrower_id = l.home_id) THEN 'home'
                       WHEN g.starter_id = l.home_id THEN 'home'
                       ELSE 'away'
                     END AS thrower
                FROM current_leg cl
                JOIN live l ON l.match_id = cl.match_id
                LEFT JOIN read.leg g ON g.match_id = cl.match_id AND g.leg_ordinal = cl.leg_ordinal
                JOIN read.visit v ON v.match_id = cl.match_id AND v.leg_ordinal = cl.leg_ordinal
                                 AND v.superseded_by IS NULL
               GROUP BY cl.match_id, g.winner_id, g.starter_id, l.home_id, l.away_id
            )
            SELECT l.match_id,
                   CASE WHEN l.home_vis = 'public' THEN l.home_team_name END AS home_team,
                   CASE WHEN l.away_vis = 'public' THEN l.away_team_name END AS away_team,
                   ven.name AS venue,
                   CASE WHEN identity.player_may_be_shown_live(l.home_id) THEN l.home_name END AS home_name,
                   CASE WHEN identity.player_may_be_shown_live(l.away_id) THEN l.away_name END AS away_name,
                   coalesce((SELECT remaining_after FROM latest WHERE match_id = l.match_id AND thrower_id = l.home_id AND rn = 1),
                            l.starting_score) AS home_remaining,
                   coalesce((SELECT remaining_after FROM latest WHERE match_id = l.match_id AND thrower_id = l.away_id AND rn = 1),
                            l.starting_score) AS away_remaining,
                   coalesce((SELECT won FROM legs WHERE match_id = l.match_id AND winner_id = l.home_id), 0) AS home_legs,
                   coalesce((SELECT won FROM legs WHERE match_id = l.match_id AND winner_id = l.away_id), 0) AS away_legs,
                   turn.thrower,
                   l.opened_at
              FROM live l
              LEFT JOIN competition.venue ven ON ven.venue_id = l.venue_id AND ven.visibility = 'public'
              LEFT JOIN turn ON turn.match_id = l.match_id
             ORDER BY l.opened_at DESC
             LIMIT ?
        """
    }
}
