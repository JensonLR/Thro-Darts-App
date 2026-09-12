package thro.client

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import thro.journal.DeviceId
import thro.journal.Journal
import java.io.File
import java.util.UUID

// The phone's own record, on Android (PD-082).
//
// **The same journal, not a second one.** `packages/journal` is ADR-006's on-device journal in Kotlin — the
// same schema, the same append-only triggers, the same replay, held by 39 tests on the JVM. Its README is
// careful to say those tests run on `sqlite-jdbc` and not on `android.database.sqlite`, and the obvious
// reading of that is that Android needs its own implementation. It does not: **the `sqlite-jdbc` JAR ships
// Android natives**, so the phone can run the same code against the same SQLite build the tests do.
//
// What that is worth: a trigger that refuses a `DELETE` is the same trigger on both platforms, a replay that
// throws on a corrupt row throws the same way, and a durability configuration measured once means something
// on both. What it is *not* worth is a durability claim — ADR-006's measurement on a real Android device is
// still outstanding, and an emulator's storage says nothing about a phone's.

/// Where the journal lives, and whether it opened.
public class ThroStore private constructor(
    public val journal: Journal,
    public val path: String,
) {
    public companion object {
        /// The device identity, kept in the same place the iOS client keeps its own: a preference, written
        /// once. Not the hardware's identifier — a journal's device id is about which device wrote a row,
        /// not about which person is holding it.
        private const val DEVICE_KEY = "thro.journal.deviceId"

        public suspend fun open(context: Context): Result<ThroStore> = withContext(Dispatchers.IO) {
            runCatching {
                val prefs = context.getSharedPreferences("thro", Context.MODE_PRIVATE)
                val device = prefs.getString(DEVICE_KEY, null) ?: UUID.randomUUID().toString().also {
                    prefs.edit().putString(DEVICE_KEY, it).apply()
                }
                // Point the driver at the APK's own native library directory. Without this it extracts the
                // `.so` to a temp folder and asks Android to load it from there, which Android refuses —
                // *dlopen failed: library "libsqlitejdbc.so" not found*, which is a true statement about the
                // only directory it is allowed to look in.
                System.setProperty("org.sqlite.lib.path", context.applicationInfo.nativeLibraryDir)
                System.setProperty("org.sqlite.lib.name", "libsqlitejdbc.so")
                val file = File(context.filesDir, "thro-journal.sqlite")
                ThroStore(Journal.open(file.absolutePath, DeviceId(device)), file.absolutePath)
            }
        }
    }
}
