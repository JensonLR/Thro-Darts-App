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

// iCloud Drive syncs ~/Documents, and it resolves a conflict by leaving `Foo 2.class` beside
// `Foo.class`. Gradle then hands D8 both and dexing fails with *"Type … is defined multiple times"* —
// three times on this branch, each costing a clean and a rebuild, for a file nobody wrote.
//
// macOS's own escape hatch is a directory whose name ends `.nosync`, which the sync clients skip. This
// applies it **only when the checkout is somewhere a sync client watches**, so CI and anybody outside
// ~/Documents keeps the ordinary `build/` and nothing about the build's shape changes for them.
val synced = rootDir.absolutePath.let { path ->
    listOf("/Documents/", "/Dropbox/", "/Library/CloudStorage/", "/Google Drive/").any { it in path }
}
if (synced) {
    gradle.beforeProject { layout.buildDirectory.set(layout.projectDirectory.dir("build.nosync")) }
}
