package thro.org

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * A club's own colour, and the rule that keeps the app readable whatever it picks.
 *
 * The founder asked for clubs and leagues to customise, and for everything to be "utterly beautiful
 * all round". Those two pull against each other the moment somebody picks a yellow: a colour chosen
 * for a badge is not a colour chosen to carry text, and an app that simply obeys will show a club
 * their own name at 1.4:1 on the day they join.
 *
 * So the accent is not trusted. It is measured, in the same absolute terms the design tokens are
 * held to (`packages/design-tokens/build.py`), and:
 *
 *  - the text that sits ON the accent is CHOSEN, not configured — whichever of the brand's two
 *    neutrals reads better against it;
 *  - an accent where neither neutral reaches the floor would be REFUSED, with the ratio it was
 *    measured at — though with the palette as it stands that cannot happen, and the reason is worth
 *    knowing: the brand's two neutrals sit near the ends of the luminance range, so the worst any
 *    colour can do against the better of them is 4.17:1, at a luminance of 0.183. `BrandingTest`
 *    proves it by sweep. The refusal stays as a guard on the palette, not on the club;
 *  - the accent is never used as text on the app's own surfaces unless it passes there too, and
 *    `onSurface` reports whether it may be.
 *
 * That is a guarantee a club cannot switch off, and it is what "customisable" has to mean if the
 * result is still going to be beautiful.
 */
@JvmInline
public value class Colour private constructor(public val rgb: Int) {

    public val hex: String get() = "#%06X".format(rgb)
    public val red: Int get() = (rgb shr 16) and 0xFF
    public val green: Int get() = (rgb shr 8) and 0xFF
    public val blue: Int get() = rgb and 0xFF

    public companion object {
        /**
         * `#RRGGBB`, with or without the hash, in either case. Three-digit shorthand is refused
         * rather than expanded: a club pasting `#fc0` and getting `#ffcc00` is a guess about what
         * they meant, and the difference is visible.
         */
        public fun of(text: String): Colour {
            val t = text.trim().removePrefix("#")
            require(t.length == 6 && t.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
                "a colour must be six hexadecimal digits, as #RRGGBB — got \"$text\""
            }
            return Colour(t.toInt(16))
        }

        public fun rgb(red: Int, green: Int, blue: Int): Colour {
            require(red in 0..255 && green in 0..255 && blue in 0..255) { "each channel is 0..255" }
            return Colour((red shl 16) or (green shl 8) or blue)
        }
    }
}

/**
 * Contrast, by WCAG 2.x relative luminance. The same arithmetic as the token gate, written here
 * because this package is an independent build and a shared copy that drifts is worse than two that
 * are each tested. `BrandContrastTest` holds it against the values the token gate publishes.
 */
public object Contrast {
    /** Body text. */
    public const val TEXT_MINIMUM: Double = 4.5
    /** Large text, and the boundary of a control. */
    public const val LARGE_TEXT_MINIMUM: Double = 3.0

    private fun channel(v: Int): Double {
        val s = v / 255.0
        return if (s <= 0.04045) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
    }

    public fun luminance(c: Colour): Double =
        0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)

    public fun ratio(a: Colour, b: Colour): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/**
 * The brand's two neutrals — the only two colours text is ever set in — and the two surfaces the app
 * paints. Taken from the generated token layer; `BrandContrastTest` holds them to it.
 */
public object Palette {
    /** `colorTextPrimary`, light theme: the app's ink. */
    public val ink: Colour = Colour.of("#101211")
    /** `colorTextInverse`, light theme: the chalk the dark screens are written in. */
    public val chalk: Colour = Colour.of("#F7F6F2")
    /** `colorBackgroundPrimary`, light theme. */
    public val surfaceLight: Colour = Colour.of("#F7F6F2")
    /** `colorBackgroundPrimary`, dark theme. */
    public val surfaceDark: Colour = Colour.of("#101211")
    /** `throGreen`: the brand's own, and what a club wears until it chooses. */
    public val brandGreen: Colour = Colour.of("#0F3D2E")

