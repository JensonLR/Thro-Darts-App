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
    /// Whether the press moves the control as well as changing it.
    ///
    /// A key and a chip want the travel: it is the whole sensation of pressing something. **A
    /// full-width row does not** — scaling a list row shrinks it away from the finger that is
    /// touching it, which reads as the row flinching rather than as a press landing. Those get the
    /// fill and stay still.
    private let scales: Bool

    public init(radius: CGFloat = ThroSpacing.radiusKeypad, pressedFill: Color? = nil,
                scales: Bool = true) {
        self.radius = radius
        self.pressedFill = pressedFill
        self.scales = scales
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
            .scaleEffect(scales && configuration.isPressed && !reduceMotion ? ThroPressStyle.pressedScale : 1)
            .animation(.easeOut(duration: ThroMotion.motionDurationInstant), value: configuration.isPressed)
    }
}

/// A worded action — *See all*, *Edit*, *Announce*, *Draw 4*, *Enter the result*.
///
/// **This exists because those were not buttons in any way a finger could tell.** The founder, on a
/// build from their phone: *"buttons need to be more reactive, sometimes when I press close to them
/// they don't react and have to be exactly direct on them."* Every one of them was a `Text` in a
/// `Button` with `.buttonStyle(.plain)`, which is SwiftUI for **do nothing at all**: no pressed
/// state, and a hit area exactly the size of the glyphs. *See all* was a target about 50 by 17
/// points, in an app whose own design system defines a 44-point minimum and uses it for icons.
///
/// Two failures in one control, and both are fixed here rather than at seventeen call sites:
///
///  - **The target is at least 44 by 44**, and `contentShape` makes the whole of it tappable rather
///    than only where ink happens to fall. The frame's alignment keeps the *text* where it was, so a
///    trailing action still sits on the screen gutter and the target grows inward — the same trick
///    `BackChevron` uses, and the reason it needs no negative inset.
///  - **It reacts.** `ThroPressStyle` was built for PD-015 and was on three controls in the whole
///    app: the keypad, its enter key, and the accent swatches. Everything else was `.plain`.
public struct ThroTextButton: View {
    public enum Tone: Sendable { case brand, destructive, quiet }

    private let label: String
    private let tone: Tone
    private let alignment: Alignment
    private let action: () -> Void

    /// - Parameter alignment: where the words sit inside the 44-point target. `.trailing` for an
    ///   action at the end of a row, `.leading` for one that starts a line — so the glyphs stay put
    ///   and only the target grows.
    public init(_ label: String, tone: Tone = .brand, alignment: Alignment = .leading,
                action: @escaping () -> Void) {
        self.label = label
        self.tone = tone
        self.alignment = alignment
        self.action = action
    }

    private var colour: Color {
        switch tone {
        case .brand: return ThroColor.colorTextBrand
        case .destructive: return ThroColor.colorStatusError
        case .quiet: return ThroColor.colorTextSecondary
        }
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .thro(ThroTypography.label.weight(.semibold))
                .foregroundStyle(colour)
                .lineLimit(1)
                // So a neighbour can never squeeze the words into an ellipsis — the defect that put
                // "Announce" half off the edge of a phone.
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: ThroSpacing.touchTargetMinimum,
                       minHeight: ThroSpacing.touchTargetMinimum,
                       alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
    }
}

public extension View {
    /// A whole row that is a button.
    ///
    /// Without this the gaps between a row's pieces are not tappable at all: SwiftUI hit-tests the
    /// label's ink, so a finger landing between a badge and a name lands on nothing. The row is also
    /// given the press fill rather than the travel — see `ThroPressStyle.scales`.
    func throRowTapTarget() -> some View {
        contentShape(Rectangle())
    }

