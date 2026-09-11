package thro.api

import java.sql.Types

import java.net.URI

import java.math.BigDecimal

import java.io.File
import java.sql.Connection
import java.sql.Date
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * The league import (PD-033): the organisational graph of real local leagues, read from a seed
 * file that `tools/pull_leaguerepublic.py` writes from the leagues' own public pages, with the
 * provenance of every row carried into `competition.source_record` (V027).
 *
 * **What it writes and what it never writes.** Leagues, seasons, divisions, teams, venues, the
 * team–season affiliations and the team–venue home tenures. No person: the seed file carries none
 * and this importer has no code path that could insert one. A player joins a team by claiming,
 * with consent, never by import.
 *
 * **Idempotent by natural key, not by wiping.** A second run against the same database inserts
 * nothing and changes nothing: a league is found by name, a season by (league, label), a division
 * by (season, name), a venue by its OpenStreetMap element, a team by name-and-venue (the same
 * organisation fields sides in more than one league — Thornaby F.C plays Thursday and Monday —
 * and two pubs with the same name in two towns are two teams). Nothing a secretary has since
 * recorded is overwritten: a team that already has an open home tenure keeps it, whatever the seed
 * says, and a source record is `ON CONFLICT DO NOTHING`.
 *
 * Runs as the deploy user (the same as `migrate`), because it writes rows that carry no author.
 */
public class Seed(private val c: Connection, private val now: Instant = Instant.now()) {

    public data class Outcome(
        val leagues: Int, val seasons: Int, val divisions: Int, val teams: Int, val venues: Int,
        val affiliations: Int, val tenures: Int, val sourceRecords: Int,
    ) {
        override fun toString(): String =
            "leagues +$leagues, seasons +$seasons, divisions +$divisions, teams +$teams, venues +$venues, " +
                "affiliations +$affiliations, tenures +$tenures, source records +$sourceRecords"
    }

    private var made = Outcome(0, 0, 0, 0, 0, 0, 0, 0)
    private val org = Organisations(c)

    public fun importFile(file: File): Outcome = import(file.readText())

    public fun import(json: String): Outcome {
        val doc = Json.parseObject(json)
        val retrievedOn = LocalDate.parse(doc["retrieved_on"] as String)
        val method = doc["method"] as String
        c.autoCommit = false
        try {
            val venues = (doc["venues"] as List<*>).associate { v ->
                v as Map<*, *>
                (v["key"] as String) to venue(v)
            }
            val teamVenue = (doc["team_venues"] as List<*>).associate { tv ->
                tv as Map<*, *>
                Pair(tv["league"] as String, tv["team"] as String) to Pair(venues.getValue(tv["venue"] as String), tv["basis"] as String)
            }
            for (l in doc["leagues"] as List<*>) league(l as Map<*, *>, teamVenue, retrievedOn, method)
            c.commit()
        } catch (e: Exception) {
            c.rollback(); throw e
        } finally {
            c.autoCommit = true
        }
        return made
    }

    // --- venues -------------------------------------------------------------------------------

    private class VenueRef(val id: UUID, val osm: String?)

    private fun venue(v: Map<*, *>): VenueRef {
        val osm = v["osm"] as String?
        val name = v["name"] as String
        val locality = v["locality"] as String?
        val existing = osm?.let { bySource("venue", "OpenStreetMap", it) }
            ?: one("SELECT venue_id FROM competition.venue WHERE name = ? AND locality IS NOT DISTINCT FROM ?", name, locality)
        val id = existing ?: org.createVenue(name, locality).also {
            made = made.copy(venues = made.venues + 1)
        }
        // Coordinates and postcode are written where the row has none, and left where it has.
        val lat = (v["latitude"] as Number?)?.toDouble(); val lon = (v["longitude"] as Number?)?.toDouble()
        c.prepareStatement(
            """UPDATE competition.venue SET latitude = coalesce(latitude, ?), longitude = coalesce(longitude, ?),
               postcode = coalesce(postcode, ?) WHERE venue_id = ?""",
        ).use { ps ->
            if (lat != null && lon != null) { ps.setBigDecimal(1, lat.toBigDecimal()); ps.setBigDecimal(2, lon.toBigDecimal()) }
            else { ps.setNull(1, java.sql.Types.NUMERIC); ps.setNull(2, java.sql.Types.NUMERIC) }
            ps.setString(3, v["postcode"] as String?); ps.setObject(4, id); ps.executeUpdate()
        }
        if (osm != null) {
            record("venue", id, v["source"] as String, "https://www.openstreetmap.org/$osm", osm,
                   LocalDate.parse(v["retrieved_on"] as String), "stated by the source")
        }
        return VenueRef(id, osm)
    }

    // --- leagues ------------------------------------------------------------------------------

