package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import thro.engine.Dart
import thro.engine.Darts
import thro.engine.RejectionReason
import thro.engine.Ring
import thro.journal.Seat

// Scoring a match on Android (PD-083).
//
// **Two keypads, one visit.** The total keypad is what every darts app has; the dart keypad takes the three
// darts one at a time, and it is the one that carries evidence — the engine reads the darts, so how many were
// used and how many were thrown at a double are never asked, and a T20 from 60 is recorded as the bust it is
// rather than read as a checkout. The iPhone has had both; this is the same pair, in the same words.
//
// **Every number the player sees comes from the engine.** The remaining, the route and whether the visit is
// already decided come from `MatchState` and from the engine's reading of the darts in hand — nothing is
// subtracted here. The local state on this screen is what has been typed or keyed and not yet entered.

private val MIN_TARGET = 48.dp

@Composable
public fun ThroScoringScreen(
    session: ThroSession,
    /// Where the last-used keypad is remembered. Null in a preview, which then opens on the default.
    preferences: ThroScoringPreferences? = null,
    onDone: () -> Unit,
) {
    val key = session.matchId.value
    var typed by rememberSaveable(key) { mutableStateOf("") }
    var mode by rememberSaveable(key) {
        mutableStateOf(ThroEntryMode.initial(preferences?.entryMode, session.bustRule))
    }
    // The ring the next sector lands in. Falls back to single after every dart: holding TREBLE across a visit is
    // a mis-key waiting to happen.
    var ring by rememberSaveable(key) { mutableStateOf(Ring.SINGLE) }
    // Half-entered darts, kept across the screen being rebuilt — the activity handles rotation itself, but a
    // font-size change or the process being reclaimed still rebuilds it, and three darts are cheap to keep.
    var keptDarts by rememberSaveable(key) { mutableStateOf("") }
    LaunchedEffect(session) {
        if (session.darts.isEmpty() && keptDarts.isNotEmpty()) session.restoreDarts(ThroDartWords.read(keptDarts))
        snapshotFlow { session.darts }.collect { keptDarts = ThroDartWords.store(it) }
    }
    val colors = LocalThroColors.current

    // Undo takes back what is in hand before it touches the record: one dart, then the typed digits, and only
    // then the last visit. Clearing a whole entry — or striking a visit — to fix one mis-key is the correction
    // costing more than the error.
    val undo: () -> Unit = {
        if (session.darts.isNotEmpty()) {
            session.takeBackDarts(session.darts.size - 1)
        } else if (typed.isNotEmpty()) {
            typed = ""
        } else {
            session.undo()
        }
    }

    ThroBoard {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (seat in listOf(Seat.HOME, Seat.AWAY)) {
                    Side(session, seat, Modifier.weight(1f))
                }
            }

            // What just happened, said once to TalkBack as well as drawn: a polite live region, so a bust or a
            // leg is announced without interrupting whatever is already being read.
            ThroText(
                ThroScoringWords.say(session, typed),
                ThroTypography.body.weight(FontWeight.SemiBold),
                colors.throGreenOnink,
                modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(vertical = 4.dp)
                    .semantics { liveRegion = LiveRegionMode.Polite },
                align = TextAlign.Center,
                maxLines = 3,
            )

            if (!session.state.isComplete) {
                ModeSwitch(mode) { chosen ->
                    if (chosen != mode) {
                        // The part-entered visit is cleared: three darts have a total, but a total does not have
                        // three darts, and inventing them would put darts nobody threw into the record.
                        typed = ""
                        session.clearDarts()
                        ring = Ring.SINGLE
                        mode = chosen
                        preferences?.entryMode = chosen
                    }
                }
            }

            if (mode == ThroEntryMode.DARTS) {
                DartLine(session)
                DartKeypad(
                    session = session,
                    ring = ring,
                    onRing = { ring = it },
                    onDart = { session.dart(it); ring = Ring.SINGLE },
                    onUndo = undo,
                    modifier = Modifier.weight(1f),
                )
            } else if (session.prompt != null) {
                PromptPanel(session.prompt!!, onAnswer = { answer ->
                    session.answer(answer)
                    // The keep rule's refusal arrives after the question now; the screen still goes to darts.
                    val refused = session.mark
                    if (refused is ThroMark.Refused && refused.reason == RejectionReason.DARTS_REQUIRED) {
                        mode = ThroEntryMode.DARTS
                    }
                }, onCancel = session::cancelPrompt, modifier = Modifier.weight(1f))
            } else {
                TotalKeypad(
                    typed = typed,
                    onDigit = { typed = ThroScoringWords.typed(typed, it) },
                    onBack = { typed = typed.dropLast(1) },
                    onEnter = {
                        val total = typed.toIntOrNull()
                        if (total != null) {
                            session.enter(total)
                            typed = ""
                            // The words say to enter it dart by dart; the screen goes there, so the next thing the
                            // scorer does is the thing they were told to. Not remembered as their choice.
                            val refused = session.mark
                            if (refused is ThroMark.Refused && refused.reason == RejectionReason.DARTS_REQUIRED) {
                                mode = ThroEntryMode.DARTS
                            }
                        }
                    },
                    onUndo = undo,
                    modifier = Modifier.weight(1f),
                )
            }

            if (session.state.isComplete) {
                Key("Done", "done", Modifier.fillMaxWidth().height(56.dp), lit = true) { onDone() }
            }
        }
    }
}

