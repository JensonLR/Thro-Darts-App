package app.thro.darts

import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import thro.client.THRO_WEB_BASE_URL
import thro.client.ThroAndroidRoot

// The whole of the Android app target, for the same reason the iOS one is nineteen lines: an app needs an
// activity, and nothing else about the app belongs in it.
class MainActivity : ComponentActivity() {
    // Every return to the front, counted, so the first screen can look for a notice again (PD-097). `onStart` rather than
    // `onResume`: a dialog over the app is not the app coming back.
    private var foregrounds by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // **Light system icons, always** (PD-093). Every Android screen is the green board, but
        // `enableEdgeToEdge()` with no arguments picks the icons from the phone's light or dark setting — so on
        // a phone in light mode the clock and the battery were drawn dark grey on dark green, and all but vanished.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        // A debuggable build may read the notice from a local copy, as the iPhone's Debug build takes -ThroWebBaseURL, so
        // the card can be looked at without publishing anything (docs/runbooks/CLIENT_ANDROID.md). A release build cannot.
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        // And only the emulator's address for the host machine, even then. This activity is exported, so any app on the
        // phone can start it with extras, and a notice card pointed at somebody else's site is a phishing page in THRØ's
        // colours.
        val web = intent.getStringExtra("thro.webBaseUrl")
            ?.takeIf { debuggable && (it.startsWith("http://10.0.2.2:") || it.startsWith("http://10.0.2.2/")) }
            ?: THRO_WEB_BASE_URL
        setContent { ThroAndroidRoot(webBaseUrl = web, foregrounds = foregrounds) }
    }

    override fun onStart() {
        super.onStart()
        foregrounds++
    }
}
