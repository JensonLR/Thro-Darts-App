plugins {
    kotlin("jvm") version "2.0.21"
    application
}
repositories { mavenCentral() }
dependencies {
    implementation("thro-engine:thro-engine")
    implementation("thro-statistics:thro-statistics")
    implementation("thro-authz:thro-authz")
    implementation("thro-trust:thro-trust")
    implementation("thro-competition:thro-competition")
    implementation("org.postgresql:postgresql:42.7.4")
    testImplementation(kotlin("test"))
}
kotlin { explicitApi() }
tasks.test {
    useJUnitPlatform()
    testLogging { showStandardStreams = true }
    // Integration tests need a database; they skip cleanly when none is configured, and fail rather
    // than skip when THRO_REQUIRE_DB says the run must have one — which is why that variable has to
    // be forwarded too. A Gradle test task does not inherit the environment, so anything the tests
    // read has to be named here; THRO_REQUIRE_DB was set by CI and never arrived until it was.
    //
    // Each is forwarded only when it has a value. Passing an empty string is not the same as passing
    // nothing: it defeats the `?: "5432"` fallbacks on the other side, and produced the unparseable
    // `jdbc:postgresql://host:/` for anyone who set PGHOST alone.
    for (name in listOf("PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "THRO_REQUIRE_DB")) {
        System.getenv(name)?.takeIf { it.isNotBlank() }?.let { environment(name, it) }
    }
}

// `gradle -p services/api run` starts the playtest harness. The database settings come from the
// environment so that no connection detail is ever committed.
application {
    mainClass.set("thro.api.PlaytestServer")
}
tasks.named<JavaExec>("run") {
    standardInput = System.`in`
    for (v in listOf("PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PORT")) {
        System.getenv(v)?.let { environment(v, it) }
    }
}
