package thro.client

import androidx.activity.compose.BackHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.window.Dialog
import thro.journal.MatchId
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// The Android client's one route (PD-081, PD-083).
//
// **Local-first, like the phone.** PD-012: scoring needs no account and no network, so nothing here asks
// for either. The journal opens, two names are typed, and a match is scored. Everything else the iOS client
// does — leagues, clubs, sharing, the rest — is downstream of an account and is not here yet.
//
// **One thing is read from outside** (PD-097): the notice about people's information, from THRØ's public web site,
// anonymously, at launch and on every return to the front. Nothing about scoring waits on it or knows it exists.

@Composable
public fun ThroAndroidRoot(
    /// The public web site the notice is read from; null asks nothing. `MainActivity` may point a debuggable build at a
    /// local copy.
    webBaseUrl: String? = THRO_WEB_BASE_URL,
    /// How many times the app has come to the front. Each is a chance to look for a notice again; the notices themselves
    /// hold the looks to one a minute.
    foregrounds: Int = 0,
) {
    val context = LocalContext.current
    var store by remember { mutableStateOf<ThroStore?>(null) }
    var trouble by remember { mutableStateOf<String?>(null) }
    var session by remember { mutableStateOf<ThroSession?>(null) }
    // The match being scored, by id, kept across the activity being rebuilt — the session itself is not
    // something a Bundle can hold, but the journal can replay it from its id, which is how it came back anyway.
    var playingId by rememberSaveable { mutableStateOf<String?>(null) }
    val play: (ThroSession?) -> Unit = { next ->
        session = next
        playingId = next?.matchId?.value
    }
    var leaving by remember { mutableStateOf(false) }
    val scoring = remember { ThroScoringPreferences(context) }
    var carryOn by remember { mutableStateOf<ThroCarryOn?>(null) }
    // Read when the list is opened and when a match ends, rather than held and mutated. The journal is
    // the only record; a cached list is a second one, and a second record is a record that can be wrong.
    var kept by remember { mutableStateOf<List<ThroMatchRow>>(emptyList()) }
    var showingKept by remember { mutableStateOf(false) }
    val notices = remember(webBaseUrl) {
        ThroServiceNotices(webBaseUrl, ThroNoticeTransport.Anonymous, ThroNoticePreferences(context))
    }
    var notice by remember { mutableStateOf<ThroNotice?>(null) }
    val pages = LocalUriHandler.current

    LaunchedEffect(Unit) {
        ThroStore.open(context).fold(
            onSuccess = {
                store = it
                carryOn = ThroAndroidWords.carryOn(it.journal)
                kept = ThroMatchList.rows(it.journal)
                // Rebuilt in the middle of a match: pick it back up where the scorer was, by replay.
                playingId?.let { id ->
                    runCatching { ThroSession.resume(it.journal, it.journal.match(MatchId(id))) }
                        .onSuccess { resumed -> session = resumed; carryOn = null }
                        .onFailure { playingId = null }
                }
            },
            onFailure = { trouble = ThroAndroidWords.journalRefused(it) },
        )
    }

    LaunchedEffect(notices, foregrounds) {
        withContext(Dispatchers.IO) { notices.refresh() }
        notice = notices.showing
    }

    ThroTheme {
        val open = store
        val playing = session
        when {
            // The journal is the phone's own record and there is no version of this app that scores
            // without one. Saying so is better than a keypad that quietly forgets.
            trouble != null -> Trouble(trouble!!)
            open == null -> Waiting()
            playing != null && playing.state.isComplete -> {
                val finished = {
                    play(null)
                    carryOn = null
                    kept = ThroMatchList.rows(open.journal)
                }
                // Back from a result is the result's own Done, not the launcher.
                BackHandler(onBack = finished)
                ThroResultScreen(playing, finished)
            }
            playing != null -> {
                // **Back leaves the keypad, not the app** (PD-093). With no handler, the system's back — the edge
                // swipe that gesture navigation puts under every thumb — closed the activity in the middle of a leg.
                // Nothing was lost, because every visit is already in the journal, but the scorer landed on the
                // phone's home screen with no word about the match. Back goes to the first screen, which offers the
                // match as "Carry on", exactly as it would after the app had been closed.
                //
                // **And it asks first.** That same edge swipe is also what a thumb does by accident reaching for the
                // left column of the keypad, and it took the scorer off the match mid-visit, darts in hand and all.
                BackHandler { leaving = true }
                ThroScoringScreen(playing, scoring) {
                    play(null)
                    kept = ThroMatchList.rows(open.journal)
                }
                if (leaving) {
                    ThroConfirm(
                        question = ThroAndroidWords.LEAVE_QUESTION,
                        detail = ThroAndroidWords.LEAVE_DETAIL,
                        confirm = "Leave",
                        cancel = "Stay",
                        onConfirm = {
                            leaving = false
                            play(null)
                            carryOn = ThroAndroidWords.carryOn(open.journal)
                            kept = ThroMatchList.rows(open.journal)
                        },
                        onCancel = { leaving = false },
                    )
                }
            }
            showingKept -> {
                BackHandler { showingKept = false }
                ThroMatchesScreen(
                    rows = kept,
                    onCarryOn = { row ->
                        play(ThroSession.resume(open.journal, row.record))
                        showingKept = false
                        carryOn = null
                    },
                    onBack = { showingKept = false },
                )
            }
            else -> {
                // Nobody on Android has said their age — there are no accounts here — so the under-18 words, as for
                // anybody whose age is not known to be adult.
                val reading = notice?.forReader(ageBand = null)
                ThroSetupScreen(
                    carryOn = carryOn,
                    onCarryOn = {
                        ThroSession.resumable(open.journal)?.let { play(ThroSession.resume(open.journal, it)) }
                        carryOn = null
                    },
                    kept = kept.size,
                    onSeeKept = {
                        kept = ThroMatchList.rows(open.journal)
                        showingKept = true
                    },
                    notice = reading,
                    onReadNotice = {
                        notices.page(underEighteen = reading?.underEighteen ?: true)?.let { page ->
                            // A phone with nothing to open a web page in keeps the card, and the notice with it.
                            runCatching { pages.openUri(page) }
                        }
                    },
                    onPutAwayNotice = {
                        notices.putAway()
                        notice = notices.showing
                    },
                ) { match ->
                    play(ThroSession.start(open.journal, match))
                    carryOn = null
                }
            }
        }
    }
}