/// One side of the scoreboard: name, what is left, legs. Read by TalkBack as one sentence rather than three
/// unconnected numbers.
@Composable
private fun Side(session: ThroSession, seat: Seat, modifier: Modifier) {
    val colors = LocalThroColors.current
    val throwing = session.throwerSeat == seat && session.state.winner == null
    // The thrower's figure follows the darts as they land — the engine's reading, not a subtraction here.
    val left = if (throwing) session.throwerLeft ?: session.remaining(seat) else session.remaining(seat)
    val legs = session.legs(seat)
    val spoken = buildString {
        append("${session.name(seat)}, $left left, ")
        append(if (legs == 1) "1 leg" else "$legs legs")
        if (throwing) append(", to throw")
    }
    Column(
        modifier.clearAndSetSemantics { contentDescription = spoken },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ThroText(
            session.name(seat),
            ThroTypography.label.weight(if (throwing) FontWeight.SemiBold else FontWeight.Normal),
            colors.throChalk.copy(alpha = if (throwing) 0.95f else 0.55f),
            maxLines = 1,
        )
        // The remaining score in the sport face and tabular, so it does not jitter as it counts down — the
        // figure iOS draws in `sportHero`, where this used to be Roboto Black at a size nobody chose.
        ThroText(
            "$left",
            ThroTypography.sportHero,
            colors.throChalk.copy(alpha = if (throwing) 1f else 0.62f),
        )
        ThroText(
            "$legs",
            ThroTypography.bodyLarge.family(ThroTypeRole.Family.SPORT).weight(FontWeight.Bold),
            if (throwing) colors.throGreenOnink else colors.throChalk.copy(alpha = 0.45f),
        )
    }
}

/// Total or Darts. Two segments, one of them chosen — a radio group to TalkBack.
@Composable
private fun ModeSwitch(mode: ThroEntryMode, onChoose: (ThroEntryMode) -> Unit) {
    val colors = LocalThroColors.current
    Row(
        Modifier.fillMaxWidth().height(MIN_TARGET)
            .background(colors.throChalk.copy(alpha = 0.05f), RoundedCornerShape(10.dp))
            .selectableGroup(),
    ) {
        for (option in ThroEntryMode.entries) {
            val chosen = option == mode
            Box(
                Modifier.weight(1f).fillMaxHeight()
                    .background(colors.throChalk.copy(alpha = if (chosen) 0.16f else 0f), RoundedCornerShape(10.dp))
                    .semantics { contentDescription = option.spoken }
                    .selectable(selected = chosen, role = Role.RadioButton) { onChoose(option) },
                contentAlignment = Alignment.Center,
            ) {
                ThroText(
                    option.label,
                    ThroTypography.labelStrong.weight(if (chosen) FontWeight.Bold else FontWeight.Normal),
                    colors.throChalk.copy(alpha = if (chosen) 1f else 0.6f),
                    modifier = Modifier.clearAndSetSemantics {},
                )
            }
        }
    }
}

