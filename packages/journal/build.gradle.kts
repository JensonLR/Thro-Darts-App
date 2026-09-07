plugins { kotlin("jvm") version "2.0.21" }

group = "thro-journal"
version = "1.0.0"
repositories { mavenCentral() }

dependencies {
    // The journal reaches the engine and SQLite and nothing else — the same graph ThroJournal has
    // on iOS, and for the same reason: LATENCY_BUDGETS.md makes the network-independence of scoring
    // a structural requirement, and the module graph is where it is enforced.
    implementation("thro-engine:thro-engine")
    // The JVM SQLite. **Not Android's SQLite** — Android ships its own build behind
    // `android.database.sqlite`, and the two are different binaries with different defaults. What
    // these tests prove is the schema, the triggers, the replay and the API; what they cannot prove
    // is how a Pixel's storage behaves. See README.md.
    implementation("org.xerial:sqlite-jdbc:3.46.1.3")
    testImplementation(kotlin("test"))
}

kotlin { explicitApi() }

tasks.test {
    useJUnitPlatform()
    testLogging { showStandardStreams = true }
}
