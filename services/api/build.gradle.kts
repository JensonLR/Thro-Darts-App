plugins { kotlin("jvm") version "2.0.21" }
repositories { mavenCentral() }
dependencies {
    implementation("thro-engine:thro-engine")
    implementation("thro-statistics:thro-statistics")
    implementation("org.postgresql:postgresql:42.7.4")
    testImplementation(kotlin("test"))
}
kotlin { explicitApi() }
tasks.test {
    useJUnitPlatform()
    testLogging { showStandardStreams = true }
    // integration tests need a database; skipped cleanly when none is configured
    environment("PGHOST", System.getenv("PGHOST") ?: "")
    environment("PGPORT", System.getenv("PGPORT") ?: "")
    environment("PGUSER", System.getenv("PGUSER") ?: "")
    environment("PGDATABASE", System.getenv("PGDATABASE") ?: "")
}