    private fun league(l: Map<*, *>, teamVenue: Map<Pair<String, String>, Pair<VenueRef, String>>, retrievedOn: LocalDate, method: String) {
        val key = l["key"] as String
        val name = l["name"] as String
        val url = l["url"] as String
        // Found by name, else by its web address — the directory lists Stockton Thursday under a
        // shorter name than its own pages do, and the same address is the same league. Never two.
        val leagueId = one("SELECT league_id FROM competition.league WHERE name = ?", name)
            ?: byAddress(url)
            ?: org.createLeague(name, l["locality"] as String?).also { made = made.copy(leagues = made.leagues + 1) }
        // Fields a source adds and never overwrites: a secretary's word stays; a point stays placed.
        c.prepareStatement(
            """UPDATE competition.league SET short_name = coalesce(short_name, ?), plays_on = coalesce(plays_on, ?),
                      latitude = coalesce(latitude, ?), longitude = coalesce(longitude, ?), website = coalesce(website, ?)
                WHERE league_id = ?""",
        ).use { ps ->
            ps.setString(1, l["short_name"] as String?); ps.setString(2, l["night"] as String?)
            ps.setObject(3, decimal(l["latitude"]), Types.NUMERIC); ps.setObject(4, decimal(l["longitude"]), Types.NUMERIC)
            ps.setString(5, (l["website"] as String?) ?: url); ps.setObject(6, leagueId); ps.executeUpdate()
        }
        record("league", leagueId, l["platform"] as String, url, key, retrievedOn, (l["basis"] as String?) ?: "stated by the source; $method")
        val teamsByName = HashMap<String, UUID>()
        for (s in l["seasons"] as List<*>) {
            s as Map<*, *>
            val label = s["label"] as String
            val seasonId = one("SELECT league_season_id FROM competition.league_season WHERE league_id = ? AND label = ?", leagueId, label)
                ?: org.openSeason(leagueId, label, LocalDate.parse(s["starts_on"] as String), LocalDate.parse(s["ends_on"] as String))
                    .also { made = made.copy(seasons = made.seasons + 1) }
            record("league_season", seasonId, l["platform"] as String, url, label, retrievedOn, s["span_basis"] as String)
            for (d in s["divisions"] as List<*>) {
                d as Map<*, *>
                val dname = d["name"] as String
                val ordinal = (d["ordinal"] as Number).toInt()
                val sourceUrl = d["source_url"] as String
                val divisionId = one("SELECT division_id FROM competition.division WHERE league_season_id = ? AND name = ?", seasonId, dname)
                    ?: org.createDivision(seasonId, dname, ordinal).also { made = made.copy(divisions = made.divisions + 1) }
                record("division", divisionId, l["platform"] as String, sourceUrl, null, retrievedOn, "stated by the source")
                for (t in d["teams"] as List<*>) {
                    val teamName = t as String
                    val home = teamVenue[key to teamName]
                    val teamId = teamsByName.getOrPut(teamName) { team(teamName, l["locality"] as String?, home?.first, key) }
                    record("team", teamId, l["platform"] as String, sourceUrl, null, retrievedOn, "stated by the source")
                    if (home != null) tenure(teamId, home.first, home.second, retrievedOn)
                    val existing = one("SELECT affiliation_id FROM competition.team_affiliation WHERE team_id = ? AND league_season_id = ? AND valid_until IS NULL", teamId, seasonId)
                    val affiliationId = existing ?: org.affiliate(teamId, seasonId, divisionId, from = Timestamp.valueOf((s["starts_on"] as String) + " 00:00:00").toInstant())
                        .also { made = made.copy(affiliations = made.affiliations + 1) }
                    record("team_affiliation", affiliationId, l["platform"] as String, sourceUrl, null, retrievedOn, "stated by the source")
                }
            }
        }
    }

    /** The league whose recorded source address has this host, if one was imported before. */
    private fun byAddress(url: String): UUID? {
        val host = runCatching { URI(url).host }.getOrNull()?.lowercase()?.removePrefix("www.") ?: return null
        return one(
            """SELECT subject_id FROM competition.source_record
                WHERE subject_kind = 'league' AND (source_url ILIKE ? OR source_url ILIKE ?)
                ORDER BY retrieved_on DESC LIMIT 1""",
            "%://$host/%", "%://www.$host/%",
        )
    }

    private fun decimal(v: Any?): BigDecimal? = (v as Number?)?.let { BigDecimal(it.toString()) }

