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

**Why the glob on the path.** On a checkout inside iCloud, Dropbox or Google Drive the build directory
is `build.nosync/` rather than `build/` — the sync client resolves its own conflicts by leaving
`Foo 2.class` beside `Foo.class`, Gradle hands D8 both, and dexing fails with *"Type … is defined multiple
times"*. `apps/android/settings.gradle.kts` renames the directory only on such a checkout, because a name
ending `.nosync` is the one thing every macOS sync client agrees to skip. Elsewhere it is `build/` as usual.

```bash
adb install -r "$(ls apps/android/app/build*/outputs/apk/debug/app-debug.apk | head -1)" && adb shell am start -n app.thro.darts/.MainActivity
```

### Looking at the notice about people's information (PD-097)

The client's one network call reads `notice.json` from the public web site (`THRO_WEB_BASE_URL` in `Hosts.kt`, kept by
`tools/host.py`), and the committed file says no notice is live. To look at the card, serve a copy of `apps/web` whose
`notice.json` is a rehearsal, from this Mac, and point a debuggable build at it. Plain HTTP to `10.0.2.2` — the
emulator's address for the host — is allowed in debug builds only (`apps/android/app/src/debug`).

```bash
python3 -m http.server 8787 --bind 127.0.0.1 --directory /path/to/a-copy-of-apps-web
```

```bash
adb shell am start -n app.thro.darts/.MainActivity --es thro.webBaseUrl http://10.0.2.2:8787
```

The card sits under the mark on the first screen. **Never put a rehearsal in `apps/web/notice.json`**: the file on the
site is the notice, and it reaches every phone that opens THRØ.

A screenshot comes back with `adb exec-out screencap -p > shot.png`.

## The shape

`apps/android/app` is the activity and nothing else, the same as `apps/ios/ThroDarts`. Everything real is in
`packages/client-android`, which is a module of the Android build rather than a composite one — an Android
library in a composite build cannot be consumed by an Android application without publishing it. The engine
and the journal *are* composite builds, so they are the same projects the JVM tests run.

The design tokens are compiled **from where they are generated**: `packages/design-tokens/generated` is a
source directory of the client module, so `build.py` feeds Swift, Kotlin and CSS from one run and there is no
copy here to forget.

### The screens

`Root.kt` holds the whole of the navigation, which is four states and no library:

| | |
| --- | --- |
| **Setup** | Two names and a start, plus *Carry on* when a match is half-scored and *Your darts · n* when the phone is holding any. Both are offered rather than taken: a match left three weeks ago is not the one somebody just opened the app to start. |
| **Scoring** | The keypad. Engine, then journal, then screen, never another order. |
| **Result** | Who won, and who has said so (PD-011). |
| **Your darts** | Every match the journal holds, newest first — `ThroMatchList` builds the rows and `ThroMatchesScreen` draws them. Tapping an unfinished one carries it on. |

`ThroMatchList` is deliberately parallel to iOS's `AppStore.HomeMatch`, down to the status words: **three,
not two**, because an abandoned match is finished and is not a result. A match whose rows will not replay
is listed with the reason where its score would be, and with no score at all.

### The launcher icon

Generated, never exported. `tools/make_android_icon.py` reads `MarkGeometry.Ratios.mark` out of the Swift
and the colours out of the design tokens, and writes the adaptive icon, a monochrome layer for Android 13
themed icons, and the background colour. CI runs it with `--check`, so a change to the mark that has not
been regenerated fails the build rather than leaving two versions of the brand in the product.

Android guarantees only the central **72×72dp of its 108dp canvas**; the rest is margin a launcher may crop
or parallax away. So 72 is treated as the icon exactly as 1024 is on iOS, which puts the mark's tips at the
same 92% of the visible radius on both.

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