/// The darts entered so far, three slots. Each filled slot takes back everything from it onwards, which is what a
/// player means when they point at the middle dart and say "that one was a five".
@Composable
private fun DartLine(session: ThroSession) {
    val colors = LocalThroColors.current
    Row(Modifier.fillMaxWidth().height(MIN_TARGET), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (i in 0 until Darts.HAND) {
            val dart = session.darts.getOrNull(i)
            Box(
                Modifier.weight(1f).fillMaxHeight()
                    .background(colors.throChalk.copy(alpha = if (dart == null) 0.03f else 0.10f),
                                RoundedCornerShape(10.dp))
                    .semantics {
                        contentDescription =
                            dart?.let { "${ThroDartWords.spoken(it)}, take back from here" } ?: "no dart yet"
                    }
                    .clickable(enabled = dart != null, role = Role.Button) { session.takeBackDarts(i) },
                contentAlignment = Alignment.Center,
            ) {
                ThroText(
                    dart?.let { ThroDartWords.written(it) } ?: " ",
                    ThroTypography.heading3.family(ThroTypeRole.Family.SPORT).weight(FontWeight.Bold),
                    colors.colorTextOnBoard,
                    modifier = Modifier.clearAndSetSemantics {},
                    maxLines = 1,
                )
            }
        }
    }
}

/// The keypad that takes three darts.
///
///   DOUBLE · TREBLE · UNDO          the ring for the next dart, held until it lands
///   20 … 1                          four rows of five, counting down, as on the iPhone
///   25 · BULL · MISS · ENTER        the darts with no sector, and the commit
///
/// **Sectors close once the visit is decided.** A stray tap after a checkout would otherwise turn it into a bust;
/// the session refuses such a dart too, and this is the same rule where the thumb is.
@Composable
private fun DartKeypad(
    session: ThroSession,
    ring: Ring,
    onRing: (Ring) -> Unit,
    onDart: (Dart) -> Unit,
    onUndo: () -> Unit,
    modifier: Modifier,
) {
    val open = !session.visitDecided && session.darts.size < Darts.HAND && !session.state.isComplete
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (option in listOf(Ring.DOUBLE, Ring.TREBLE)) {
                val held = ring == option
                val word = if (option == Ring.DOUBLE) "double" else "treble"
                Key(
                    word.uppercase(),
                    word,
                    Modifier.weight(1f).fillMaxHeight(),
                    lit = held,
                    enabled = open,
                    // A modifier, not a dart: it is on or off, and pressing it again puts it back to single.
                    toggled = held,
                ) { onRing(if (held) Ring.SINGLE else option) }
            }
            Key("UNDO", "undo", Modifier.weight(1f).fillMaxHeight()) { onUndo() }
        }
        for (row in ThroDartWords.rows) {
            Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (sector in row) {
                    val dart = Dart(sector, ring)
                    Key(ThroDartWords.written(dart), ThroDartWords.spoken(dart), Modifier.weight(1f).fillMaxHeight(),
                        enabled = open, sport = true) { onDart(dart) }
                }
            }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            // MISS sits beside ENTER: a slip onto it adds nothing, where the same slip onto BULL would add fifty.
            for (centre in listOf(Dart.OUTER_BULL, Dart.BULL, Dart.MISS)) {
                Key(ThroDartWords.written(centre), ThroDartWords.spoken(centre), Modifier.weight(1f).fillMaxHeight(),
                    enabled = open, sport = true) { onDart(centre) }
            }
            val ready = session.dartsMayBeEntered
            Key(ThroScoringWords.enterLabel(session).uppercase(), "enter", Modifier.weight(1.4f).fillMaxHeight(),
                lit = ready, enabled = ready) { session.enterDarts() }
        }
    }
}

