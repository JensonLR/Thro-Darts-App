import SwiftUI
import ThroTokens
#if canImport(UIKit)
import UIKit
#endif

// What a control does when you touch it (PD-015).
//
// `docs/design/DESIGN_UNSPECIFIED.md` listed the pressed and focus appearance and keypad haptics as
// a design commission, and the founder released it to engineering on PD-010's terms. Until this,
// every control in the app used `.buttonStyle(.plain)`, which is SwiftUI's way of saying *do
// nothing at all*: the keypad — the one surface a player touches sixty times a leg — gave no
// acknowledgement whatsoever that a key had been hit. On a phone held at arm's length in a noisy
// room, that is the difference between confidence and double-tapping.
//
// Everything here is built from tokens that already exist. Nothing new was invented for it.

/// The pressed appearance for every THRØ control.
///
/// Two signals, deliberately, because one of them is not always available:
///
/// - **Scale.** `motionScaleImpact` is the design's impact magnitude (1.02); a press is its
///   inverse, so a key goes *in* by exactly as much as the design says an impact comes *out*.
///   Motion, and so **withdrawn under Reduce Motion** — that setting means what it says.
/// - **Surface.** A press moves the fill one step, which is not motion and is therefore kept under
///   Reduce Motion. It is the signal that always survives.
///
/// `motionDurationInstant` (0.08s) is the shortest duration the design defines, and a key that took
/// longer than that to acknowledge a touch would feel behind the player rather than under them.
public struct ThroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let radius: CGFloat
    /// The fill a press moves to. Nil keeps the label's own background and dims instead, which is
    /// what a ghost button — a control with no surface of its own — needs.
    private let pressedFill: Color?

    public init(radius: CGFloat = ThroSpacing.radiusKeypad, pressedFill: Color? = nil) {
        self.radius = radius
        self.pressedFill = pressedFill
    }

    /// A press goes in by as much as an impact comes out. 1.02 out, 0.98 in.
    public static var pressedScale: CGFloat { 2 - ThroMotion.motionScaleImpact }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if let pressedFill {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(pressedFill)
                        .opacity(configuration.isPressed ? 1 : 0)
                }
            }
            .opacity(pressedFill == nil && configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? ThroPressStyle.pressedScale : 1)
            .animation(.easeOut(duration: ThroMotion.motionDurationInstant), value: configuration.isPressed)
    }
}

/// The focus ring, for the people who do not touch the screen.
///
/// Switch Control, a hardware keyboard and Voice Control all move a focus around the app, and until
/// this there was nothing to see when they did. Drawn as a second, wider stroke *outside* the
/// control's own border in the brand surface colour, so it reads as an addition rather than as a
/// change of state — and outside, so it never overlaps the control's own error border, which is a
/// different thing that must stay legible at the same time.
public struct ThroFocusRing: ViewModifier {
    private let focused: Bool
    private let radius: CGFloat

    public init(focused: Bool, radius: CGFloat) {
        self.focused = focused
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius + 3)
                .strokeBorder(ThroColor.colorSurfaceBrand, lineWidth: 2)
                .padding(-3)
                .opacity(focused ? 1 : 0)
        }
    }
}

public extension View {
    /// The THRØ focus ring, shown when `focused`.
    func throFocusRing(_ focused: Bool, radius: CGFloat = ThroSpacing.radiusField) -> some View {
        modifier(ThroFocusRing(focused: focused, radius: radius))
    }
}

/// What the phone does in the player's hand.
///
/// **Three weights, and they mean three different things.** A keypad that buzzed identically for a
/// digit and for a bust would be telling the player nothing they could use without looking — and the
/// whole point of a haptic at a dartboard is that it is felt while the player is looking at the
/// board rather than at the phone.
///
/// The player can turn them off (`ThroHaptics.enabledKey`), because a phone in a pocket
/// buzzing through a match is somebody else's idea of helpful. Default on.
public enum ThroHaptics {
    /// The player's answer, stored. Lives here rather than in `ScoringPreferences` because
    /// `ThroDesign` cannot import `ThroPlay` — the dependency runs the other way — and the control
    /// that reads it is the keypad, which is a design component. `ScoringPreferences.hapticsKey`
    /// forwards to this one so Settings can go on naming it where the other scoring settings live.
    /// The string is a contract with every install that has saved one.
    public static let enabledKey = "thro.haptics"

    public enum Event: Sendable, Equatable {
        /// A digit, a quick score, a choice. The lightest thing the phone can do.
        case key
        /// A visit accepted and committed. Slightly firmer: this one changed the record.
        case commit
        /// A bust, or a refused entry. Sharp, and distinct from a commit, because the player needs
        /// to know something did NOT go on the board without reading the screen.
        case refused
        /// A leg won. The heaviest, and the only one a player should feel more than a few times a
        /// match — which is what makes it recognisable.
        case legWon
    }

    /// Whether a haptic is played at all. False on a Mac, in a test, and whenever the player has
    /// turned them off.
    public static func play(_ event: Event, enabled: Bool = true) {
        guard enabled else { return }
        #if canImport(UIKit) && !os(watchOS)
        switch event {
        case .key:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .commit:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .refused:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .legWon:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        #endif
    }

    /// The mapping, exposed so a test can hold it. A description of the design rather than of UIKit:
    /// what matters is that the four events are four distinct sensations and that the two which
    /// mean *something went wrong* and *something went right* are not the same one.
    public static func weight(_ event: Event) -> String {
        switch event {
        case .key: return "light"
        case .commit: return "medium"
        case .refused: return "warning"
        case .legWon: return "success"
        }
    }
}

/// The Dynamic Type contract (PD-015).
///
/// **The app scales, and one screen has a ceiling.** Every type role already carries a `relativeTo:`
/// text style, so all of THRØ has grown with the player's text size since the type layer was
/// written. What was missing was a *contract*: a stated answer to what happens at the accessibility
/// sizes, where body text is roughly three times its default and a 96-point hero numeral is a
/// screenful on its own.
///
/// - **Reading screens** — Result, Settings, Clubs, a person's page — scale all the way to
///   `.accessibility5` and scroll. Nothing there is capped, because nothing there is harmed by
///   being tall.
/// - **The scoring screen** stops at `scoringCeiling`. It is the one screen the founder verified
///   must fit without scrolling, and it has to hold a keypad whose targets are already at the
///   minimum. Past this size the choice is between a keypad that scrolls under the player's thumb
///   mid-visit and text that stops growing, and this takes the second.
///
/// **This is a real limit, stated rather than hidden.** A player who needs `.accessibility5` gets
/// `.accessibility1` while scoring. The alternative that would serve them properly is a scoring
/// screen that reflows — the upper region scrolling above a pinned keypad — and that is a screen the
/// export does not draw, so it is a design commission rather than something to invent here. It is
/// recorded in `docs/design/DYNAMIC_TYPE.md` so it can be revisited deliberately.
public enum ThroDynamicType {
    /// Where a screen that must fit without scrolling stops growing.
    public static let scoringCeiling: DynamicTypeSize = .accessibility1

    /// Where everything else stops, which is where iOS stops.
    public static let readingCeiling: DynamicTypeSize = .accessibility5
}

public extension View {
    /// The ceiling for a screen that must fit without scrolling. Only the scoring screen uses it,
    /// and a test asserts that the reading screens do not.
    func throScoringTypeCeiling() -> some View {
        dynamicTypeSize(...ThroDynamicType.scoringCeiling)
    }
}