@Composable
private fun Waiting() {
    ThroBoard {
        // The wordmark, not the name in a font: a dart through a ring, generated from the geometry the
        // app draws (`tools/make_web_wordmark.py`) and tinted so it follows the palette.
        Image(
            painter = painterResource(R.drawable.thro_wordmark),
            contentDescription = "THRØ",
            colorFilter = ColorFilter.tint(LocalThroColors.current.colorTextOnBoard),
            modifier = Modifier.align(Alignment.Center).width(220.dp),
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
            ThroText("THRØ cannot keep a record on this phone", ThroTypography.heading3, colors.colorTextOnBoard,
                     align = TextAlign.Center)
            ThroText(message, ThroTypography.metadata, colors.throBronzeOnink, align = TextAlign.Center)
        }
    }
}

/// A question with a consequence, asked over the board before anything happens. Drawn in the board's own chalk
/// rather than Material's dialog, which would be the one grey rectangle in the app.
@Composable
internal fun ThroConfirm(
    question: String,
    detail: String,
    confirm: String,
    cancel: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
) {
    val colors = LocalThroColors.current
    Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier.fillMaxWidth()
                .background(colors.colorBoardSunken, RoundedCornerShape(14.dp))
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ThroText(question, ThroTypography.heading3, colors.colorTextOnBoard,
                     modifier = Modifier.semantics { heading() })
            ThroText(detail, ThroTypography.body, colors.throChalk.copy(alpha = 0.8f))
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((label, action, lit) in listOf(Triple(cancel, onCancel, true), Triple(confirm, onConfirm, false))) {
                    Box(
                        Modifier.weight(1f).heightIn(min = 48.dp)
                            .background(colors.throChalk.copy(alpha = if (lit) 0.18f else 0.07f), RoundedCornerShape(10.dp))
                            .clickable(role = Role.Button) { action() },
                        contentAlignment = Alignment.Center,
                    ) {
                        ThroText(label, ThroTypography.labelStrong, colors.throChalk)
                    }
                }
            }
        }
    }
}

/// What the app says about itself, in a type so it can be tested.
public object ThroAndroidWords {
    public const val LEAVE_QUESTION: String = "Leave this match?"
    public const val LEAVE_DETAIL: String = "It is saved; you can carry on from the match list."

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
