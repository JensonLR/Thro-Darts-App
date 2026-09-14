package thro.client

import androidx.compose.foundation.background
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import thro.design.ThroColors
import thro.design.throDarkColors
import thro.design.throLightColors

// The board, on Android (PD-081).
//
// **The same three stops, from the same generator.** `ThroBoard` on iOS is a radial gradient from
// `colorBoardLit` through `colorBoardField` to `colorBoardSunken`, with the lamp above centre and a reach
// of 0.86 of the longer side — under that the corners go flat black before the edge and the board reads as
// a vignette filter; over it the pool stops being a pool. Those numbers are the design's, not this
// platform's, so they are repeated here as numbers rather than re-chosen by eye.
//
// What is deliberately *not* here yet is the chalk grain. On iOS it is a seeded scatter of specks drawn
// into a `Canvas`; it is the difference between a board and a green rectangle, and it is the next thing.

/// The palette in force. A composition local rather than a parameter on every component, because the
/// alternative is threading a palette through forty call sites and forgetting one.
public val LocalThroColors: androidx.compose.runtime.ProvidableCompositionLocal<ThroColors> =
    staticCompositionLocalOf { throLightColors() }

@Composable
public fun ThroTheme(dark: Boolean = false, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalThroColors provides if (dark) throDarkColors() else throLightColors()) {
        content()
    }
}

/// The lamp's height in the frame, and its reach as a fraction of the longer side. iOS's numbers.
private const val LAMP_Y = 0.30f
private const val REACH = 0.86f

/// A board: the lit field everything in THRØ is drawn on.
@Composable
public fun ThroBoard(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val colors = LocalThroColors.current
    Box(
        modifier
            .fillMaxSize()
            .background(colors.colorBoardField)
            .drawBehind {
                // Drawn from the measured size rather than from a percentage brush, so the lamp is where
                // the design puts it on every screen shape instead of wherever the default centre lands.
                drawRect(
                    Brush.radialGradient(
                        0f to colors.colorBoardLit,
                        0.55f to colors.colorBoardField,
                        1f to colors.colorBoardSunken,
                        center = lampCentre(size.width, size.height),
                        radius = lampRadius(size.width, size.height),
                    ),
                )
            },
        content = content,
    )
}

/// Where the lamp hangs, for a box of this size. Kept as a function so the arithmetic is in one place and
/// can be tested without a screen.
public fun lampCentre(width: Float, height: Float): Offset = Offset(width / 2f, height * LAMP_Y)

/// The lamp's radius for a box of this size: a fraction of the LONGER side, which is what stops a tall
/// phone and a wide tablet reading as two different rooms.
public fun lampRadius(width: Float, height: Float): Float = maxOf(width, height) * REACH
