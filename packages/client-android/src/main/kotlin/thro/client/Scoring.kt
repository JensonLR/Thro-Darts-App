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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import thro.journal.Seat

// Scoring a match on Android (PD-083).
//
// **A total, not three darts.** The iOS client has both, and per-dart entry is the larger of the two — it
// carries the evidence that makes checkout percentage computable (PD-024). This is the total keypad only,
// because the engine scores a visit and a total is the whole of what it needs; the dart keypad is a second
// screen and a second decision, not a smaller version of this one.
//
// **Every number the player sees comes from `MatchState`.** There is no running total kept beside it and
// nothing subtracted here. The one piece of local state on this screen is the digits the player has typed
// and not yet entered.

@Composable
public fun ThroScoringScreen(session: ThroSession, onDone: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    val colors = LocalThroColors.current

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

            ThroText(
                ThroScoringWords.say(session, typed),
                ThroTypography.body.weight(FontWeight.SemiBold),
                colors.throGreenOnink,
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                align = TextAlign.Center,
            )

            Keypad(
                typed = typed,
                onDigit = { typed = ThroScoringWords.typed(typed, it) },
                onBack = { typed = typed.dropLast(1) },
                onEnter = {
                    val total = typed.toIntOrNull()
                    if (total != null) { session.enter(total); typed = "" }
                },
                onUndo = { session.undo(); typed = "" },
                modifier = Modifier.weight(1f),
            )

            if (session.state.isComplete) {
                Key("Done", Modifier.fillMaxWidth(), lit = true) { onDone() }
            }
        }
    }
}

@Composable
private fun Side(session: ThroSession, seat: Seat, modifier: Modifier) {
    val colors = LocalThroColors.current
    val throwing = session.throwerSeat == seat && session.state.winner == null
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        ThroText(
            session.name(seat),
            ThroTypography.label.weight(if (throwing) FontWeight.SemiBold else FontWeight.Normal),
            colors.throChalk.copy(alpha = if (throwing) 0.95f else 0.55f),
        )
        // The remaining score in the sport face and tabular, so it does not jitter as it counts down — the
        // figure iOS draws in `sportHero`, where this used to be Roboto Black at a size nobody chose.
        ThroText(
            "${session.remaining(seat)}",
            ThroTypography.sportHero,
            colors.throChalk.copy(alpha = if (throwing) 1f else 0.62f),
        )
        ThroText(
            "${session.legs(seat)}",
            ThroTypography.bodyLarge.family(ThroTypeRole.Family.SPORT).weight(FontWeight.Bold),
            if (throwing) colors.throGreenOnink else colors.throChalk.copy(alpha = 0.45f),
        )
    }
}

@Composable
private fun Keypad(
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
    // pub, and the row's whole height is that place.
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))) {
            Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (digit in row) Key("$digit", Modifier.weight(1f).fillMaxHeight()) { onDigit(digit) }
            }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("←", Modifier.weight(1f).fillMaxHeight()) { onBack() }
            Key("0", Modifier.weight(1f).fillMaxHeight()) { onDigit(0) }
            Key("Enter", Modifier.weight(1f).fillMaxHeight(), lit = typed.isNotEmpty()) { onEnter() }
        }
        Row(Modifier.fillMaxWidth().weight(0.7f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("Undo", Modifier.weight(1f).fillMaxHeight()) { onUndo() }
        }
    }
}

/// A key on the board: chalk on a lighter patch of the field, brighter when it is the one to press.
@Composable
private fun Key(label: String, modifier: Modifier, lit: Boolean = false, onPress: () -> Unit) {
    val colors = LocalThroColors.current
    Box(
        modifier
            .background(colors.throChalk.copy(alpha = if (lit) 0.16f else 0.07f),
                        RoundedCornerShape(10.dp))
            .clickable { onPress() }
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        // Digits in the sport face, like every figure; the word keys in the UI face.
        ThroText(
            label,
            if (label.length > 2) ThroTypography.bodyLarge.weight(FontWeight.SemiBold)
            else ThroTypography.heading2.family(ThroTypeRole.Family.SPORT).weight(FontWeight.SemiBold),
            colors.throChalk.copy(alpha = if (lit) 1f else 0.85f),
        )
    }
}
