// The Android client: everything real, so the app target stays an activity and nothing else — the same
// shape as `packages/client-ios` beside `apps/ios`.
//
// **The design tokens are compiled from where they are generated, not copied.** `build.py` emits
// `ThroTokens.kt` beside the Swift and the CSS, and adding that directory as a source root is what keeps
// one generator feeding every platform. A copy here would be a second place to forget.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "thro.client"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets["main"].kotlin.srcDir("../design-tokens/generated")
    // A literal path, not `layout.buildDirectory.dir(...)`: AGP 9 refuses a Provider here because Android
    // Studio cannot tell generated directories from static ones through one. The task dependency it would
    // have carried is wired by hand below, which the error message says is the trade.
    sourceSets["main"].jniLibs.srcDir("build/generated/sqliteJniLibs")
}

// SQLite's native library, out of the JAR and into the APK.
//
// **`sqlite-jdbc` ships Android natives and Android still would not load them.** The JAR carries
// `org/sqlite/native/Linux-Android/aarch64/libsqlitejdbc.so`, and the driver's loader extracts it to a temp
// directory and calls `System.load` — which Android refuses, because an app may not execute code from its
// own writable storage. The first run said so exactly: *dlopen failed: library "libsqlitejdbc.so" not
// found*. The only place Android will dlopen from is the APK's own `lib/` directory.
//
// So the `.so` is lifted out of the resolved JAR at build time rather than committed. That keeps a
// multi-megabyte binary out of git and — the part that matters — makes it **impossible for the native
// library and the JDBC driver to be different versions**, which is the bug this would otherwise grow.
val sqliteNatives: Configuration by configurations.creating { isTransitive = false }

val extractSqliteNatives by tasks.registering(Copy::class) {
    val abis = mapOf("aarch64" to "arm64-v8a", "arm" to "armeabi-v7a", "x86_64" to "x86_64")
    from({ zipTree(sqliteNatives.singleFile) }) {
        include("org/sqlite/native/Linux-Android/**/libsqlitejdbc.so")
        eachFile {
            val abi = abis[path.substringAfter("Linux-Android/").substringBefore("/")]
            if (abi == null) exclude() else path = "$abi/libsqlitejdbc.so"
        }
        includeEmptyDirs = false
    }
    into(layout.buildDirectory.dir("generated/sqliteJniLibs"))
}

tasks.named("preBuild") { dependsOn(extractSqliteNatives) }

// The rules the screens obey run on the JVM, so they are tested there. Nothing in `ThroScoringWords` or
// `ThroSetupWords` needs a device, and a rule nothing checks is a rule that comes back.
android {
    testOptions.unitTests.isReturnDefaultValues = true
}

dependencies {
    sqliteNatives("org.xerial:sqlite-jdbc:3.46.1.3")
    // Explicit coordinates, not `kotlin("test")`: AGP 9 supplies Kotlin without the Kotlin Gradle Plugin,
    // and that helper comes from the plugin. Named versions are also honest about what is being resolved.
    // `kotlin-test-junit`, not plain `kotlin-test`: the plain artefact picks its framework variant through
    // Gradle attributes the Kotlin plugin sets, and AGP 9 does not apply that plugin — so it resolves to the
    // common variant and `kotlin.test.Test` does not exist. Naming the JUnit variant removes the guesswork.
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.2.20")
    testImplementation("junit:junit:4.13.2")
    // The scoring engine and the journal, which are the same Gradle projects the JVM conformance corpus
    // and the 39 journal tests run against. Not copies: ADR-002 and ADR-006 both turn on there being one
    // implementation per language, and a second one here would be the thing those decisions exist to stop.
    implementation("thro-engine:thro-engine")
    implementation("thro-journal:thro-journal")
    implementation("androidx.compose.ui:ui:1.7.5")
    implementation("androidx.compose.ui:ui-graphics:1.7.5")
    implementation("androidx.compose.ui:ui-text:1.7.5")
    implementation("androidx.compose.foundation:foundation:1.7.5")
}
