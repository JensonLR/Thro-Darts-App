package thro.client

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.text.TextStyle
import thro.engine.OutRule
import thro.engine.RuleTables

// The first Android screen, and what it is for.
//
// **It says what the phone can already do, in the phone's own words, and proves it.** The checkout shown
// is derived by `thro-engine` — the same Kotlin engine the conformance corpus runs against, which is the
// whole of ADR-002's claim that the rules are one implementation per language and not one per screen. A
// welcome screen that said "Android, coming soon" would have proved nothing at all.

@Composable
public fun ThroAndroidRoot() {
    ThroTheme {
        ThroBoard {
            Column(
                Modifier.align(Alignment.Center).padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                val chalk = LocalThroColors.current.throChalk
                BasicText("THRØ", style = TextStyle(color = chalk, fontSize = 64.sp,
                                                    fontWeight = FontWeight.Black, letterSpacing = 4.sp))
                BasicText(
                    "FROM THE PUB BOARD TO THE WORLD STAGE",
                    style = TextStyle(color = chalk.copy(alpha = 0.72f), fontSize = 12.sp,
                                      fontWeight = FontWeight.Medium, letterSpacing = 2.sp,
                                      textAlign = TextAlign.Center),
                )
                BasicText(
                    ThroAndroidWords.provenBySharedEngine(),
                    style = TextStyle(color = LocalThroColors.current.throGreenOnink, fontSize = 18.sp,
                                      fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
                    modifier = Modifier.padding(top = 24.dp),
                )
            }
        }
    }
}

/// What the screen says, in a type so it can be tested rather than looked at — the same rule the wrist and
/// the wall follow.
public object ThroAndroidWords {
    /// A finish, worked out here and now by the shared engine.
    ///
    /// 141 is the number to use: it has a route under double-out and it is the one the iOS tests use, so a
    /// difference between the platforms would show up as a difference in this line.
    public fun provenBySharedEngine(from: Int = 141, outRule: OutRule = OutRule.DOUBLE): String {
        val route = RuleTables.route(from, outRule)
        return if (route == null) "no route from $from" else "$from: " + route.joinToString(" ")
    }
}
