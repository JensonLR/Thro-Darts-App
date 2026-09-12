package thro.api

import java.sql.Connection
import java.sql.DriverManager

/**
 * A freshly migrated database for an integration test.
 *
 * Extracted because four test classes had grown their own copy, and adding the audit schema broke
 * three of them at once — each copy had its own list of schemas to drop, and only one knew about
 * the new one. A migration helper that has to be updated in four places is a helper that will be
 * wrong in three.
 */
public object TestDatabase {

    private val host: String get() = System.getenv("PGHOST").orEmpty()

    /**
     * False when no database is configured, so integration tests skip cleanly rather than lie —
     * except where the run has declared that it must have one. CI sets `THRO_REQUIRE_DB=1`, so if the
     * Postgres service ever fails to come up, or the variable is dropped from the workflow, these nine
     * suites fail loudly instead of reporting a green pass over nothing. A suite that can silently run
     * no assertions is worse than no suite: it produces evidence of work that did not happen.
     */
    public val configured: Boolean
        get() {
            if (host.isNotBlank()) return true
            check(System.getenv("THRO_REQUIRE_DB").isNullOrBlank()) {
                "THRO_REQUIRE_DB is set but PGHOST is empty: this run must have a database and does not. " +
                    "The integration suites will not skip themselves here."
            }
            return false
        }

    /** Every schema the migrations create. Dropping them all is what makes a run repeatable. */
    // Every schema a migration creates. A list that does not know about one leaves its tables standing
    // through the reset, and the next run fails on "already exists" — which is what `safety` (V040) did.
    private val schemas = listOf("evidence", "trust", "rating", "read", "audit", "authz", "identity", "competition",
                                 "safety", "thro")

    private val roles = listOf("thro_owner", "app_match", "app_trust", "app_rating", "app_read", "app_competition")

    /** An environment variable's value, treating blank as absent — because a build that forwards
     *  every name unconditionally supplies "" for the ones nobody set, and "" is not a port. */
    private fun env(name: String, fallback: String): String =
        System.getenv(name)?.takeIf { it.isNotBlank() } ?: fallback

    public fun migrated(): Connection = migratedUpTo(Int.MAX_VALUE)

    /** A further connection to the same database, for code that opens one per request. */
    public fun connect(): Connection =
        DriverManager.getConnection("jdbc:postgresql://$host:${env("PGPORT", "5432")}/${env("PGDATABASE", "postgres")}", env("PGUSER", "postgres"), "")

    /**
     * A database migrated only as far as `V<upTo>`, so a test can populate it the way the world
     * looked then and prove that the next migration loses nothing. [apply] runs the rest.
     */
    public fun migratedUpTo(upTo: Int): Connection {
        val port = env("PGPORT", "5432")
        val db = env("PGDATABASE", "postgres")
        val user = env("PGUSER", "postgres")
        val c = DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
        c.createStatement().use { st ->
            for (s in schemas) st.execute("DROP SCHEMA IF EXISTS $s CASCADE")
            for (r in roles) st.execute("DROP ROLE IF EXISTS $r")
        }
        Migrations.apply(c, upTo)
        return c
    }

    /**
     * Applies every migration the ledger does not yet hold, on an existing connection. [after] is
     * documentation of where the caller believes the database stands; the ledger is the authority,
     * and a mismatch is an error in the test rather than something to paper over.
     */
    public fun apply(c: Connection, after: Int) {
        check(Migrations.currentVersion(c) == after) { "the database is at V${Migrations.currentVersion(c)}, not V$after" }
        Migrations.apply(c)
    }
}