    /// The 44-point minimum, for a control whose own content is smaller than a fingertip.
    ///
    /// The alignment keeps the visible thing where the design put it and grows the target around it,
    /// which is why this never moves a layout: the same reason `BackChevron` needs no inset.
    func throTapTarget(_ alignment: Alignment = .center) -> some View {
        frame(minWidth: ThroSpacing.touchTargetMinimum,
              minHeight: ThroSpacing.touchTargetMinimum,
              alignment: alignment)
            .contentShape(Rectangle())
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

    /// The vocabulary.
    ///
    /// **These are moments in a game of darts, not places a finger landed.** That is the whole
    /// distinction between a haptic language and haptics on buttons: a phone that taps for every
    /// control teaches a player to ignore it, and then the one tap that mattered — *that did not go
    /// on the board* — is lost in the noise. Every case below is a thing that happened to the
    /// record, and nothing else in the app produces a haptic at all.
    public enum Event: Sendable, Equatable, CaseIterable {
        /// A digit, a quick score, a choice. The lightest thing the phone can do.
        case key
        /// A visit accepted and committed. Slightly firmer: this one changed the record.
        case commit
        /// A bust, or a refused entry. Sharp, and distinct from a commit, because the player needs
        /// to know something did NOT go on the board without reading the screen.
        case refused
        /// The thrower has come down onto a finish.
        ///
        /// The one moment in a leg that a player wants to know about **before** they look up, and
        /// the reason this vocabulary is worth having: no darts app marks it. Lighter than a commit
        /// on purpose — it is news, not a change to the record, and the visit that produced it has
        /// already had its own.
        case checkout
        /// A visit struck from the record (PD-004). Deliberately unlike a commit: an undo is a
        /// correction, and a correction that felt like an entry would be the wrong feedback for the
        /// one action in the app that takes something back.
        case retracted
        /// A leg won.
        case legWon
        /// The match decided. The heaviest thing here, and the rarest — a player should feel this
        /// once, which is what makes it unmistakable.
        case matchWon
        /// Both players have agreed the result (PD-011). The moment a claim becomes attested
        /// evidence, and the only haptic in the app that is about the record rather than the game.
        case attested
        /// The dart striking the board in the opening (PD-007).
        case strike
        /// A letter of the wordmark being struck in behind it.
        case stamp
    }

    /// Whether a haptic is played at all. False on a Mac, in a test, and whenever the player has
    /// turned them off.
    public static func play(_ event: Event, enabled: Bool = true) {
        guard enabled else { return }
        #if canImport(UIKit) && !os(watchOS)
        switch event {
        case .key:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .checkout:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .commit:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .retracted:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .refused:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .legWon, .attested:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .matchWon:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .strike:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
        case .stamp:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
        }
        #endif
    }

    /// The mapping, exposed so a test can hold it. A description of the design rather than of UIKit:
    /// what matters is that *something went wrong* and *something went right* are never the same
    /// sensation, and that the events which happen many times a leg are lighter than the ones that
    /// happen once a match.
    public static func weight(_ event: Event) -> String {
        switch event {
        case .key: return "light"
        case .checkout: return "soft"
        case .commit: return "medium"
        case .retracted: return "rigid"
        case .refused: return "warning"
        case .legWon: return "success"
        case .matchWon: return "heavy"
        case .attested: return "success"
        case .strike: return "heavy"
        case .stamp: return "rigid-soft"
        }
    }

    /// One event's generator, held ready.
    ///
    /// `play(_:)` builds a generator and fires it in the same breath, which is right for a keypad —
    /// the finger is already down and a millisecond does not matter. It is wrong for the opening,
    /// where the strike has to land on the frame of the thud: the Taptic Engine needs readying
    /// roughly half a second ahead, and that is as long as it stays ready.
    ///
    /// So the opening keeps its prepared generators and gives up its own vocabulary instead. Before
    /// this there were two haptic systems in the app — four named events on one preference, and two
    /// unnamed intensities on another — and the intensities lived as literals in a scheduler.
    public final class Player {
        private let event: Event
        #if canImport(UIKit) && !os(watchOS)
        private let generator: UIImpactFeedbackGenerator?
        #endif

        public init(_ event: Event) {
            self.event = event
            #if canImport(UIKit) && !os(watchOS)
            switch event {
            case .strike, .matchWon: generator = UIImpactFeedbackGenerator(style: .heavy)
            case .stamp, .retracted: generator = UIImpactFeedbackGenerator(style: .rigid)
            case .key: generator = UIImpactFeedbackGenerator(style: .light)
            case .checkout: generator = UIImpactFeedbackGenerator(style: .soft)
            case .commit: generator = UIImpactFeedbackGenerator(style: .medium)
            // The notification generator is a different class and does not take an intensity;
            // these events are not ones anything schedules to a frame, so they go the short way.
            case .refused, .legWon, .attested: generator = nil
            }
            #endif
        }

        /// Readies the engine. Costs nothing if it is already ready.
        public func prepare() {
            #if canImport(UIKit) && !os(watchOS)
            generator?.prepare()
            #endif
        }

        public func play(enabled: Bool = true) {
            guard enabled else { return }
            #if canImport(UIKit) && !os(watchOS)
            if let generator {
                generator.impactOccurred(intensity: CGFloat(ThroHaptics.intensity(event)))
            } else {
                ThroHaptics.play(event)
            }
            #endif
        }
    }

    /// How hard an impact event strikes, 0...1. The opening's two were literals in its scheduler;
    /// they are part of the vocabulary now, so a test can hold them and the opening cannot drift
    /// from the design on its own.
    public static func intensity(_ event: Event) -> Double {
        switch event {
        case .strike, .matchWon: return 1.0
        case .stamp: return 0.55
        case .retracted: return 0.7
        case .commit: return 0.8
        case .checkout: return 0.6
        case .key: return 1.0
        case .refused, .legWon, .attested: return 1.0
        }
    }

    /// Roughly how hard each event feels, on one scale, so the ordering can be asserted rather than
    /// argued about. Not a UIKit value: a description of the design's own intent.
    public static func magnitude(_ event: Event) -> Double {
        switch event {
        case .key: return 0.2
        case .checkout: return 0.3
        case .stamp: return 0.4
        case .commit: return 0.5
        case .retracted: return 0.6
        case .refused: return 0.7
        case .legWon: return 0.8
        case .attested: return 0.8
        case .matchWon: return 1.0
        case .strike: return 1.0
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
/// **That limit is now lifted, and PD-024 is how.** It used to be a real one — a player who needed
/// `.accessibility5` got `.accessibility1` while scoring — and this file said so rather than hiding
/// it. `DYNAMIC_TYPE.md` named two shapes that would serve that player properly and said choosing was
/// a design commission, not engineering's; the founder chose the first: **the upper region scrolls
/// above a pinned keypad.**
///
/// Past the scoring ceiling the screen reflows. Everything above the keypad — the remaining score,
/// the leg state, the checkout route, the turn indicator — grows to the reading ceiling and scrolls.
/// **The keypad does not.** It keeps the scoring ceiling at every size, which is what *pinned* means
/// and is the whole reason the cap existed: a keypad that moves under the player's thumb mid-visit
/// turns a mis-key into a wrong number in an evidence journal, and that is worse than a small key.
///
/// So the two halves of the screen answer two different questions. Above the keypad, *can the player
/// read this?* — and it scales all the way. At the keypad, *is the key where their thumb expects it?*
/// — and it does not move.
public enum ThroDynamicType {
    /// Where the keypad stops growing, at every size. Also the size the screen reflows **above**.
    public static let scoringCeiling: DynamicTypeSize = .accessibility1

    /// Where everything else stops, which is where iOS stops.
    public static let readingCeiling: DynamicTypeSize = .accessibility5

    /// Whether the scoring screen reflows at this size: the upper region scrolling, the keypad
    /// pinned (PD-024).
    ///
    /// The threshold is the scoring ceiling itself, so the screen changes shape at exactly the size
    /// text used to stop growing — no size loses anything it had, and none gains a scroll bar it did
    /// not need.
    public static func reflows(at size: DynamicTypeSize) -> Bool { size > scoringCeiling }

    /// What the screen's text is capped at, given whether it is reflowing.
    public static func ceiling(reflowing: Bool) -> DynamicTypeSize {
        reflowing ? readingCeiling : scoringCeiling
    }
}

public extension View {
    /// The scoring screen's ceiling (PD-024). Below the reflow threshold it is the scoring ceiling,
    /// because nothing scrolls; above it the text grows to the reading ceiling and the upper region
    /// scrolls instead. The keypad applies the scoring ceiling to itself either way.
    func throScoringTypeCeiling(reflowing: Bool = false) -> some View {
        dynamicTypeSize(...ThroDynamicType.ceiling(reflowing: reflowing))
    }

    /// The keypad's own ceiling, applied inside the screen's. Pinned means fixed: the key under a
    /// thumb is the same size and in the same place at every text setting.
    func throPinnedKeypadTypeCeiling() -> some View {
        dynamicTypeSize(...ThroDynamicType.scoringCeiling)
    }
}

// MARK: - entrances (PD-027)

/// The design's own easing curves as SwiftUI animations.
///
/// They were already in the tokens and already used — by the opening sequence, which evaluates them
/// as maths on a per-frame basis. Nothing could reach them as an `Animation`, so every transition
/// in the app that was not the opening used SwiftUI's defaults. That is what "generic" looks like
/// from the outside: an app whose motion is Apple's rather than its own.
public extension Animation {
    /// Something arriving. `motionEasingSet` decelerates hard at the end — a thing that lands.
    static func throEnter(_ duration: Double = ThroMotion.motionDurationStandard) -> Animation {
        let c = ThroMotion.motionEasingSet
        return .timingCurve(Double(c.0), Double(c.1), Double(c.2), Double(c.3), duration: duration)
    }

    /// Something settling into a new value in place — a score changing, a row re-sorting.
    static func throResolve(_ duration: Double = ThroMotion.motionDurationResolve) -> Animation {
        let c = ThroMotion.motionEasingResolve
        return .timingCurve(Double(c.0), Double(c.1), Double(c.2), Double(c.3), duration: duration)
    }

    /// Something leaving. Faster than it arrived, because waiting for an exit is the one kind of
    /// motion that always reads as slowness.
    static func throExit(_ duration: Double = ThroMotion.motionDurationFast) -> Animation {
        let c = ThroMotion.motionEasingExit
        return .timingCurve(Double(c.0), Double(c.1), Double(c.2), Double(c.3), duration: duration)
    }
}

/// A block of a screen arriving, a beat after the one above it.
///
/// **Why a screen needs this at all.** The founder: *"all screens feel bare & basic ... must be
/// incredibly beautiful, clean, dynamic & fluid, no clunkyness or generic slop anywhere."* A screen
/// that is simply *there* the instant it is pushed has no craft in it, however good its typography
/// is; a screen whose parts land in the order you read them has depth without a single extra pixel
/// of decoration. This is that, and it is deliberately small: 12 points of travel — the design's own
/// `motionTravelMedium` — and 45 milliseconds between blocks.
///
/// **It withdraws completely under Reduce Motion**, and withdrawing means the content is simply
/// present at full opacity from the first frame, never a faded-in version of itself. A person who
/// has asked for no motion gets no motion, not gentler motion.
///
/// **The stagger is capped.** Past about six blocks the delay stops growing, because the eighth
/// section of a long screen arriving a third of a second late is not choreography, it is a wait.
public struct ThroEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let index: Int
    @State private var arrived = false

    public init(index: Int) { self.index = index }

    /// The most blocks that are still worth staggering.
    public static let stagger = 6
    public static let step = 0.045

    public func body(content: Content) -> some View {
        let shown = arrived || reduceMotion
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : ThroSpacing.motionTravelMedium)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.throEnter().delay(Double(min(index, ThroEntrance.stagger)) * ThroEntrance.step)) {
                    arrived = true
                }
            }
    }
}

