package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// The notice about people's information, on the first screen (PD-094, PD-097).
//
// The iPhone's card, on the board: the warning surface, the title and the summary in the words for this reader, and two
// ways out — **Read what happened**, which opens the full account on the web site, and **Put away**, which takes the card
// off the screen until the notice changes. It is the one thing on this screen THRØ put there rather than the phone, so it
// says what it is first; the iPhone does that with a warning glyph, and Android, with no icon set, does it in words.

@Composable
public fun ThroNoticeCard(
    words: ThroNotice.Words,
    onRead: () -> Unit,
    onPutAway: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalThroColors.current
    Column(
        modifier
            .fillMaxWidth()
            .background(colors.colorStatusWarningSurface, RoundedCornerShape(10.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        ThroText("About your information", ThroTypography.eyebrow, colors.colorStatusWarning)
        ThroText(words.title, ThroTypography.label.weight(FontWeight.Bold), colors.colorTextPrimary)
        ThroText(words.summary, ThroTypography.metadata, colors.colorTextSecondary)
        Row(
            Modifier.padding(top = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .background(colors.colorTextPrimary, RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button, onClick = onRead)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                ThroText("Read what happened", ThroTypography.label.weight(FontWeight.SemiBold),
                         colors.colorStatusWarningSurface)
            }
            Box(Modifier.clickable(role = Role.Button, onClick = onPutAway).padding(vertical = 10.dp)) {
                ThroText("Put away", ThroTypography.label, colors.colorTextSecondary)
            }
        }
    }
}
