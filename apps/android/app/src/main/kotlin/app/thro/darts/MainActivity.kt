package app.thro.darts

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import thro.client.ThroAndroidRoot

// The whole of the Android app target, for the same reason the iOS one is nineteen lines: an app needs an
// activity, and nothing else about the app belongs in it.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // **Light system icons, always** (PD-093). Every Android screen is the green board, but
        // `enableEdgeToEdge()` with no arguments picks the icons from the phone's light or dark setting — so on
        // a phone in light mode the clock and the battery were drawn dark grey on dark green, and all but vanished.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        setContent { ThroAndroidRoot() }
    }
}
