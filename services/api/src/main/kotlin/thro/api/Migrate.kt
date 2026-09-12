package thro.api


/**
 * The deploy step ADR-013 requires: bring the database to this image's version, then exit.
 * Runs before the new image serves a request (Fly's release command). Connects as the deploy
 * user — which must be `thro_owner` or a member of it, because every migration does `SET ROLE
 * thro_owner` — and never as an application role. Refuses a ledgerless, edited or ahead database
 * with the reason, so a wrong deploy stops here rather than at the first request.
 */
public fun main() {
    val env: (String) -> String? = { System.getenv(it)?.takeIf { v -> v.isNotBlank() } }
    // The migration connects as the deploy user (MIGRATE_DATABASE_URL, else DATABASE_URL, else PG*),
    // which must be thro_owner, a member of it, or a superuser.
    val target = Db.target(env, urlVariable = if (env("MIGRATE_DATABASE_URL") != null) "MIGRATE_DATABASE_URL" else "DATABASE_URL")
    Db.connect(target).use { c ->
        val before = Migrations.currentVersion(c)
        val applied = Migrations.apply(c)
        val after = Migrations.currentVersion(c)
        if (applied.isEmpty()) println("schema already at V${"%03d".format(after)}; nothing applied")
        else println("migrated V${before?.let { "%03d".format(it) } ?: "---"} -> V${"%03d".format(after)}: " + applied.joinToString { it.file })
        // The user the server connects as (APP_DB_USER, or the user in DATABASE_URL) is given the
        // application roles the migrations created, and nothing else. ADR-011's per-module roles
        // exist in the schema; connecting each module through its own is a follow-up, and until
        // then this one user holds the union, granted here rather than by hand.
        val appUser = env("APP_DB_USER") ?: env("DATABASE_URL")?.let { Db.target(env).user }
        if (appUser != null && appUser != target.user) {
            c.createStatement().use { st ->
                st.execute("GRANT app_match, app_trust, app_rating, app_read, app_competition TO \"${appUser.replace("\"", "")}\"")
            }
            println("application roles granted to $appUser")
        }
    }
}
