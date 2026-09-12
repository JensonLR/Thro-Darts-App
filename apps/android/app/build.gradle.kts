plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "app.thro.darts"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.thro.darts"
        // **API 26.** The journal's SQLite comes from `sqlite-jdbc`, which needs 26 for its native
        // loader, and 26 is also where java.time lives without desugaring — the journal is written
        // against `Instant` and `DateTimeFormatter` and neither is negotiable.
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
}

dependencies {
    implementation(project(":client"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui:1.7.5")
    implementation("androidx.compose.ui:ui-graphics:1.7.5")
    implementation("androidx.compose.foundation:foundation:1.7.5")
}
