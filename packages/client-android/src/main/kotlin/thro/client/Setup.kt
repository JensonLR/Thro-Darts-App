package thro.client

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import thro.engine.BustRule
import thro.journal.NewMatch
import thro.journal.Seat

// Two names, the format, and a start — on one screen.
//
// **The format was a caption, and the caption was the only format there was.** "501, best of five, double out"
// sat under the names as grey text, so a pub that plays 301, or best of three, or keeps the darts before a bust,
// could not score its own match on Android at all. The choices are now the iPhone's — game, legs, who throws
// first, and what a bust does — each already set to what most players expect, so somebody who wants a standard
// match still only types two names and presses Start.

@Composable
public fun ThroSetupScreen(
    carryOn: ThroCarryOn? = null,
    onCarryOn: () -> Unit = {},
    /// How many matches this phone is holding. Zero hides the way in entirely: a door to an empty room
    /// is worse than no door, because somebody opens it once and learns not to.
    kept: Int = 0,
    onSeeKept: () -> Unit = {},
    /// The notice about people's information (PD-097), in the words for this reader — or nothing, which is almost always.
    notice: ThroNotice.Reading? = null,
    onReadNotice: () -> Unit = {},
    onPutAwayNotice: () -> Unit = {},
    onStart: (NewMatch) -> Unit,
) {
    var home by rememberSaveable { mutableStateOf("") }
    var away by rememberSaveable { mutableStateOf("") }
    var game by rememberSaveable { mutableStateOf(501) }
    var legs by rememberSaveable { mutableStateOf(5) }
    var first by rememberSaveable { mutableStateOf(Seat.HOME) }
    var bustRule by rememberSaveable { mutableStateOf(BustRule.RESTORE_VISIT) }
    val colors = LocalThroColors.current
    val ready = ThroSetupWords.ready(home, away)

    ThroBoard {
        // Fills the screen when it fits, and scrolls only when it does not — a large font size, a small phone, the
        // keyboard up. The column's minimum height is the screen's, so the two spacers still centre the form.
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight)
                .padding(horizontal = 28.dp),
        ) {
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
            // Under the mark, where the iPhone puts it under the masthead: before anything this screen asks for, because
            // it is the one thing here THRØ has to tell somebody rather than ask them.
            if (notice != null) {
                ThroNoticeCard(notice.words, onRead = onReadNotice, onPutAway = onPutAwayNotice,
                               modifier = Modifier.padding(top = 18.dp))
            }
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 16.dp)) {
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
                ThroText("Who is playing?", ThroTypography.heading1, colors.colorTextOnBoard,
                         modifier = Modifier.semantics { heading() })
                NameField(home, "Player one") { home = it }
                NameField(away, "Player two") { away = it }

                Choices("Game", listOf(301, 501, 701), game, { "$it" }) { game = it }
                Choices("Best of", listOf(3, 5, 7, 9), legs, { "$it" }, spoken = { "best of $it legs" }) { legs = it }
                Choices("First", listOf(Seat.HOME, Seat.AWAY), first,
                        { ThroSetupWords.seatName(it, home, away) },
                        spoken = { "${ThroSetupWords.seatName(it, home, away)} throws first" }) { first = it }
                // Standard first and chosen: it is what every player expects, and what a first match should be. The
                // other is the pub-league rule — on 40, a 20 then a D15 leaves 20 rather than 40 — said plainly, since
                // somebody who has never met it needs to know what they are choosing.
                Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (rule in BustRule.entries) {
                        RuleRow(ThroSetupWords.bustRule(rule), chosen = rule == bustRule) { bustRule = rule }
                    }
                }

                Box(
                    Modifier.fillMaxWidth().padding(top = 4.dp).heightIn(min = 56.dp)
                        .background(colors.throChalk.copy(alpha = if (ready) 0.18f else 0.06f),
                                    RoundedCornerShape(10.dp))
                        .clickable(enabled = ready, role = Role.Button) {
                            onStart(ThroSetupWords.match(home, away, game, legs, first, bustRule))
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    ThroText("Start", ThroTypography.heading3,
                             colors.throChalk.copy(alpha = if (ready) 1f else 0.45f))
                }
                if (kept > 0) {
                    Box(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button) { onSeeKept() },
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
}

/// A labelled row of segments, one of them chosen — a radio group to TalkBack. Every segment is at least 48dp tall.
@Composable
private fun <T> Choices(
    label: String,
    options: List<T>,
    chosen: T,
    text: (T) -> String,
    spoken: (T) -> String = text,
    onChoose: (T) -> Unit,
) {
    val colors = LocalThroColors.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        ThroText(label, ThroTypography.label, colors.throChalk.copy(alpha = 0.7f),
                 modifier = Modifier.width(64.dp).clearAndSetSemantics {}, maxLines = 1)
        Row(
            Modifier.weight(1f).height(48.dp)
                .background(colors.throChalk.copy(alpha = 0.06f), RoundedCornerShape(10.dp))
                .selectableGroup(),
        ) {
            for (option in options) {
                val on = option == chosen
                Box(
                    Modifier.weight(1f).fillMaxHeight()
                        .background(colors.throChalk.copy(alpha = if (on) 0.18f else 0f), RoundedCornerShape(10.dp))
                        .semantics { contentDescription = spoken(option) }
                        .selectable(selected = on, role = Role.RadioButton) { onChoose(option) },
                    contentAlignment = Alignment.Center,
                ) {
                    ThroText(text(option),
                             ThroTypography.labelStrong.weight(if (on) FontWeight.Bold else FontWeight.Normal),
                             colors.throChalk.copy(alpha = if (on) 1f else 0.6f),
                             modifier = Modifier.padding(horizontal = 6.dp).clearAndSetSemantics {}, maxLines = 1)
                }
            }
        }
    }
}

