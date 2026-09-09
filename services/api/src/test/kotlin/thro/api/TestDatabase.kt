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

    /** False when no database is configured, so integration tests skip cleanly rather than lie. */
    public val configured: Boolean get() = host.isNotBlank()

    /** Every schema the migrations create. Dropping them all is what makes a run repeatable. */
    private val schemas = listOf("evidence", "trust", "rating", "read", "audit", "authz", "identity", "competition")

    private val roles = listOf("thro_owner", "app_match", "app_trust", "app_rating", "app_read", "app_competition")

    public fun migrated(): Connection = migratedUpTo(Int.MAX_VALUE)

    /**
     * A database migrated only as far as `V<upTo>`, so a test can populate it the way the world
     * looked then and prove that the next migration loses nothing. [apply] runs the rest.
     */
    public fun migratedUpTo(upTo: Int): Connection {
        val port = System.getenv("PGPORT") ?: "5432"
        val db = System.getenv("PGDATABASE") ?: "postgres"
        val user = System.getenv("PGUSER") ?: "postgres"
        val c = DriverManager.getConnection("jdbc:postgresql://$host:$port/$db", user, "")
        c.createStatement().use { st ->
            for (s in schemas) st.execute("DROP SCHEMA IF EXISTS $s CASCADE")
            for (r in roles) st.execute("DROP ROLE IF EXISTS $r")
        }
        migrations().filter { versionOf(it) <= upTo }.forEach { f ->
            c.createStatement().use { it.execute(f.readText()) }
        }
        return c
    }

    /** Applies every migration after [after], in order, on an existing connection. */
    public fun apply(c: Connection, after: Int) {
        migrations().filter { versionOf(it) > after }.forEach { f ->
            c.createStatement().use { it.execute(f.readText()) }
        }
    }

    private fun migrations(): List<File> =
        migrationsDir().listFiles { f -> f.extension == "sql" }?.sortedBy { it.name }.orEmpty()

    private fun versionOf(f: File): Int = f.name.removePrefix("V").substringBefore("__").toInt()

    private fun migrationsDir(): File =
        generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "services/api/migrations") }
            .firstOrNull { it.isDirectory } ?: File("migrations")
}
