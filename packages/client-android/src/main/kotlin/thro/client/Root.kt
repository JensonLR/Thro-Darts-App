package thro.client

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The Android client's one route (PD-081, PD-083).
//
// **Local-first, like the phone.** PD-012: scoring needs no account and no network, so nothing here asks
// for either. The journal opens, two names are typed, and a match is scored. Everything else the iOS client
// does — leagues, clubs, sharing, the rest — is downstream of an account and is not here yet.

@Composable
public fun ThroAndroidRoot() {
    val context = LocalContext.current
    var store by remember { mutableStateOf<ThroStore?>(null) }
    var trouble by remember { mutableStateOf<String?>(null) }
    var session by remember { mutableStateOf<ThroSession?>(null) }
    var carryOn by remember { mutableStateOf<ThroCarryOn?>(null) }

    LaunchedEffect(Unit) {
        ThroStore.open(context).fold(
            onSuccess = {
                store = it
                carryOn = ThroAndroidWords.carryOn(it.journal)
            },
            onFailure = { trouble = ThroAndroidWords.journalRefused(it) },
        )
    }

    ThroTheme {
        val open = store
        val playing = session
        when {
            // The journal is the phone's own record and there is no version of this app that scores
            // without one. Saying so is better than a keypad that quietly forgets.
            trouble != null -> Trouble(trouble!!)
            open == null -> Waiting()
            playing != null && playing.state.isComplete -> ThroResultScreen(playing) {
                session = null
                carryOn = null
            }
            playing != null -> ThroScoringScreen(playing) { session = null }
            else -> ThroSetupScreen(
                carryOn = carryOn,
                onCarryOn = {
                    ThroSession.resumable(open.journal)?.let { session = ThroSession.resume(open.journal, it) }
                    carryOn = null
                },
            ) { home, away ->
                session = ThroSession.start(open.journal, home, away)
                carryOn = null
            }
        }
    }
}

@Composable
private fun Waiting() {
    ThroBoard {
        BasicText(
            "THRØ",
            style = TextStyle(color = LocalThroColors.current.colorTextOnBoard, fontSize = 56.sp,
                              fontWeight = FontWeight.Black, letterSpacing = 4.sp),
            modifier = Modifier.align(Alignment.Center),
        )
    }
}

@Composable
private fun Trouble(message: String) {
    val colors = LocalThroColors.current
    ThroBoard {
        Column(
            Modifier.align(Alignment.Center).padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            BasicText("THRØ cannot keep a record on this phone", style = TextStyle(
                color = colors.colorTextOnBoard, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ))
            BasicText(message, style = TextStyle(
                color = colors.throBronzeOnink, fontSize = 14.sp, textAlign = TextAlign.Center,
            ))
        }
    }
}

/// What the app says about itself, in a type so it can be tested.
public object ThroAndroidWords {
    /// Why the journal would not open. Said on screen rather than logged: a scoring app that cannot record
    /// is not a scoring app, and the player is entitled to know that before they throw.
    public fun journalRefused(error: Throwable): String =
        error.message ?: error::class.simpleName ?: "unknown"

    /// The match to offer back, said the way somebody will read it: both names and where the score stands,
    /// so they can tell at a glance whether it is the one they meant.
    public fun carryOn(journal: thro.journal.Journal): ThroCarryOn? {
        val record = ThroSession.resumable(journal) ?: return null
        val state = runCatching { journal.replay(record.id) }.getOrNull() ?: return null
        val home = state.remaining[state.home] ?: return null
        val away = state.remaining[state.away] ?: return null
        return ThroCarryOn("${record.homeName} $home  ·  ${record.awayName} $away")
    }
}
