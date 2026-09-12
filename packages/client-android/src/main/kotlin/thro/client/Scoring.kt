package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

            BasicText(
                ThroScoringWords.say(session, typed),
                style = TextStyle(color = colors.throGreenOnink, fontSize = 16.sp,
                                  fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
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
        BasicText(
            session.name(seat),
            style = TextStyle(color = colors.throChalk.copy(alpha = if (throwing) 0.95f else 0.55f),
                              fontSize = 15.sp, fontWeight = if (throwing) FontWeight.SemiBold else FontWeight.Normal),
        )
        BasicText(
            "${session.remaining(seat)}",
            style = TextStyle(color = colors.throChalk.copy(alpha = if (throwing) 1f else 0.62f),
                              fontSize = 68.sp, fontWeight = FontWeight.Black),
        )
        BasicText(
            "${session.legs(seat)}",
            style = TextStyle(color = if (throwing) colors.throGreenOnink else colors.throChalk.copy(alpha = 0.45f),
                              fontSize = 18.sp, fontWeight = FontWeight.Bold),
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
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))) {
            Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (digit in row) Key("$digit", Modifier.weight(1f)) { onDigit(digit) }
            }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("←", Modifier.weight(1f)) { onBack() }
            Key("0", Modifier.weight(1f)) { onDigit(0) }
            Key("Enter", Modifier.weight(1f), lit = typed.isNotEmpty()) { onEnter() }
        }
        Row(Modifier.fillMaxWidth().weight(0.7f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Key("Undo", Modifier.weight(1f)) { onUndo() }
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
        BasicText(label, style = TextStyle(
            color = colors.throChalk.copy(alpha = if (lit) 1f else 0.85f),
            fontSize = if (label.length > 2) 18.sp else 26.sp,
            fontWeight = FontWeight.SemiBold,
        ))
    }
}
