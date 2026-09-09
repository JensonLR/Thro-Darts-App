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
    // ADR-001: Ktor. The HTTP layer is thin — routes over the existing handlers — and the contract
    // it serves at /openapi.json is emitted from the same registry the routes are built from.
    implementation("io.ktor:ktor-server-core:3.0.3")
    implementation("io.ktor:ktor-server-cio:3.0.3")
    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-server-test-host:3.0.3")
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
    for (name in listOf("PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "THRO_REQUIRE_DB", "THRO_WRITE_OPENAPI")) {
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

// `gradle -p services/api serve` starts the HTTP API. It refuses to start without an authenticator;
// the only one that exists is the development one, enabled by THRO_DEV_AUTH=1 and nothing else.
tasks.register<JavaExec>("serve") {
    group = "application"
    description = "Start the THRØ HTTP API (Ktor)"
    classpath = sourceSets["main"].runtimeClasspath
    mainClass.set("thro.api.http.MainKt")
    for (v in listOf("PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PORT", "THRO_DEV_AUTH")) {
        System.getenv(v)?.let { environment(v, it) }
    }
}
