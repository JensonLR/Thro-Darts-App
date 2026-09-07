package thro.api

import java.io.File
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
    private val schemas = listOf("evidence", "trust", "rating", "read", "audit", "authz", "identity", "competition")

    private val roles = listOf("thro_owner", "app_match", "app_trust", "app_rating", "app_read", "app_competition")

    public fun migrated(): Connection {
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        val c = DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
        c.createStatement().use { st ->
            for (s in schemas) st.execute("DROP SCHEMA IF EXISTS $s CASCADE")
            for (r in roles) st.execute("DROP ROLE IF EXISTS $r")
        }
        migrationsDir().listFiles { f -> f.extension == "sql" }?.sortedBy { it.name }?.forEach { f ->
            c.createStatement().use { it.execute(f.readText()) }
        }
        return c
    }

    private fun migrationsDir(): File =
        generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "services/api/migrations") }
            .firstOrNull { it.isDirectory } ?: File("migrations")
}
