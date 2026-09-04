plugins { kotlin("jvm") version "2.0.21" }

group = "thro-engine"
version = "1.1.0"

repositories { mavenCentral() }

dependencies {
    // The engine itself has NO dependency beyond the standard library. Enforced by the guard below.
    testImplementation(kotlin("test"))
}

kotlin {
    // Explicit API mode: every public declaration must state its visibility and return type, so the
    // surface three platforms depend on cannot widen by accident.
    explicitApi()
}

tasks.test {
    useJUnitPlatform()
    testLogging { showStandardStreams = true }
}

/**
 * The engine must stay deterministic. This fails the build if the main sources reach for a clock,
 * randomness, floating point or I/O — the four things that would let two platforms disagree about
 * a match. It is the highest value-per-line rule in the build.
 */
val determinismGuard by tasks.registering {
    group = "verification"
    val srcDir = file("src/main/kotlin")
    doLast {
        val banned = listOf(
            "currentTimeMillis" to "wall clock", "nanoTime" to "clock", "Instant.now" to "clock",
            "Random" to "randomness", "Double" to "floating point", "Float" to "floating point",
            "java.io" to "I/O", "java.nio" to "I/O", "readLine" to "I/O",
        )
        val violations = mutableListOf<String>()
        srcDir.walkTopDown().filter { it.extension == "kt" }.forEach { f ->
            f.readLines().forEachIndexed { i, line ->
                val code = line.substringBefore("//")
                banned.forEach { (needle, why) ->
                    if (code.contains(needle)) violations += "${f.name}:${i + 1} uses $needle ($why)"
                }
            }
        }
        if (violations.isNotEmpty())
            throw GradleException("engine determinism violated:\n  " + violations.joinToString("\n  "))
        println("determinism guard: clean — no clock, randomness, floating point or I/O")
    }
}

tasks.named("check") { dependsOn(determinismGuard) }
