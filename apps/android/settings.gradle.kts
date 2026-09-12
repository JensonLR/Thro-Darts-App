// The Android client's build.
//
// **The packages are composite builds, not copies.** `thro-engine` and `thro-journal` are the same
// Gradle projects the JVM tests run against — ADR-002 keeps a Kotlin scoring engine structurally parallel
// to the Swift one, and a second copy of either here would be the thing that ADR exists to prevent.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "thro-android"
includeBuild("../../packages/engine")
includeBuild("../../packages/journal")
include(":app")
// The client lives where every other client does — under packages/ — and is a module of this build
// rather than a composite one, because an Android library in a composite build cannot be consumed by
// an Android application without publishing it.
include(":client")
project(":client").projectDir = file("../../packages/client-android")
