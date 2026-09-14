package thro.client

import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import thro.design.ThroSpacing
import thro.design.ThroType
import kotlin.math.roundToInt

// The brand's type on Android (PD-093).
//
// **Android was set entirely in Roboto.** Every string on every screen was a `TextStyle` with a hand-picked
// `fontSize` and no `fontFamily`, so the phone's own typeface drew THRØ — twelve different sizes, five of
// them not on the approved scale, and none of them in Archivo or IBM Plex Sans Condensed. The generated
// `ThroType` had the sizes all along; nothing read them.
//
// **The roles are the iOS roles, transcribed, and a guard holds them equal.** The weights and trackings
// live in `ThroTypography` in Swift rather than in the token source, so there is no generator to share and
// two copies are unavoidable. `tools/check_type_parity.py` reads both files and fails if a role's family,
// weight, tracking, case or numerals differ — the same bargain the journal's parity check makes.

/// The two families, from the faces the build copies out of `apps/ios/ThroDarts/Fonts`.
public object ThroFonts {
    public val ui: FontFamily = FontFamily(
        Font(R.font.archivo_regular, FontWeight.Normal),
        Font(R.font.archivo_medium, FontWeight.Medium),
        Font(R.font.archivo_semibold, FontWeight.SemiBold),
        Font(R.font.archivo_bold, FontWeight.Bold),
        Font(R.font.archivo_extrabold, FontWeight.ExtraBold),
        Font(R.font.archivo_black, FontWeight.Black),
    )

    /// IBM Plex Sans Condensed stops at Bold, as on iOS: a heavier request matches the heaviest face.
    public val sport: FontFamily = FontFamily(
        Font(R.font.ibmplexsanscondensed_regular, FontWeight.Normal),
        Font(R.font.ibmplexsanscondensed_medium, FontWeight.Medium),
        Font(R.font.ibmplexsanscondensed_semibold, FontWeight.SemiBold),
        Font(R.font.ibmplexsanscondensed_bold, FontWeight.Bold),
    )
}

/// One type role: family, size, line, weight, tracking, case, numerals. Colour is the caller's.
public data class ThroTypeRole(
    val family: Family,
    val size: TextUnit,
    val line: Dp,
    val weight: FontWeight,
    val trackingEm: Float = 0f,
    val uppercase: Boolean = false,
    val tabularNumerals: Boolean = false,
) {
    public enum class Family { UI, SPORT }

    /// `sp`, so Android's font scale applies — the same reason the generated sizes are `sp`.
    public fun style(color: Color, align: TextAlign = TextAlign.Unspecified): TextStyle = TextStyle(
        color = color,
        fontFamily = if (family == Family.UI) ThroFonts.ui else ThroFonts.sport,
        fontSize = size,
        lineHeight = line.value.sp,
        fontWeight = weight,
        letterSpacing = trackingEm.em,
        fontFeatureSettings = if (tabularNumerals) "tnum" else null,
        textAlign = align,
    )

    public fun weight(w: FontWeight): ThroTypeRole = copy(weight = w)

    /// Sport figures are always tabular, as on iOS, so a score does not jitter as it changes.
    public fun family(f: Family): ThroTypeRole = copy(family = f, tabularNumerals = f == Family.SPORT || tabularNumerals)
}

/// The roles, sized from the token layer. The names are the Swift names.
public object ThroTypography {
    public val scoreHero: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.SPORT, size = ThroType.typographyScoreHeroSize,
        line = ThroSpacing.typographyScoreHeroLine, weight = FontWeight.Bold,
        trackingEm = -0.03f, tabularNumerals = true,
    )
    public val sportHero: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.SPORT, size = ThroType.typographySportHeroSize,
        line = ThroSpacing.typographySportHeroLine, weight = FontWeight.Bold,
        trackingEm = -0.02f, tabularNumerals = true,
    )
    public val ratingHero: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.SPORT, size = ThroType.typographyRatingHeroSize,
        line = ThroSpacing.typographyRatingHeroLine, weight = FontWeight.Bold,
        trackingEm = -0.02f, tabularNumerals = true,
    )
    public val display: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyDisplaySize,
        line = ThroSpacing.typographyDisplayLine, weight = FontWeight.ExtraBold,
        trackingEm = -0.015f,
    )
    public val heading1: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyHeading1Size,
        line = ThroSpacing.typographyHeading1Line, weight = FontWeight.ExtraBold,
        trackingEm = -0.01f,
    )
    public val heading2: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyHeading2Size,
        line = ThroSpacing.typographyHeading2Line, weight = FontWeight.Bold,
    )
    public val heading3: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyHeading3Size,
        line = ThroSpacing.typographyHeading3Line, weight = FontWeight.Bold,
    )
    public val bodyLarge: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyBodyLargeSize,
        line = ThroSpacing.typographyBodyLargeLine, weight = FontWeight.Normal,
    )
    public val body: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyBodyDefaultSize,
        line = ThroSpacing.typographyBodyDefaultLine, weight = FontWeight.Normal,
    )
    public val label: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyLabelDefaultSize,
        line = ThroSpacing.typographyLabelDefaultLine, weight = FontWeight.SemiBold,
    )
    public val labelStrong: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyLabelStrongSize,
        line = ThroSpacing.typographyLabelStrongLine, weight = FontWeight.Bold,
    )
    public val metadata: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyMetadataSize,
        line = ThroSpacing.typographyMetadataLine, weight = FontWeight.Normal,
    )
    public val eyebrow: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.UI, size = ThroType.typographyEyebrowSize,
        line = ThroSpacing.typographyEyebrowLine, weight = FontWeight.SemiBold,
        trackingEm = 0.09f, uppercase = true,
    )
    public val boardHero: ThroTypeRole = ThroTypeRole(
        family = ThroTypeRole.Family.SPORT, size = ThroType.typographyScoreHeroSize,
        line = ThroSpacing.typographyScoreHeroLine, weight = FontWeight.Bold,
        trackingEm = 0f, tabularNumerals = true,
    )
}

/// Text in a role. Upper-cases where the role says so, because Compose's `TextStyle` has no text-transform.
@Composable
public fun ThroText(
    text: String,
    role: ThroTypeRole,
    color: Color,
    modifier: Modifier = Modifier,
    align: TextAlign = TextAlign.Unspecified,
    maxLines: Int = Int.MAX_VALUE,
) {
    BasicText(
        text = if (role.uppercase) text.uppercase() else text,
        modifier = modifier,
        style = role.style(color, align),
        maxLines = maxLines,
        overflow = if (maxLines == Int.MAX_VALUE) TextOverflow.Clip else TextOverflow.Ellipsis,
    )
}
