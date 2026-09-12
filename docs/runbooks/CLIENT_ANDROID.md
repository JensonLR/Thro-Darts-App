# The Android client

> First run: 12 September 2026 (PD-081). What exists is the board, the wordmark and one line derived by the
> shared scoring engine. What does not exist yet is scoring, the journal on a phone, or any screen with a
> control on it.

## Why there is anything here at all

ADR-002 keeps a Kotlin scoring engine structurally parallel to the Swift one, and `packages/journal` is the
Kotlin half of ADR-006's on-device journal. Both are tested on the JVM and neither had ever run on a phone.
The Android client is where that changes, and the first screen exists to prove it rather than to say it: the
checkout it shows — `141: T20 T19 D12` — is worked out at runtime by `thro-engine`, the same Gradle project
the conformance corpus runs against. A welcome screen reading "Android, coming soon" would have proved
nothing.

## The toolchain, on this Mac

Nothing Android was installed before 12 September 2026. What is there now:

```bash
brew install --cask android-commandlinetools
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

Installed packages: `platform-tools`, `platforms;android-36`, `build-tools;36.0.0`, `emulator`,
`system-images;android-36;google_apis;arm64-v8a`. The SDK licences were accepted with the founder's
say-so — that is a legal acceptance and not a download.

**There is no `local.properties` and there should not be.** Gradle finds the SDK through `ANDROID_HOME`,
which keeps a machine-specific absolute path out of the repository.

## Versions, and why they are not free choices

- **Gradle 9.7.1**, which is what this Mac has and what the other Kotlin packages use.
- **AGP 9.0.0**, because AGP 8.x cannot run on it: it reaches for `org.gradle.api.problems.internal.InternalProblems`,
  removed in Gradle 9.6, and fails at configuration time saying so.
- **No `org.jetbrains.kotlin.android` plugin.** AGP 9 carries Kotlin support itself and errors if you apply
  it as well. Only the Compose compiler plugin is applied on top.

## Building and looking at it

```bash
cd apps/android && gradle :app:assembleDebug
```

```bash
emulator -avd thro-pixel -no-boot-anim -gpu swiftshader_indirect
```

```bash
adb install -r apps/android/app/build/outputs/apk/debug/app-debug.apk && adb shell am start -n app.thro.darts/.MainActivity
```

A screenshot comes back with `adb exec-out screencap -p > shot.png`.

## The shape

`apps/android/app` is the activity and nothing else, the same as `apps/ios/ThroDarts`. Everything real is in
`packages/client-android`, which is a module of the Android build rather than a composite one — an Android
library in a composite build cannot be consumed by an Android application without publishing it. The engine
and the journal *are* composite builds, so they are the same projects the JVM tests run.

The design tokens are compiled **from where they are generated**: `packages/design-tokens/generated` is a
source directory of the client module, so `build.py` feeds Swift, Kotlin and CSS from one run and there is no
copy here to forget.

## The journal, and the two things it took (PD-082)

The client runs `packages/journal` — the same package the 39 JVM tests exercise, against the same SQLite
build. Verified on the emulator, which reports `journal_mode wal · synchronous 2`.

Two things were needed, and a future reader will hit both again if either is undone:

1. **The `.so` must be in the APK's own `lib/`.** Android refuses to `dlopen` from an app's writable
   storage, so the driver's habit of extracting to a temp folder fails with *dlopen failed: library
   "libsqlitejdbc.so" not found*. `packages/client-android/build.gradle.kts` has an `extractSqliteNatives`
   task that lifts them out of the resolved JAR at build time — not committed, so the driver and its native
   library cannot drift apart.
2. **`org.sqlite.lib.path` must be `applicationInfo.nativeLibraryDir`**, set before the first connection.
   `ThroStore.open` does it.

**No durability number is claimed.** ADR-006's measurement on a real Android device is still outstanding;
an emulator's storage says nothing about a phone's.
