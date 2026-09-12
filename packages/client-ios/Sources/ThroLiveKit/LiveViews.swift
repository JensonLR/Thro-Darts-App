import SwiftUI
import ThroTokens

// The scoreboard, drawn.
//
// **Tokens, but the system's font.** Every colour and every measure here is THRØ's, straight from
// the generated token layer, so the Lock Screen matches the app. The typeface is deliberately not:
// Archivo and IBM Plex Sans Condensed are registered by the *app's* `UIAppFonts`, and an extension
// that asked for them by name would silently fall back to the system face on a phone while looking
// right in a preview. A brand is worth more than a font here, and a wrong font is worse than none.
//
// Numerals are monospaced so 180 and 26 occupy the same width and the score does not jitter as the
// leg goes down — the same reason the scoring screen pins its keypad.

/// One player's side of the board.
public struct ThroLiveSide: View {
    private let name: String
    private let remaining: Int
    private let legs: Int
    private let throwing: Bool
    private let compact: Bool

    public init(name: String, remaining: Int, legs: Int, throwing: Bool, compact: Bool = false) {
        self.name = name
        self.remaining = remaining
        self.legs = legs
        self.throwing = throwing
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                // The one who is throwing is marked, not merely coloured: a dot survives Increase
                // Contrast, Differentiate Without Color, and being glanced at in a dark pub.
                Circle()
                    .fill(throwing ? ThroColor.throGreenOnink : Color.clear)
                    .frame(width: 6, height: 6)
                Text(name)
                    .font(.system(size: compact ? 12 : 13, weight: throwing ? .semibold : .regular))
                    .foregroundStyle(ThroColor.throChalk.opacity(throwing ? 1 : 0.72))
                    .lineLimit(1)
            }
            Text("\(remaining)")
                .font(.system(size: compact ? 26 : 34, weight: .heavy, design: .default))
                .monospacedDigit()
                .foregroundStyle(ThroColor.throChalk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(legs)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ThroColor.throChalk.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(remaining) remaining, \(legs) legs\(throwing ? ", throwing" : "")")
    }
}

/// The Lock Screen presentation, and the Dynamic Island's expanded one.
public struct ThroLiveBoard: View {
    private let state: ThroLiveState
    private let format: String
    private let stale: Bool

    public init(state: ThroLiveState, format: String, stale: Bool) {
        self.state = state
        self.format = format
        self.stale = stale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            HStack(alignment: .top, spacing: ThroSpacing.spacing4) {
                ThroLiveSide(name: state.homeName, remaining: state.homeRemaining,
                             legs: state.homeLegs,
                             throwing: ThroLiveCopy.isThrowing(state, .home))
                Spacer(minLength: 0)
                ThroLiveSide(name: state.awayName, remaining: state.awayRemaining,
                             legs: state.awayLegs,
                             throwing: ThroLiveCopy.isThrowing(state, .away))
            }
            Text(ThroLiveCopy.caption(state, stale: stale))
                .font(.system(size: 12, weight: stale ? .semibold : .regular))
                // A stale caption is not decoration and is not an error either — it is the surface
                // saying what it knows. Pending is the app's colour for exactly that.
                .foregroundStyle(stale ? ThroColor.throBronzeOnink : ThroColor.throChalk.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(format)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ThroColor.throChalk.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, ThroSpacing.spacing4)
        .padding(.vertical, ThroSpacing.spacing3)
    }
}

/// The two colours the system needs by name, so a widget extension can dress a Live Activity in
/// THRØ's field without linking the whole token package itself.
public enum ThroLivePalette {
    /// The board's own dark green — the same field the app's masthead stands on.
    public static var field: Color { ThroColor.colorBackgroundBrand }
    /// What the system tints its own controls with, over that field.
    public static var onField: Color { ThroColor.throGreenOnink }
}
