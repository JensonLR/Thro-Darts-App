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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Two names and a start. Nothing else on this screen has earned its place yet: the format is 501, best of
// five, double out — the defaults `NewMatch` already carries — and every option added here is an option
// somebody has to get past before they can throw.

@Composable
public fun ThroSetupScreen(onStart: (String, String) -> Unit) {
    var home by remember { mutableStateOf("") }
    var away by remember { mutableStateOf("") }
    val colors = LocalThroColors.current

    ThroBoard {
        Column(
            Modifier.align(Alignment.Center).safeDrawingPadding().padding(horizontal = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            BasicText("Who is playing?", style = TextStyle(
                color = colors.colorTextOnBoard, fontSize = 30.sp, fontWeight = FontWeight.Black,
            ))
            NameField(home, "First to throw") { home = it }
            NameField(away, "The other player") { away = it }
            BasicText("501, best of five, double out.", style = TextStyle(
                color = colors.throChalk.copy(alpha = 0.55f), fontSize = 14.sp,
            ))
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
                BasicText("Start", style = TextStyle(
                    color = colors.throChalk.copy(alpha = if (ThroSetupWords.ready(home, away)) 1f else 0.45f),
                    fontSize = 20.sp, fontWeight = FontWeight.Bold,
                ))
            }
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
            BasicText(placeholder, style = TextStyle(color = colors.throChalk.copy(alpha = 0.4f), fontSize = 18.sp))
        }
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            textStyle = TextStyle(color = colors.colorTextOnBoard, fontSize = 18.sp,
                                  fontWeight = FontWeight.SemiBold),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(colors.throGreenOnink),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/// The rules about the two names, apart from the drawing.
public object ThroSetupWords {
    /// Trailing spaces are not part of anybody's name, and a name that is only spaces is not a name.
    public fun tidy(name: String): String = name.trim()

    /// **Both named, and not the same person.** The engine refuses a competitor playing itself with a
    /// `require`, which would crash rather than explain — so it never gets the chance.
    public fun ready(home: String, away: String): Boolean {
        val h = tidy(home)
        val a = tidy(away)
        return h.isNotEmpty() && a.isNotEmpty() && !h.equals(a, ignoreCase = true)
    }
}
