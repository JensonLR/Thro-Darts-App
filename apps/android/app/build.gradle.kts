import java.io.File
import java.util.zip.ZipFile

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

// **The APK carries the journal's native library, or the build fails** (PD-093).
//
// On 13 September a build-directory move (`build.nosync`, 7c10426) left the client's jniLibs source set naming a
// directory nothing wrote to any more. Every APK built after it contained no libsqlitejdbc.so, so on a phone the
// journal could not open and the app would say it cannot keep a record — and no test could see it, because the
// JVM unit tests load the driver from the host. It passed an emulator check that morning only because a stale
// `build/` from an earlier build still held the natives, and that directory was deleted minutes later.
//
// So the property is checked where it lives — in the APK — every time one is assembled, locally and in CI.
val verifyApkCarriesTheJournal by tasks.registering {
    group = "verification"
    description = "Fails when the debug APK carries no libsqlitejdbc.so for any ABI."
    val apk = providers.gradleProperty("verifyApk").map { File(it) }
        .orElse(layout.buildDirectory.file("outputs/apk/debug/app-debug.apk").map { it.asFile })
    inputs.property("apkPath", apk.map { it.absolutePath })
    doLast {
        val file = apk.get()
        if (!file.exists()) throw GradleException("No APK at ${file.path} to check.")
        val natives = ZipFile(file).use { zip ->
            zip.entries().asSequence().map { it.name }
                .filter { Regex("lib/[^/]+/libsqlitejdbc\\.so").matches(it) }.toList()
        }
        if (natives.isEmpty()) {
            throw GradleException(
                "${file.name} carries no libsqlitejdbc.so. On a device the journal cannot open and THRØ cannot " +
                    "keep a record. Check the client's jniLibs source set against the real build directory.",
            )
        }
        logger.lifecycle("the APK carries the journal: ${natives.joinToString()}")
    }
}
tasks.named { it == "assembleDebug" }.configureEach { finalizedBy(verifyApkCarriesTheJournal) }