/// One of the two bust rules, as a full-width row: the words are too long for a segment, and they are the point.
@Composable
private fun RuleRow(words: String, chosen: Boolean, onChoose: () -> Unit) {
    val colors = LocalThroColors.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp)
            .background(colors.throChalk.copy(alpha = if (chosen) 0.16f else 0.05f), RoundedCornerShape(10.dp))
            .selectable(selected = chosen, role = Role.RadioButton, onClick = onChoose)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // A ring, filled when chosen — the radio mark, drawn in chalk rather than borrowed from Material.
        Box(
            Modifier.width(14.dp).height(14.dp)
                .background(if (chosen) colors.throGreenOnink else colors.throChalk.copy(alpha = 0.2f),
                            RoundedCornerShape(7.dp)),
        )
        ThroText(words, ThroTypography.body.weight(if (chosen) FontWeight.SemiBold else FontWeight.Normal),
                 colors.throChalk.copy(alpha = if (chosen) 1f else 0.7f))
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
    /// What each bust rule is called on the setup screen: what happens, in the words a player uses, and which one is
    /// the standard. The engine's names are for the engine.
    public fun bustRule(rule: BustRule): String = when (rule) {
        BustRule.RESTORE_VISIT -> "Bust: back to the start of the visit (standard)"
        BustRule.KEEP_SCORED_DARTS -> "Bust: keep the darts before the bust (some pub leagues)"
    }

    /// A seat on the "first" control: the name typed, or which player it is until one has been.
    public fun seatName(seat: Seat, home: String, away: String): String {
        val typed = tidy(if (seat == Seat.HOME) home else away)
        return typed.ifEmpty { if (seat == Seat.HOME) "Player one" else "Player two" }
    }

    /// The match the screen describes. Double out, as every format this screen offers is.
    public fun match(home: String, away: String, game: Int, legs: Int, first: Seat, bustRule: BustRule): NewMatch =
        NewMatch(
            homeName = tidy(home), awayName = tidy(away), startingScore = game, legsTarget = legs,
            throwFirst = first, bustRule = bustRule,
        )

    public fun kept(n: Int): String = if (n == 1) "Your darts · 1 match" else "Your darts · $n matches"

    /// **Both named, and not the same person.** The engine refuses a competitor playing itself with a
    /// `require`, which would crash rather than explain — so it never gets the chance.
    public fun ready(home: String, away: String): Boolean {
        val h = tidy(home)
        val a = tidy(away)
        return h.isNotEmpty() && a.isNotEmpty() && !h.equals(a, ignoreCase = true)
    }
}
