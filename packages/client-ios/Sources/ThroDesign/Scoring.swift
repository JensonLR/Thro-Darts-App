import SwiftUI
import ThroTokens

// The scoring components, each a direct reading of components/scoring/*.jsx. These are presentation
// only — no engine, no journal — so the design package stays free of domain dependencies and the
// Play module composes them.

/// components/scoring/RemainingScore.jsx. `aria-live="polite"` becomes the updates-frequently trait.
public struct RemainingScore: View {
    /// `CaseIterable` so a test can walk every state and hold that no two of them sound the
    /// same. The compiler already makes sure each is *handled*; what it cannot see is a new
    /// state that is handled by speaking what another one speaks, which is a state a
    /// listener cannot tell from its neighbour.
    public enum State: CaseIterable, Sendable { case normal, checkout, bust }

    private let value: Int
    private let label: String
    private let state: State
    private let darts: String?

    public init(value: Int, label: String = "You require", state: State = .normal, darts: String? = nil) {
        self.value = value
        self.label = label
        self.state = state
        self.darts = darts
    }

    private var color: Color {
        switch state {
        case .bust: return ThroColor.colorStatusError
        case .checkout: return ThroColor.colorTextBrand
        case .normal: return ThroColor.colorTextPrimary
        }
    }

    public var body: some View {
        VStack(spacing: ThroSpacing.spacing1) {
            Eyebrow(state == .bust ? "Bust — score restored" : label,
                    color: state == .bust ? ThroColor.colorStatusError : ThroColor.colorTextSecondary)
            Text("\(value)")
                .thro(ThroTypography.scoreHero)
                .foregroundStyle(color)
                // On a phone too short for the 96-point face the numeral shrinks rather than clips
                // or scrolls (DESIGN_UNSPECIFIED #1 gives no clamp; this is the floor, not a design).
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let darts {
                Text(darts)
                    .thro(ThroTypography.label.family(.sport))
                    .foregroundStyle(ThroColor.colorTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        // Label and value are separate, not combined into one string. VoiceOver re-announces a
        // changed *value* without re-reading the name, which is what a number that moves every
        // visit needs, and a Braille display puts it in its own cell.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RemainingScore.spokenLabel(label: label, state: state))
        .accessibilityValue(RemainingScore.spokenValue(value: value, darts: darts))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// What a screen reader is told this number *is*.
    ///
    /// **The checkout state was carried by colour and nothing else.** A sighted player sees the
    /// hero turn brand green and knows they are on a finish; a VoiceOver player was told the number
    /// and left to work it out. On this screen a `CheckoutCard` happens to name the fact as well,
    /// but this is a design-system component that any screen may use, and a component that relies
    /// on a sibling to say the important half is one that will eventually be used without it.
    static func spokenLabel(label: String, state: State) -> String {
        switch state {
        case .bust: return "\(label). Bust — score restored"
        case .checkout: return "\(label), on a finish"
        case .normal: return label
        }
    }

    static func spokenValue(value: Int, darts: String?) -> String {
        [String(value), darts].compactMap { $0 }.joined(separator: ", ")
    }
}

/// components/scoring/Checkout.jsx. Route chips are shown only when a route is supplied, and the
/// component never derives one: the table is the engine's (`RuleTables.route`, PD-013), held by the
/// conformance corpus to be a legal finish of exactly that number under exactly that out-rule. A
/// component that guessed a route would be inventing dart-level evidence on the one screen a player
/// reads mid-visit.
public struct CheckoutCard: View {
    private let required: Int
    private let route: [String]
    private let compact: Bool
    private let hideValue: Bool

    public init(required: Int, route: [String] = [], compact: Bool = false, hideValue: Bool = false) {
        self.required = required
        self.route = route
        self.compact = compact
        self.hideValue = hideValue
    }

    public var body: some View {
        VStack(spacing: ThroSpacing.spacing2) {
            Eyebrow("Checkout available", color: ThroColor.colorTextBrand)
            if !hideValue {
                Text("\(required)")
                    .thro((compact ? ThroTypography.heading1 : ThroTypography.sportHero).family(.sport).weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
            }
            if !route.isEmpty {
                HStack(spacing: ThroSpacing.spacing2) {
                    ForEach(route, id: \.self) { step in
                        Text(step)
                            .thro(ThroTypography.label.family(.sport).weight(.semibold).tracking(em: 0.04))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusSmall).fill(ThroColor.colorBackgroundRaised))
                            .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusSmall).strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? ThroSpacing.spacing3 : ThroSpacing.spacing4)
        .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard).fill(ThroColor.colorBackgroundBrandSubtle))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard).strokeBorder(ThroColor.colorBorderBrand, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

/// components/scoring/LegState.jsx.
public struct LegState: View {
    private let home: Int
    private let away: Int
    private let bestOf: Int?
    private let unit: String

    public init(home: Int, away: Int, bestOf: Int? = nil, unit: String = "Legs") {
        self.home = home
        self.away = away
        self.bestOf = bestOf
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: ThroSpacing.spacing2) {
            Eyebrow(unit)
            Text("\(home)–\(away)")
                .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                .foregroundStyle(ThroColor.colorTextPrimary)
            if let bestOf {
                Text("Best of \(bestOf)")
                    .thro(ThroTypography.metadata.family(.sport))
                    .foregroundStyle(ThroColor.colorTextSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit)
        .accessibilityValue(LegState.spoken(home: home, away: away, bestOf: bestOf))
    }

    /// `2–1` drawn is `2 to 1` spoken. An en dash between two numerals is not a word: read out it
    /// becomes "2 1", which is the same sound as twenty-one and tells a player nothing about who is
    /// ahead — on the one figure that decides whether the match is nearly over.
    static func spoken(home: Int, away: Int, bestOf: Int?) -> String {
        let score = "\(home) to \(away)"
        guard let bestOf else { return score }
        return "\(score), best of \(bestOf)"
    }
}

/// components/scoring/MatchHeader.jsx. Board and format are numerals, so they take the sport face.
///
/// `onBack` is not in the export: the export's scoring screen has no way out at all. A TopBar above
/// this header was tried first and cost 64 points the screen does not have on a 430×932 phone — the
/// checkout card clipped and the turn indicator fell below the keypad. A 44-point chevron at the
/// header's leading edge costs nothing vertically.
///
/// `onEnd` is the same extension made a second time, for PD-016: a match that will not be played out
/// has to be endable from the screen the players are looking at when it happens. It is a trailing
/// 44-point target on the row that already exists, so it too costs nothing vertically — which is the
/// constraint that decides this header's shape. Both are recorded in `DESIGN_INVENTORY.md` as
/// engineering-drawn rather than exported.
public struct MatchHeader: View {
    private let competition: String
    private let round: String?
    private let board: String?
    private let format: String?
    private let onBack: (() -> Void)?
    private let onEnd: (() -> Void)?

    public init(competition: String, round: String? = nil, board: String? = nil, format: String? = nil,
                onBack: (() -> Void)? = nil, onEnd: (() -> Void)? = nil) {
        self.competition = competition
        self.round = round
        self.board = board
        self.format = format
        self.onBack = onBack
        self.onEnd = onEnd
    }

    public var body: some View {
        HStack(alignment: .center, spacing: ThroSpacing.spacing2) {
            if let onBack {
                Button(action: onBack) {
                    Icon(.chevronLeft, size: 24)
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                .accessibilityLabel("Back")
                .padding(.leading, -ThroSpacing.spacing3)
            }
            HStack(alignment: .top, spacing: ThroSpacing.spacing4) {
                cell("Competition", competition, sport: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let round { cell("Round", round, sport: false) }
                if let board { cell("Board", board, sport: true) }
                if let format { cell("Format", format, sport: true) }
            }
            if let onEnd {
                Button(action: onEnd) {
                    Icon(.x, size: 20)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                        .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                // Named for what it does, not for the glyph. "Close" would read as dismissing the
                // screen; this ends the match, and a player who taps it by accident deserves to have
                // been told which of those it was before the confirm card appears.
                .accessibilityLabel("End this match")
                .padding(.trailing, -ThroSpacing.spacing3)
            }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .background(ThroColor.colorBackgroundPrimary)
        .overlay(alignment: .bottom) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
    }

    private func cell(_ label: String, _ value: String, sport: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label)
            Text(value)
                .thro(sport ? ThroTypography.label.family(.sport).weight(.bold) : ThroTypography.label.weight(.bold))
                .foregroundStyle(ThroColor.colorTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}

/// components/scoring/TurnIndicator.jsx. The export's one colour literal, `rgba(247,246,242,0.6)`,
/// is chalk at 60% — written here through the token so the contrast matrix can see it.
public struct TurnIndicator: View {
    private let player: String
    private let dartsThrown: Int
    private let active: Bool

    public init(player: String, dartsThrown: Int = 0, active: Bool = true) {
        self.player = player
        self.dartsThrown = dartsThrown
        self.active = active
    }

    public var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            Text(active ? "\(player) to throw" : "\(player) waiting")
                .thro(ThroTypography.label.weight(.bold).uppercase(true).tracking(em: 0.04))
                .foregroundStyle(active ? ThroColor.throChalk : ThroColor.colorTextSecondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < dartsThrown ? (active ? ThroColor.throChalk : ThroColor.colorTextSecondary) : Color.clear)
                        .overlay(Circle().strokeBorder(active ? ThroColor.throChalk.opacity(0.6) : ThroColor.colorBorderStrong, lineWidth: 1))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityLabel("\(dartsThrown) of 3 darts thrown")
        }
        .padding(.vertical, ThroSpacing.spacing2)
        .padding(.horizontal, ThroSpacing.spacing4)
        .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusStatus, style: .continuous)
            .fill(active ? ThroColor.colorBackgroundBrand : ThroColor.colorSurfaceSecondary))
    }
}

/// components/scoring/ScoreKeypad.jsx: six quick totals, nine digits, Miss / 0 / clear, Enter.
///
/// One reading differs from the JSX and is recorded here rather than hidden. The export's Enter
/// submits `Number(value || 0)` — an empty entry becomes a scored 0 — and the harness disables Enter
/// until something is typed; this follows the harness, because a nought recorded by a stray tap is
/// evidence that did not happen. The undo key does what the export labels it: with an entry typed it
/// clears the entry; with nothing typed it undoes the last visit, as a retraction the journal appends
/// (PD-004) — the caller decides which, this key only reports the tap.
public struct ScoreKeypad: View {
    public static let quick: [Int] = [180, 140, 100, 60, 45, 26]

    /// What to say when the entry changes, or nil when there is nothing worth saying.
    ///
    /// Nil for no change and nil when the keypad arrives empty, so a screen appearing does not
    /// announce anything. Emptying a typed entry says so: silence there would be indistinguishable
    /// from the tap not registering, which is the same complaint about controls that do not react —
    /// heard rather than felt.
    static func spokenEntry(from was: String, to now: String) -> String? {
        guard was != now else { return nil }
        if now.isEmpty { return was.isEmpty ? nil : "Cleared" }
        return now
    }

    /// Whether the phone answers in the hand (PD-015). Read here rather than passed in, because a
    /// player's answer to "should this buzz" belongs to the player and not to every caller.
    @AppStorage(ThroHaptics.enabledKey) private var haptics: Bool = true

    private let value: String
    private let disabled: Bool
    private let onDigit: (String) -> Void
    private let onQuick: (Int) -> Void
    private let onMiss: () -> Void
    private let onClear: () -> Void
    private let onEnter: () -> Void

    public init(value: String, disabled: Bool = false,
                onDigit: @escaping (String) -> Void, onQuick: @escaping (Int) -> Void,
                onMiss: @escaping () -> Void, onClear: @escaping () -> Void, onEnter: @escaping () -> Void) {
        self.value = value
        self.disabled = disabled
        self.onDigit = onDigit
        self.onQuick = onQuick
        self.onMiss = onMiss
        self.onClear = onClear
        self.onEnter = onEnter
    }

    public var body: some View {
        VStack(spacing: ThroSpacing.spacing2) {
            HStack(spacing: ThroSpacing.spacing2) {
                ForEach(Array(ScoreKeypad.quick.enumerated()), id: \.element) { total in
                    key(action: { onQuick(total.element) },
                        seedAngle: Double(total.offset) * 37) {
                        Text("\(total.element)").thro(ThroTypography.label.family(.sport))
                    }
                    .accessibilityLabel("Score \(total.element)")
                }
            }
            ForEach(Array([[1, 2, 3], [4, 5, 6], [7, 8, 9]].enumerated()), id: \.element) { row in
                HStack(spacing: ThroSpacing.spacing2) {
                    ForEach(Array(row.element.enumerated()), id: \.element) { column in
                        // Every key gets its own seed, so no two chalk boxes on the keypad wander
                        // identically. A grid of identical hand-drawn boxes is a stamped grid.
                        key(action: { onDigit(String(column.element)) },
                            seedAngle: Double(row.offset * 3 + column.offset) * 53 + 211) {
                            digit("\(column.element)")
                        }
                    }
                }
            }
            HStack(spacing: ThroSpacing.spacing2) {
                key(action: onMiss, seedAngle: 401) {
                    Text("Miss").thro(ThroTypography.label.weight(.bold).uppercase(true).tracking(em: 0.04))
                }
                key(action: { onDigit("0") }, seedAngle: 457) { digit("0") }
                key(action: onClear, seedAngle: 509) {
                    Icon(.undo2, size: 24)
                }
                .accessibilityLabel("Undo")
            }
            Button(action: { ThroHaptics.play(.commit, enabled: haptics); onEnter() }) {
                Text(value.isEmpty ? "Enter score" : "Enter \(value)")
                    .thro(ThroTypography.bodyLarge.weight(.bold).uppercase(true).tracking(em: 0.04))
                    .foregroundStyle(ScoreKeypad.ink(ready: !value.isEmpty, disabled: disabled))
            }
            .buttonStyle(ChalkKeyStyle(ScoreKeypad.enterLighting(ready: !value.isEmpty, disabled: disabled),
                                       seedAngle: 577))
            .disabled(value.isEmpty)
        }
        .padding(.vertical, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .background(ThroColor.colorBoardField)
        .disabled(disabled)
        // **What has been typed, said out loud.** The Enter key is the readout — it reads
        // "Enter 141" — and a sighted player sees it change under their thumb. A VoiceOver player's
        // focus stays on the digit they just tapped, and nothing announced anything at all: three
        // taps and no confirmation of what is about to be committed, on the one screen in this app
        // where a mis-key becomes evidence. The announcement is the entry and nothing else, so it
        // is over before the next dart.
        .onChange(of: value) { was, now in
            guard let spoken = ScoreKeypad.spokenEntry(from: was, to: now) else { return }
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    private func digit(_ text: String) -> some View {
        Text(text).thro(ThroTypography.heading2.family(.sport).weight(.semibold))
    }

    /// Which board ground the Enter key sits on. Availability is a place in the light, never an
    /// opacity: the resting Enter key used to be the whole control at 0.4, which composited its
    /// label down to **2.20:1** in light and 2.92:1 in dark — below the 4.5:1 floor on the one
    /// control in this app that commits evidence. Out of the light it measures 7.60:1, and ready it
    /// measures 8.75:1, with the ground moving in the direction a player expects: the key they can
    /// press is the brightest thing on the board.
    static func enterLighting(ready: Bool, disabled: Bool) -> ChalkKeyStyle.Lighting {
        (ready && !disabled) ? .lit : .sunken
    }

    /// Full chalk when the key can be pressed, the quieter chalk when it cannot. Both are on the
    /// contrast matrix against all three board grounds, so neither can fall below its floor.
    static func ink(ready: Bool, disabled: Bool) -> Color {
        (ready && !disabled) ? ThroColor.colorTextOnBoard : ThroColor.colorTextOnBoardSecondary
    }

    /// The ink on every other key. A disabled keypad recedes by losing the brightest chalk, not by
    /// fading towards its own background — 6.00:1 rather than a ghost.
    static func keyInk(disabled: Bool) -> Color {
        disabled ? ThroColor.colorTextOnBoardSecondary : ThroColor.colorTextOnBoard
    }

    /// Where an ordinary key sits. Out of the light when the keypad is not accepting a score, so a
    /// player can see at a glance that the board is not listening.
    static func keyLighting(disabled: Bool) -> ChalkKeyStyle.Lighting {
        disabled ? .sunken : .field
    }

    private func key<Label: View>(haptic: ThroHaptics.Event = .key,
                                  action: @escaping () -> Void,
                                  seedAngle: Double,
                                  @ViewBuilder label: () -> Label) -> some View {
        Button(action: { ThroHaptics.play(haptic, enabled: haptics); action() }) {
            label().foregroundStyle(ScoreKeypad.keyInk(disabled: disabled))
        }
        // PD-015, and SLATE B.3. `ThroPressStyle(pressedFill:)` draws the pressed colour with
        // `.background`, which is BEHIND the label — and the label carried an opaque background of
        // its own, so the pressed fill was never visible. Sixty taps a leg on a control whose only
        // acknowledgement was a 2% scale. `ChalkKeyStyle` owns the face, the boundary and the press
        // together, because `isPressed` exists inside a `ButtonStyle` and nowhere else.
        .buttonStyle(ChalkKeyStyle(ScoreKeypad.keyLighting(disabled: disabled), seedAngle: seedAngle))
    }
}

/// One figure on a result, drawn according to how far it can be trusted (PD-015).
///
/// **The gap this closes** was named as `DESIGN_UNSPECIFIED` #9: the export draws exactly one kind
/// of statistic — a confident number — and THRØ's honesty layer produces three. Until this, all
/// three were drawn identically: `58.4`, `58.4–61.2` and `—` were the same weight, the same colour
/// and the same size, so the one thing the honesty layer exists to communicate was the one thing
/// the screen did not show. A reader had to notice the shape of the string.
///
/// **The guarantee is in the type, not in the drawing.** `range` and `unavailable` take a
/// non-optional reason, so it is not possible to put a dash or a range on a screen without saying
/// why it is one. That is the failure this is really guarding: a figure that lost its qualification
/// somewhere between the statistics layer and the view.
public struct StatItem: Identifiable, Equatable, Sendable {
    /// How far the figure can be trusted. Mirrors `ThroStatistics.Basis`, restated here because the
    /// design package must not depend on the statistics package to know how to draw a number.
    public enum Confidence: CaseIterable, Sendable, Equatable { case exact, range, unavailable }

    public let label: String
    public let value: String
    public let note: String?
    public let confidence: Confidence
    public var id: String { label }

    private init(label: String, value: String, note: String?, confidence: Confidence) {
        self.label = label
        self.value = value
        self.note = note
        self.confidence = confidence
    }

    /// A figure derived with certainty. `note` is optional here and only here — an exact figure may
    /// still disclose something (a first nine that excludes short legs), but it need not.
    public static func exact(_ label: String, _ value: String, note: String? = nil) -> StatItem {
        StatItem(label: label, value: value, note: note, confidence: .exact)
    }

    /// An interval. `why` is required: a range with no explanation reads as indecision rather than
    /// as the precise statement of what the evidence supports that it is.
    public static func range(_ label: String, _ value: String, why: String) -> StatItem {
        StatItem(label: label, value: value, note: why, confidence: .range)
    }

    /// Not computable. The value is always the em dash — never a zero, which would read as
    /// *they are bad at darts* rather than *this cannot be worked out*.
    public static func unavailable(_ label: String, why: String) -> StatItem {
        StatItem(label: label, value: "—", note: why, confidence: .unavailable)
    }
}

/// The two-column figures grid from MatchSummary.jsx, usable on its own.
///
/// Three drawn forms, one per confidence (PD-015). Colour alone would not carry it — a screen
/// reader gets no colour — so the basis is also spoken in the accessibility label.
public struct StatGrid: View {
    private let stats: [StatItem]

    public init(_ stats: [StatItem]) { self.stats = stats }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: ThroSpacing.spacing6, alignment: .topLeading),
                            GridItem(.flexible(), alignment: .topLeading)],
                  alignment: .leading, spacing: ThroSpacing.spacing4) {
            ForEach(stats) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(s.label)
                    HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing2) {
                        Text(s.value)
                            .thro(ThroTypography.heading2.family(.sport).weight(.bold))
                            .foregroundStyle(StatGrid.valueColour(s.confidence))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)   // a range is twice as long as a point value
                        // Only a range is marked. The confident case is the common one and labelling
                        // it would make every figure look qualified; the dash marks itself.
                        if s.confidence == .range { Tag("Range", tone: .neutral) }
                    }
                    if let note = s.note {
                        Text(note)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(s.label)
                .accessibilityValue(StatGrid.spokenValue(s))
                // The reason is a hint, not part of the value. VoiceOver reads a label and value in
                // one uninterruptible run: six figures whose reasons are two sentences each made a
                // paragraph a player had to sit through to reach the next figure. As a hint it is
                // still spoken, still after the figure, and can be skipped past.
                .accessibilityHint(s.note ?? "")
            }
        }
    }

    /// Full strength for a fact; the quieter neutral for a figure that is not one. Both neutrals are
    /// on the contrast matrix, so neither can fall below the floor.
    static func valueColour(_ c: StatItem.Confidence) -> Color {
        c == .unavailable ? ThroColor.colorTextSecondary : ThroColor.colorTextPrimary
    }

    /// What a screen reader says the figure **is**. The basis is spoken because it is the part a
    /// sighted reader gets from weight and colour, and "dash" would tell somebody nothing at all.
    ///
    /// A range is spoken as *"between 58.2 and 61.0"* rather than read off the string: an en dash
    /// between two numerals is not a word, and "58.2 61.0" is a pair of figures with no relation
    /// stated — which is exactly the collapse of a range into something else that the statistics
    /// layer exists to prevent.
    static func spokenValue(_ s: StatItem) -> String {
        switch s.confidence {
        case .exact: return s.value
        case .range: return "between \(s.value.replacingOccurrences(of: "–", with: " and "))"
        case .unavailable: return "not available"
        }
    }

    /// The whole thing in one string, for a caller that has only a label to put it in.
    static func spoken(_ s: StatItem) -> String {
        [ "\(s.label), \(spokenValue(s))", s.note ].compactMap { $0 }.joined(separator: ". ")
    }
}

/// components/scoring/MatchSummary.jsx. The export's headline is "You win" / "You lose"; a match
/// scored for two players on one phone has no "you", so the headline is a parameter and the
/// `result:` initialiser keeps the export's wording for the single-player case.
public struct MatchSummary: View {
    public enum Result: Sendable { case win, loss }

    private let headline: String
    private let won: Bool
    private let score: String
    private let opponent: String?
    private let stats: [StatItem]

    public init(headline: String, won: Bool, score: String, opponent: String? = nil, stats: [StatItem] = []) {
        self.headline = headline
        self.won = won
        self.score = score
        self.opponent = opponent
        self.stats = stats
    }

    public init(result: Result, score: String, opponent: String? = nil, stats: [StatItem] = []) {
        self.init(headline: result == .win ? "You win" : "You lose", won: result == .win,
                  score: score, opponent: opponent, stats: stats)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing4) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                Text(headline)
                    .thro(ThroTypography.heading2.weight(.heavy).uppercase(true).tracking(em: 0.02))
                    .foregroundStyle(won ? ThroColor.colorTextBrand : ThroColor.colorTextPrimary)
                Text(score)
                    .thro(ThroTypography.sportHero)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                if let opponent {
                    Text(opponent)
                        .thro(ThroTypography.body)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                }
            }
            if !stats.isEmpty {
                StatGrid(stats)
                    .padding(.top, ThroSpacing.spacing4)
                    .overlay(alignment: .top) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
            }
        }
    }
}
