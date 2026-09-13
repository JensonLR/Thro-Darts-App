package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// Two names and a start. Nothing else on this screen has earned its place yet: the format is 501, best of
// five, double out — the defaults `NewMatch` already carries — and every option added here is an option
// somebody has to get past before they can throw.

@Composable
public fun ThroSetupScreen(
    carryOn: ThroCarryOn? = null,
    onCarryOn: () -> Unit = {},
    /// How many matches this phone is holding. Zero hides the way in entirely: a door to an empty room
    /// is worse than no door, because somebody opens it once and learns not to.
    kept: Int = 0,
    onSeeKept: () -> Unit = {},
    onStart: (String, String) -> Unit,
) {
    var home by remember { mutableStateOf("") }
    var away by remember { mutableStateOf("") }
    val colors = LocalThroColors.current

    ThroBoard {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 28.dp)) {
            // **The mark, on the front door** (PD-093). This is the screen the app opens onto, and it was the one
            // front door with no brand on it: iOS opens onto a masthead carrying the wordmark, and this opened onto
            // a question in the middle of an empty board. Top left, near the width the iOS masthead gives it, drawn
            // from the generated vector rather than set in a font.
            Image(
                painter = painterResource(R.drawable.thro_wordmark),
                contentDescription = "THRØ",
                colorFilter = ColorFilter.tint(colors.colorTextOnBoard),
                modifier = Modifier.padding(top = 20.dp).width(120.dp),
            )
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                // **Offered, not resumed for you.** A match left half-scored three weeks ago is not the match
                // somebody has just opened the app to start, and dropping them into it would be the app
                // deciding. Naming the players and the score is enough for them to know which it is.
                if (carryOn != null) {
                    Box(
                        Modifier.fillMaxWidth()
                            .background(colors.throChalk.copy(alpha = 0.14f), RoundedCornerShape(10.dp))
                            .clickable { onCarryOn() }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                    ) {
                        Column {
                            ThroText("Carry on", ThroTypography.eyebrow, colors.throGreenOnink)
                            ThroText(carryOn.line, ThroTypography.bodyLarge.weight(FontWeight.SemiBold), colors.colorTextOnBoard)
                        }
                    }
                }
                ThroText("Who is playing?", ThroTypography.heading1, colors.colorTextOnBoard)
                NameField(home, "First to throw") { home = it }
                NameField(away, "The other player") { away = it }
                ThroText("501, best of five, double out.", ThroTypography.metadata, colors.throChalk.copy(alpha = 0.55f))
                Box(
                    Modifier.fillMaxWidth()
                        .background(colors.throChalk.copy(alpha = if (ThroSetupWords.ready(home, away)) 0.18f else 0.06f),
                                    RoundedCornerShape(10.dp))
                        .clickable(enabled = ThroSetupWords.ready(home, away)) {
                            onStart(ThroSetupWords.tidy(home), ThroSetupWords.tidy(away))
                        }
                        .padding(vertical = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    ThroText("Start", ThroTypography.heading3,
                             colors.throChalk.copy(alpha = if (ThroSetupWords.ready(home, away)) 1f else 0.45f))
                }
                if (kept > 0) {
                    Box(
                        Modifier.fillMaxWidth().clickable { onSeeKept() }.padding(vertical = 6.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        ThroText(ThroSetupWords.kept(kept), ThroTypography.label, colors.throGreenOnink)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun NameField(value: String, placeholder: String, onChange: (String) -> Unit) {
    val colors = LocalThroColors.current
    Box(
        Modifier.fillMaxWidth()
            .background(colors.throChalk.copy(alpha = 0.08f), RoundedCornerShape(10.dp))
            .padding(horizontal = 14.dp, vertical = 14.dp),
    ) {
        if (value.isEmpty()) {
            ThroText(placeholder, ThroTypography.bodyLarge, colors.throChalk.copy(alpha = 0.4f))
        }
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            textStyle = ThroTypography.bodyLarge.weight(FontWeight.SemiBold).style(colors.colorTextOnBoard),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.throGreenOnink),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/// A match the journal is still holding, said the way it will be shown.
public data class ThroCarryOn(val line: String)

/// The rules about the two names, apart from the drawing.
public object ThroSetupWords {
    /// Trailing spaces are not part of anybody's name, and a name that is only spaces is not a name.
    public fun tidy(name: String): String = name.trim()

    /// The way in to the list, counted rather than named — *"Your darts"* alone gives no reason to press it
    /// and *"1 matches"* is the oldest bug in software.
    public fun kept(n: Int): String = if (n == 1) "Your darts · 1 match" else "Your darts · $n matches"

    /// **Both named, and not the same person.** The engine refuses a competitor playing itself with a
    /// `require`, which would crash rather than explain — so it never gets the chance.
    public fun ready(home: String, away: String): Boolean {
        val h = tidy(home)
        val a = tidy(away)
        return h.isNotEmpty() && a.isNotEmpty() && !h.equals(a, ignoreCase = true)
    }
}