    public val textColours: List<Colour> = listOf(ink, chalk)
    public val surfaces: List<Colour> = listOf(surfaceLight, surfaceDark)
}

/**
 * What was decided about one accent, and why. Returned rather than thrown for the passing case so a
 * caller can show the reasoning — a club that is told "this reads at 2.9:1, and 3:1 is the floor"
 * can pick a better colour; a club told "invalid" cannot.
 */
public data class AccentVerdict(
    val accent: Colour,
    /** Whichever neutral reads better ON the accent. Chosen, never configured. */
    val foreground: Colour,
    /** The ratio `foreground` achieves on `accent`. */
    val ratio: Double,
    /** Whether the accent may also be used AS text, on the app's own surfaces. */
    val usableAsText: Boolean,
    /** The worst ratio the accent achieves as text across the app's surfaces. */
    val asTextRatio: Double,
) {
    public val carriesText: Boolean get() = ratio >= Contrast.TEXT_MINIMUM

    public fun explain(): String = buildString {
        append("${accent.hex}: text on it is ${foreground.hex} at ")
        append(String.format("%.2f", ratio)).append(":1")
        append(if (carriesText) " (passes 4.5:1)" else " (below 4.5:1, so large text only)")
        append("; as text on the app's surfaces it reaches ")
        append(String.format("%.2f", asTextRatio)).append(":1")
        append(if (usableAsText) " and may be used for text" else " and may not be used for text")
    }
}

public object BrandCheck {
    /**
     * Measures an accent. Never throws: a verdict is information, and `Branding` is where the
     * refusal happens.
     */
    public fun verdict(accent: Colour): AccentVerdict {
        val best = Palette.textColours.maxBy { Contrast.ratio(accent, it) }
        val onSurfaces = Palette.surfaces.minOf { Contrast.ratio(accent, it) }
        return AccentVerdict(
            accent = accent,
            foreground = best,
            ratio = Contrast.ratio(accent, best),
            usableAsText = onSurfaces >= Contrast.TEXT_MINIMUM,
            asTextRatio = onSurfaces,
        )
    }
}

/** Where a logo or an avatar lives. An opaque handle: this package stores nothing and fetches nothing. */
@JvmInline
public value class AssetRef(public val value: String) {
    init { require(value.isNotBlank()) { "an asset reference cannot be blank" } }
}

/**
 * A club's identity as it appears in the app.
 *
 * The accent is refused at construction if nothing legible can sit on it — the same shape as the
 * engine refusing a format it cannot score, and for the same reason: a value that cannot be rendered
 * honestly must not be storable, because by the time it reaches a screen the only options left are
 * bad ones.
 */
public data class Branding(
    val accent: Colour,
    val logo: AssetRef? = null,
) {
    val verdict: AccentVerdict get() = BrandCheck.verdict(accent)

    init {
        // Unreachable with the palette as it stands — the worst any colour can do is 4.17:1, which is
        // above this floor. It is kept because it is a guard on the PALETTE: if the neutrals ever move
        // towards each other, some accent becomes unreadable, and this is where that is caught rather
        // than on somebody's club page. `BrandingTest` asserts the headroom, so the day it narrows is
        // the day a test says so.
        val v = BrandCheck.verdict(accent)
        require(v.ratio >= Contrast.LARGE_TEXT_MINIMUM) {
            "accent ${accent.hex} cannot carry legible text: the better of the brand's two neutrals " +
                "(${v.foreground.hex}) reaches only ${String.format("%.2f", v.ratio)}:1 against it, " +
                "and ${Contrast.LARGE_TEXT_MINIMUM}:1 is the floor. Pick a darker or lighter shade."
        }
    }

    public companion object {
        /** A club that has chosen nothing wears the brand's own green. */
        public val default: Branding = Branding(accent = Palette.brandGreen)
    }
}