public extension View {
    /// Marks this as the `index`-th block of a screen, counting from the top.
    func throEntrance(_ index: Int) -> some View { modifier(ThroEntrance(index: index)) }
}

/// Something that lands rather than appears — a result, a won leg, a number that has just been
/// decided.
///
/// **The one gesture the design already owns.** `motionScaleImpact` is 1.02: what an impact comes
/// *out* by. `ThroPressStyle` uses its inverse for a press going in. This is the impact itself, on
/// `motionEasingImpact`, which overshoots and settles — so the result screen's score arrives with
/// the same physics as a dart hitting a board, and does it with a token that was already there
/// rather than a number somebody picked.
///
/// Used sparingly and deliberately: **on the outcome of a match, and nothing else.** A screen where
/// everything lands is a screen where nothing does.
public struct ThroLanding: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let delay: Double
    @State private var landed = false

    public init(delay: Double = 0) { self.delay = delay }

    public func body(content: Content) -> some View {
        let settled = landed || reduceMotion
        return content
            .scaleEffect(settled ? 1 : ThroMotion.motionScaleImpact)
            .opacity(settled ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                let c = ThroMotion.motionEasingImpact
                withAnimation(.timingCurve(Double(c.0), Double(c.1), Double(c.2), Double(c.3),
                                           duration: ThroMotion.motionDurationEmphasis).delay(delay)) {
                    landed = true
                }
            }
    }
}

public extension View {
    func throLanding(delay: Double = 0) -> some View { modifier(ThroLanding(delay: delay)) }
}
