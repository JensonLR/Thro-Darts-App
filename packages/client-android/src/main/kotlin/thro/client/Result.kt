package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import thro.journal.Seat

// A finished match, on Android (PD-084).
//
// **It says how the result is known.** Every figure in THRØ carries where it came from, and a result is the
// biggest figure there is. On this phone, right now, a match scored here is *self-reported*: one person held
// the phone and typed the numbers, and nobody has agreed to them. iOS has the whole of PD-011 — both players
// confirming on one device, a dispute if either refuses — and Android has none of it yet. So the word on the
// screen is the true one, not the flattering one.

@Composable
public fun ThroResultScreen(session: ThroSession, onAgain: () -> Unit) {
    val colors = LocalThroColors.current
    ThroBoard {
        Column(
            Modifier.align(Alignment.Center).safeDrawingPadding().padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            BasicText(ThroResultWords.winner(session), style = TextStyle(
                color = colors.colorTextOnBoard, fontSize = 40.sp, fontWeight = FontWeight.Black,
                textAlign = TextAlign.Center,
            ))
            BasicText(ThroResultWords.scoreline(session), style = TextStyle(
                color = colors.throGreenOnink, fontSize = 52.sp, fontWeight = FontWeight.Black,
            ))
            BasicText(ThroResultWords.verified(), style = TextStyle(
                color = colors.throChalk.copy(alpha = 0.6f), fontSize = 14.sp, textAlign = TextAlign.Center,
            ))
            Box(
                Modifier.fillMaxWidth().padding(top = 18.dp)
                    .background(colors.throChalk.copy(alpha = 0.16f), RoundedCornerShape(10.dp))
                    .clickable { onAgain() }
                    .padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                BasicText("Another", style = TextStyle(
                    color = colors.throChalk, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                ))
            }
        }
    }
}

/// What a finished match says.
public object ThroResultWords {

    public fun winner(session: ThroSession): String {
        val winner = session.state.winner ?: return "No result"
        val seat = if (winner == session.state.home) Seat.HOME else Seat.AWAY
        return "${session.name(seat)} wins"
    }

    /// The legs, home first, always in the order the two sides are drawn. Never sorted so the winner leads:
    /// a scoreline whose order changes with the result is a scoreline nobody can read at a glance.
    public fun scoreline(session: ThroSession): String =
        "${session.legs(Seat.HOME)}–${session.legs(Seat.AWAY)}"

    /// **Self-reported, and it says so.** PD-011's confirmation is on iOS and not here, so this result has
    /// one person's word behind it. Saying "confirmed" would be the app claiming something nobody did.
    public fun verified(): String =
        "Self-reported: scored on this phone, and nobody has confirmed it. Kept here whatever happens next."
}
