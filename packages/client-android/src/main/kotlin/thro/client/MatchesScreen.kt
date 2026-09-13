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
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
                BasicText("Your darts", modifier = Modifier.weight(1f), style = TextStyle(
                    color = colors.colorTextOnBoard, fontSize = 30.sp, fontWeight = FontWeight.Black,
                ))
                Box(
                    Modifier.clickable { onBack() }.padding(horizontal = 8.dp, vertical = 6.dp),
                ) {
                    BasicText("Done", style = TextStyle(
                        color = colors.throGreenOnink, fontSize = 17.sp, fontWeight = FontWeight.Bold,
                    ))
                }
            }

            if (rows.isEmpty()) {
                // Not "no matches" — they know that. What they do not know is that this phone is going to
                // keep them, which is the reason to score one here rather than on a beer mat.
                BasicText(ThroMatchList.NOTHING_YET, style = TextStyle(
                    color = colors.throChalk.copy(alpha = 0.65f), fontSize = 17.sp,
                ))
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
                BasicText(row.title, modifier = Modifier.weight(1f), style = TextStyle(
                    color = colors.colorTextOnBoard, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
                ))
                // The score in the same green the result screen gives it, so a glance down the list and a
                // glance at a result are reading the same thing. Absent when it cannot be trusted.
                row.score?.let {
                    BasicText(it, style = TextStyle(
                        color = colors.throGreenOnink, fontSize = 20.sp, fontWeight = FontWeight.Black,
                    ))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BasicText(ThroMatchList.day(row.record.startedAt), style = TextStyle(
                    color = colors.throChalk.copy(alpha = 0.55f), fontSize = 13.sp,
                ))
                BasicText(row.status, style = TextStyle(
                    color = if (row.unreadable != null) colors.throDisputed
                            else colors.throChalk.copy(alpha = 0.55f),
                    fontSize = 13.sp,
                    fontWeight = if (row.unreadable != null) FontWeight.Bold else FontWeight.Normal,
                ))
                row.wonBy?.let {
                    BasicText("$it won", style = TextStyle(
                        color = colors.throGreenOnink.copy(alpha = 0.85f), fontSize = 13.sp,
                    ))
                }
            }
            // The reason, in full, under the row. A status word alone would tell somebody their match is
            // broken without telling them anything they could act on or repeat to us.
            row.unreadable?.let {
                BasicText(it, style = TextStyle(
                    color = colors.throDisputed.copy(alpha = 0.8f), fontSize = 12.sp,
                ))
            }
            if (carryOnable) {
                BasicText("Tap to carry on", style = TextStyle(
                    color = colors.throGreenOnink, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                ))
            }
        }
    }
}
