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
        // Matched as whole identifiers, not substrings: an earlier version flagged `dartsAtDouble`
        // as floating point, which is the kind of false positive that gets a guard switched off.
        val banned = listOf(
            Regex("""\bcurrentTimeMillis\b""") to "wall clock",
            Regex("""\bnanoTime\b""") to "clock",
            Regex("""\bInstant\.now\b""") to "clock",
            Regex("""\bRandom\b""") to "randomness",
            Regex("""\bDouble\b""") to "floating point",
            Regex("""\bFloat\b""") to "floating point",
            Regex("""\bjava\.n?io\b""") to "I/O",
            Regex("""\breadLine\b""") to "I/O",
        )
        val violations = mutableListOf<String>()
        srcDir.walkTopDown().filter { it.extension == "kt" }.forEach { f ->
            f.readLines().forEachIndexed { i, line ->
                val code = line.substringBefore("//")
                banned.forEach { (pattern, why) ->
                    if (pattern.containsMatchIn(code)) {
                        violations += "${f.name}:${i + 1} uses ${pattern.pattern} ($why)"
                    }
                }
            }
        }
        if (violations.isNotEmpty())
            throw GradleException("engine determinism violated:\n  " + violations.joinToString("\n  "))
        println("determinism guard: clean — no clock, randomness, floating point or I/O")
    }
}

tasks.named("check") { dependsOn(determinismGuard) }