    /** The team of this name at this venue, or of this name already imported for this league, or a new one. */
    private fun team(name: String, locality: String?, venue: VenueRef?, leagueKey: String): UUID {
        if (venue != null) {
            one(
                """SELECT t.team_id FROM competition.team t
                   JOIN competition.team_venue_tenure tv ON tv.team_id = t.team_id AND tv.kind = 'home' AND tv.valid_until IS NULL
                   WHERE t.name = ? AND tv.venue_id = ?""", name, venue.id,
            )?.let { return it }
        }
        one(
            """SELECT t.team_id FROM competition.team t
               JOIN competition.source_record sr ON sr.subject_kind = 'team' AND sr.subject_id = t.team_id
               JOIN competition.source_record lr ON lr.subject_kind = 'league' AND lr.external_ref = ? AND lr.source_url = sr.source_url
               WHERE t.name = ? LIMIT 1""", leagueKey, name,
        )?.let { return it }
        // Same league, a later season on a different page: the league's teams are the ones affiliated to it.
        one(
            """SELECT ta.team_id FROM competition.team_affiliation ta
               JOIN competition.team t ON t.team_id = ta.team_id
               JOIN competition.league_season ls ON ls.league_season_id = ta.league_season_id
               JOIN competition.source_record lr ON lr.subject_kind = 'league' AND lr.subject_id = ls.league_id AND lr.external_ref = ?
               WHERE t.name = ? LIMIT 1""", leagueKey, name,
        )?.let { return it }
        // A secretary may already have the team — recorded by hand, with no source record and perhaps
        // a home the import did not know. Exactly one public, living team of this name in this
        // locality is that team; two would be a guess, and the import does not guess.
        val sameName = c.prepareStatement(
            "SELECT team_id FROM competition.team WHERE name = ? AND locality IS NOT DISTINCT FROM ? AND dissolved_at IS NULL",
        ).use { ps ->
            ps.setString(1, name); ps.setString(2, locality)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getObject(1) as UUID else null }.toList() }
        }
        sameName.singleOrNull()?.let { return it }
        return org.createTeam(name, locality).also { made = made.copy(teams = made.teams + 1) }
    }

    private fun tenure(teamId: UUID, venue: VenueRef, basis: String, retrievedOn: LocalDate) {
        val open = one("SELECT tenure_id FROM competition.team_venue_tenure WHERE team_id = ? AND kind = 'home' AND valid_until IS NULL", teamId)
        val tenureId = open ?: org.openTenure(teamId, venue.id, from = now.minusSeconds(1)).also { made = made.copy(tenures = made.tenures + 1) }
        record("team_venue_tenure", tenureId, "THRØ import", null, venue.osm, retrievedOn, basis)
    }

    // --- provenance ---------------------------------------------------------------------------

    private fun record(kind: String, subject: UUID, source: String, url: String?, ref: String?, retrievedOn: LocalDate, basis: String) {
        c.prepareStatement(
            """INSERT INTO competition.source_record
                 (source_record_id, subject_kind, subject_id, source, source_url, external_ref, retrieved_on, basis)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT DO NOTHING""",
        ).use { ps ->
            ps.setObject(1, UUID.randomUUID()); ps.setString(2, kind); ps.setObject(3, subject); ps.setString(4, source)
            ps.setString(5, url); ps.setString(6, ref); ps.setDate(7, Date.valueOf(retrievedOn)); ps.setString(8, basis.take(200))
            if (ps.executeUpdate() == 1) made = made.copy(sourceRecords = made.sourceRecords + 1)
        }
    }

    private fun bySource(kind: String, source: String, ref: String): UUID? =
        one("SELECT subject_id FROM competition.source_record WHERE subject_kind = ? AND source = ? AND external_ref = ? ORDER BY retrieved_on DESC LIMIT 1", kind, source, ref)

    private fun one(sql: String, vararg args: Any?): UUID? =
        c.prepareStatement(sql).use { ps ->
            args.forEachIndexed { i, a -> ps.setObject(i + 1, a) }
            ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null }
        }
}

/**
 * `gradle -p services/api seed [file]`: import the seed file into the database the environment
 * names (MIGRATE_DATABASE_URL, else DATABASE_URL, else PG*), as the deploy user. Refuses a database
 * that is behind this image's migrations, because the rows it writes need V030 (a league's point).
 * Two files ship: `leagues/directory.json` (every league the LeagueRepublic directory places in the
 * British Isles, points only) and `leagues/teesside.json` (three leagues in full); import both.
 */
public fun main(args: Array<String>) {
    val env: (String) -> String? = { System.getenv(it)?.takeIf { v -> v.isNotBlank() } }
    val file = File(args.firstOrNull() ?: "seed/leagues/teesside.json")
    require(file.isFile) { "no seed file at ${file.absolutePath}" }
    val target = Db.target(env, urlVariable = if (env("MIGRATE_DATABASE_URL") != null) "MIGRATE_DATABASE_URL" else "DATABASE_URL")
    Db.connect(target).use { c ->
        val version = Migrations.currentVersion(c)
        require(version != null && version >= 30) { "the database is at V${version ?: "---"}; the import needs V030 — run migrate first" }
        println("import of ${file.name}: " + Seed(c).importFile(file))
    }
}
