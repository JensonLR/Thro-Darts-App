package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import thro.journal.Seat

// A finished match, on Android (PD-084, PD-085).
//
// **It says how the result is known.** Every figure in THRØ carries where it came from, and a result is the
// biggest figure there is. A match scored here starts *self-reported* — one person held the phone and typed
// the numbers — and the two competitors can each say whether they accept it (PD-011). What that buys is
// **two people agreeing, not two devices**: the phone cannot tell who pressed the button, so the claim it
// makes is exactly the modest one that both people were here and both said yes, under the names typed at
// the start.

@Composable
public fun ThroResultScreen(session: ThroSession, onAgain: () -> Unit) {
    val colors = LocalThroColors.current
    ThroBoard {
        Column(
            Modifier.align(Alignment.Center).safeDrawingPadding().padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ThroText(ThroResultWords.winner(session), ThroTypography.display, colors.colorTextOnBoard,
                     align = TextAlign.Center)
            ThroText(ThroResultWords.scoreline(session), ThroTypography.ratingHero, colors.throGreenOnink)
            ThroText(
                ThroResultWords.verified(session),
                ThroTypography.metadata,
                when (ThroResultWords.label(session)) {
                    ThroVerification.DISPUTED -> colors.throDisputed
                    ThroVerification.BOTH_CONFIRMED -> colors.throGreenOnink
                    ThroVerification.SELF_REPORTED -> colors.throChalk.copy(alpha = 0.6f)
                },
                align = TextAlign.Center,
            )

            // Two rows, one per competitor, and each says only what that person has said. Never a single
            // "confirm" button: one press cannot mean two people, and the whole value of the label is that
            // it does not overclaim.
            if (session.hasResult) {
                for (seat in listOf(Seat.HOME, Seat.AWAY)) {
                    Attestation(session, seat)
                }
            }

            Box(
                Modifier.fillMaxWidth().padding(top = 18.dp)
                    .background(colors.throChalk.copy(alpha = 0.16f), RoundedCornerShape(10.dp))
                    .clickable { onAgain() }
                    .padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                ThroText("Another", ThroTypography.heading3, colors.throChalk)
            }
        }
    }
}

/// One competitor's row: their name, and the two things they can say.
@Composable
private fun Attestation(session: ThroSession, seat: Seat) {
    val colors = LocalThroColors.current
    val agreed = seat in session.standing.confirmed && !session.standing.stale
    val refused = seat in session.standing.contested && !session.standing.stale
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ThroText(session.name(seat), ThroTypography.body.weight(FontWeight.SemiBold),
                 colors.throChalk.copy(alpha = 0.85f), modifier = Modifier.weight(1f))
        Choice("Agree", lit = agreed, colour = colors.throGreenOnink) { session.attest(seat, true) }
        Choice("Dispute", lit = refused, colour = colors.throDisputed) { session.attest(seat, false) }
    }
}

@Composable
private fun Choice(label: String, lit: Boolean, colour: androidx.compose.ui.graphics.Color, onPress: () -> Unit) {
    val colors = LocalThroColors.current
    Box(
        Modifier
            .background(if (lit) colour.copy(alpha = 0.24f) else colors.throChalk.copy(alpha = 0.08f),
                        RoundedCornerShape(8.dp))
            .clickable { onPress() }
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        ThroText(label, ThroTypography.labelStrong.weight(if (lit) FontWeight.Bold else FontWeight.Normal),
                 if (lit) colour else colors.throChalk.copy(alpha = 0.7f))
    }
}

/// How a result is known, as three states and nothing in between.
public enum class ThroVerification { SELF_REPORTED, BOTH_CONFIRMED, DISPUTED }

/// What a finished match says.
public object ThroResultWords {

    /// **Conservative in both directions**, which is iOS's rule and is the whole point of the label.
    ///
    /// A contest outranks a confirmation, because a result one competitor does not accept is disputed
    /// whatever the other said. And an agreement a later visit or retraction has overtaken counts for
    /// nothing — what was agreed is no longer what is recorded — so it falls back to self-reported rather
    /// than claiming an agreement nobody gave to *this* version of the result.
    public fun label(session: ThroSession): ThroVerification = when {
        session.standing.anyContest -> ThroVerification.DISPUTED
        session.standing.bothConfirmed -> ThroVerification.BOTH_CONFIRMED
        else -> ThroVerification.SELF_REPORTED
    }

    public fun winner(session: ThroSession): String {
        val winner = session.state.winner ?: return "No result"
        val seat = if (winner == session.state.home) Seat.HOME else Seat.AWAY
        return "${session.name(seat)} wins"
    }

    /// The legs, home first, always in the order the two sides are drawn. Never sorted so the winner leads:
    /// a scoreline whose order changes with the result is a scoreline nobody can read at a glance.
    public fun scoreline(session: ThroSession): String =
        "${session.legs(Seat.HOME)}–${session.legs(Seat.AWAY)}"

    /// The sentence under the scoreline. Says what is true and no more.
    public fun verified(session: ThroSession): String = when (label(session)) {
        ThroVerification.DISPUTED ->
            "Disputed: one of you does not accept this. It stays on the record, marked, because a result " +
                "nobody agrees about is still what happened."
        // **"Two people agreeing, not two devices"** — the same sentence iOS uses, and the honest limit of
        // what one phone can witness. It cannot tell who pressed the button; it can say both were here.
        ThroVerification.BOTH_CONFIRMED ->
            "${session.name(Seat.HOME)} and ${session.name(Seat.AWAY)} both confirmed this on this phone. " +
                "Two people agreeing, not two devices — under the names typed at the start."
        // **One is not both, and "nobody has confirmed it" is not true once one of them has.** Caught by
        // looking at the screen after tapping a single Agree: the label was right — one confirmation
        // claims nothing — and the sentence under it had become false. A product that insists every
        // figure says where it came from does not get to be sloppy about the sentence.
        ThroVerification.SELF_REPORTED -> when (val alone = session.standing.confirmed.singleOrNull()) {
            null -> "Self-reported: scored on this phone, and nobody has confirmed it. " +
                "Kept here whatever happens next."
            else -> "${session.name(alone)} has confirmed this and " +
                "${session.name(if (alone == Seat.HOME) Seat.AWAY else Seat.HOME)} has not. " +
                "Until both do, it is one person's word."
        }
    }
}