@Composable
private fun TotalKeypad(
    typed: String,
    onDigit: (Int) -> Unit,
    onBack: () -> Unit,
    onEnter: () -> Unit,
    onUndo: () -> Unit,
    modifier: Modifier,
) {
    // **Every key fills its row** (PD-093). Keys were sized by their labels, so once the type roles arrived the
    // word keys — set in the UI face, smaller than the sport-face digits — came out shorter than the digits
    // beside them, and each row of keys stood in a band of empty board. A key is somewhere to put a thumb in a
    // pub, and the row's whole height is that place — Undo's row included, which used to be seven tenths of one.
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))) {
            Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (digit in row) Key("$digit", "$digit", Modifier.weight(1f).fillMaxHeight()) { onDigit(digit) }
            }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("←", "delete last digit", Modifier.weight(1f).fillMaxHeight(), enabled = typed.isNotEmpty()) { onBack() }
            Key("0", "0", Modifier.weight(1f).fillMaxHeight()) { onDigit(0) }
            Key("Enter", "enter", Modifier.weight(1f).fillMaxHeight(), lit = typed.isNotEmpty(),
                enabled = typed.isNotEmpty()) { onEnter() }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("Undo", "undo", Modifier.weight(1f).fillMaxHeight()) { onUndo() }
        }
    }
}

/// PD-001's question, where the keypad was: one question, its answers as keys, "Not sure" for an honest
/// unknown, and a way back. Nothing is written until an answer is chosen.
@Composable
private fun PromptPanel(
    prompt: ThroSession.Prompt,
    onAnswer: (Int?) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier,
) {
    val colors = LocalThroColors.current
    val (question, context) = ThroScoringWords.prompt(prompt)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ThroText(question, ThroTypography.heading2, colors.throChalk,
                 modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        ThroText(context, ThroTypography.body, colors.throChalk.copy(alpha = 0.75f))
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (option in prompt.options) {
                Key("$option", "$option", Modifier.weight(1f).fillMaxHeight(), sport = true) { onAnswer(option) }
            }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("Not sure", "not sure", Modifier.weight(1f).fillMaxHeight()) { onAnswer(null) }
            Key("Back", "back to the score", Modifier.weight(1f).fillMaxHeight()) { onCancel() }
        }
    }
}

/// A key on the board: chalk on a lighter patch of the field, brighter when it is the one to press, fainter when
/// it cannot be pressed. `description` is what TalkBack says, because "←" and "T20" are not words.
@Composable
private fun Key(
    label: String,
    description: String,
    modifier: Modifier,
    lit: Boolean = false,
    enabled: Boolean = true,
    sport: Boolean = false,
    toggled: Boolean? = null,
    onPress: () -> Unit,
) {
    val colors = LocalThroColors.current
    val press = if (toggled != null) {
        Modifier.toggleable(value = toggled, enabled = enabled, role = Role.Button) { onPress() }
            .semantics { stateDescription = if (toggled) "on" else "off" }
    } else {
        Modifier.clickable(enabled = enabled, role = Role.Button) { onPress() }
    }
    Box(
        modifier
            .heightIn(min = MIN_TARGET)
            .background(colors.throChalk.copy(alpha = if (!enabled) 0.03f else if (lit) 0.16f else 0.07f),
                        RoundedCornerShape(10.dp))
            // Said on the node that is pressed, so TalkBack reads "double 16, button" rather than a button with
            // no name beside a label nobody can press.
            .semantics { contentDescription = description }
            .then(press),
        contentAlignment = Alignment.Center,
    ) {
        // Digits and darts in the sport face, like every figure; the word keys in the UI face.
        ThroText(
            label,
            if (!sport && label.length > 2) ThroTypography.labelStrong.weight(FontWeight.Bold)
            else ThroTypography.heading2.family(ThroTypeRole.Family.SPORT).weight(FontWeight.SemiBold),
            colors.throChalk.copy(alpha = if (!enabled) 0.3f else if (lit) 1f else 0.85f),
            modifier = Modifier.clearAndSetSemantics {},
            maxLines = 1,
        )
    }
}

