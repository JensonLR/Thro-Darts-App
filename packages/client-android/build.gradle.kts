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
}

dependencies {
    // The scoring engine, which is the same Gradle project the JVM conformance corpus runs against.
    implementation("thro-engine:thro-engine")
    implementation("androidx.compose.ui:ui:1.7.5")
    implementation("androidx.compose.ui:ui-graphics:1.7.5")
    implementation("androidx.compose.ui:ui-text:1.7.5")
    implementation("androidx.compose.foundation:foundation:1.7.5")
}
