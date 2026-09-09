package thro.api

import java.io.File
import java.security.MessageDigest
import java.sql.Connection

/**
 * Forward-only migrations, with a ledger.
 *
 * Until V019 the runners applied every file when the `evidence` schema was absent and nothing
 * otherwise, so a database migrated by an earlier checkout sat silently behind the code: after V018
 * such a database still had `home_name NOT NULL` and could not open a match at all, and every
 * later property failed for the wrong reason. Hostile review found it; this is the fix.
 *
 * The ledger `thro.schema_migration` records each file applied, with a digest of its content.
 * Applying means: every file the ledger does not hold, in version order, each in its own
 * transaction together with its ledger row — so a file that fails leaves no half-applied schema
 * and no false record. Three things are refused rather than guessed:
 *
 *  - a database that has THRØ's schemas but no ledger (migrated before the ledger existed): its
 *    version cannot be known, so it is rebuilt, not patched;
 *  - a recorded file whose content has since changed: migrations are forward-only, and an edit to
 *    an applied one is a new migration or a rebuild, never a re-run;
 *  - a recorded version this checkout has no file for: the database is ahead of the code.
 *
 * The ledger belongs to the deploy role that runs migrations, not to any application role; nothing
 * grants it to them.
 */
public object Migrations {

    public data class Applied(val version: Int, val file: String)

    public fun files(): List<File> =
        dir().listFiles { f -> f.extension == "sql" && f.name.startsWith("V") }?.sortedBy { versionOf(it) }.orEmpty()

    public fun versionOf(f: File): Int = f.name.removePrefix("V").substringBefore("__").toInt()

    /** Applies every unapplied migration up to and including `V<upTo>`; returns what it applied. */
    public fun apply(c: Connection, upTo: Int = Int.MAX_VALUE): List<Applied> {
        val previous = c.autoCommit
        c.autoCommit = false
        try {
            c.createStatement().use { st ->
                st.execute("CREATE SCHEMA IF NOT EXISTS thro")
                st.execute(
                    """
                    CREATE TABLE IF NOT EXISTS thro.schema_migration (
                      version    int         PRIMARY KEY,
                      filename   text        NOT NULL,
                      sha256     text        NOT NULL,
                      applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
                    )
                    """.trimIndent(),
                )
            }
            c.commit()
            val recorded = linkedMapOf<Int, Pair<String, String>>()
            c.createStatement().use { st ->
                st.executeQuery("SELECT version, filename, sha256 FROM thro.schema_migration ORDER BY version").use { rs ->
                    while (rs.next()) recorded[rs.getInt(1)] = rs.getString(2) to rs.getString(3)
                }
            }
            val hasSchemas = c.createStatement().use { st ->
                st.executeQuery("SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'evidence'").use { rs -> rs.next(); rs.getInt(1) > 0 }
            }
            check(recorded.isNotEmpty() || !hasSchemas) {
                "this database has THRØ's schemas but no migration ledger: it was migrated by a checkout from " +
                    "before the ledger existed and its version cannot be known. Rebuild it (drop the schemas, as the " +
                    "test harness does) rather than guess."
            }
            val files = files()
            val byVersion = files.associateBy { versionOf(it) }
            recorded.keys.firstOrNull { it !in byVersion }?.let {
                error("the database records V$it, which this checkout has no file for: the database is ahead of the code")
            }
            val applied = mutableListOf<Applied>()
            for (f in files) {
                val v = versionOf(f)
                if (v > upTo) continue
                val bytes = f.readBytes()
                val digest = sha256(bytes)
                val seen = recorded[v]
                if (seen != null) {
                    check(seen.second == digest) {
                        "${f.name} was applied from different content (recorded ${seen.second.take(12)}, file ${digest.take(12)}). " +
                            "Migrations are forward-only: write a new one, or rebuild the database."
                    }
                    continue
                }
                try {
                    c.createStatement().use { it.execute(String(bytes, Charsets.UTF_8)) }
                    c.prepareStatement("INSERT INTO thro.schema_migration (version, filename, sha256) VALUES (?, ?, ?)").use { ps ->
                        ps.setInt(1, v); ps.setString(2, f.name); ps.setString(3, digest); ps.executeUpdate()
                    }
                    c.commit()
                } catch (e: Exception) {
                    c.rollback()
                    throw IllegalStateException("${f.name} failed and was rolled back: ${e.message}", e)
                }
                applied += Applied(v, f.name)
            }
            return applied
        } finally {
            c.autoCommit = previous
        }
    }

    /** The highest version the ledger records, or null when there is no ledger yet. */
    public fun currentVersion(c: Connection): Int? =
        c.createStatement().use { st ->
            st.executeQuery(
                "SELECT max(version) FROM thro.schema_migration WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'thro' AND table_name = 'schema_migration')",
            ).use { rs -> if (rs.next()) rs.getObject(1)?.let { (it as Number).toInt() } else null }
        }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun dir(): File =
        generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "services/api/migrations") }
            .firstOrNull { it.isDirectory } ?: File("migrations")
}
