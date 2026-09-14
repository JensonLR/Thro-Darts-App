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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// Every match this phone has kept, on a screen.
//
// **The rows say what is true and nothing more.** A finished match shows its score and who won; an
// unfinished one shows the score so far and says so; an abandoned one shows neither a winner nor a
// "finished", because it has no result. A match whose journal will not replay is still listed, with the
// reason where its score would be — the alternative is a list that quietly loses a game somebody played,
// which is the one thing a record must never do.
//
// **Nothing here writes.** Tapping an unfinished match carries it on, and that is the only action; putting
// a match away and taking it back out are the journal's already (`setArchived`) and are not on this screen
// yet, because a swipe that files something permanently wants a design conversation first.

@Composable
public fun ThroMatchesScreen(
    rows: List<ThroMatchRow>,
    onCarryOn: (ThroMatchRow) -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalThroColors.current
    ThroBoard {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 22.dp)) {
            Row(
                Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ThroText("Your darts", ThroTypography.heading1, colors.colorTextOnBoard, modifier = Modifier.weight(1f))
                Box(
                    Modifier.clickable { onBack() }.padding(horizontal = 8.dp, vertical = 6.dp),
                ) {
                    ThroText("Done", ThroTypography.body.weight(FontWeight.Bold), colors.throGreenOnink)
                }
            }

            if (rows.isEmpty()) {
                // Not "no matches" — they know that. What they do not know is that this phone is going to
                // keep them, which is the reason to score one here rather than on a beer mat.
                ThroText(ThroMatchList.NOTHING_YET, ThroTypography.body, colors.throChalk.copy(alpha = 0.65f))
                return@Column
            }

            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(rows, key = { it.id.value }) { row -> MatchRow(row, onCarryOn) }
            }
        }
    }
}

@Composable
private fun MatchRow(row: ThroMatchRow, onCarryOn: (ThroMatchRow) -> Unit) {
    val colors = LocalThroColors.current
    val carryOnable = !row.complete && row.unreadable == null
    Box(
        Modifier.fillMaxWidth()
            .background(colors.throChalk.copy(alpha = 0.10f), RoundedCornerShape(10.dp))
            .then(if (carryOnable) Modifier.clickable { onCarryOn(row) } else Modifier)
            .padding(horizontal = 16.dp, vertical = 13.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ThroText(row.title, ThroTypography.bodyLarge.weight(FontWeight.SemiBold), colors.colorTextOnBoard,
                         modifier = Modifier.weight(1f))
                // The score in the same green the result screen gives it, so a glance down the list and a
                // glance at a result are reading the same thing. Absent when it cannot be trusted.
                row.score?.let {
                    ThroText(it, ThroTypography.heading3.family(ThroTypeRole.Family.SPORT), colors.throGreenOnink)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ThroText(ThroMatchList.day(row.record.startedAt), ThroTypography.metadata,
                         colors.throChalk.copy(alpha = 0.55f))
                ThroText(
                    row.status,
                    ThroTypography.metadata.weight(if (row.unreadable != null) FontWeight.Bold else FontWeight.Normal),
                    if (row.unreadable != null) colors.throDisputed else colors.throChalk.copy(alpha = 0.55f),
                )
                row.wonBy?.let {
                    ThroText("$it won", ThroTypography.metadata, colors.throGreenOnink.copy(alpha = 0.85f))
                }
            }
            // The reason, in full, under the row. A status word alone would tell somebody their match is
            // broken without telling them anything they could act on or repeat to us.
            row.unreadable?.let {
                ThroText(it, ThroTypography.metadata, colors.throDisputed.copy(alpha = 0.8f))
            }
            if (carryOnable) {
                ThroText("Tap to carry on", ThroTypography.labelStrong, colors.throGreenOnink)
            }
        }
    }
}
