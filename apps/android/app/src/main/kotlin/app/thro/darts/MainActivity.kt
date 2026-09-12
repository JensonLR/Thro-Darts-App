package app.thro.darts

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import thro.client.ThroAndroidRoot

// The whole of the Android app target, for the same reason the iOS one is nineteen lines: an app needs an
// activity, and nothing else about the app belongs in it.
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { ThroAndroidRoot() }
    }
}
