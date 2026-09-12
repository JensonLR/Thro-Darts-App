// AGP 9 carries Kotlin support itself — applying `org.jetbrains.kotlin.android` beside it is an error
// now, and AGP says so in terms. Gradle 9.7 is what this machine has and AGP 8.x cannot run on it: it
// reaches for a Gradle internal removed in 9.6.
plugins {
    id("com.android.application") version "9.0.0" apply false
    id("com.android.library") version "9.0.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
}
