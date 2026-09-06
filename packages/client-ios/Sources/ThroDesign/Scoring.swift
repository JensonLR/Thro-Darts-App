import SwiftUI
import ThroTokens

// The scoring components, each a direct reading of components/scoring/*.jsx. These are presentation
// only — no engine, no journal — so the design package stays free of domain dependencies and the
// Play module composes them.

/// components/scoring/RemainingScore.jsx. `aria-live="polite"` becomes the updates-frequently trait.
public struct RemainingScore: View {
    public enum State: Sendable { case normal, checkout, bust }

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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// components/scoring/Checkout.jsx. Route chips are shown only when a route is supplied — the
/// repository holds no checkout-route table, and one will not be invented here.
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
        .accessibilityElement(children: .combine)
    }
}

/// components/scoring/MatchHeader.jsx. Board and format are numerals, so they take the sport face.
///
/// `onBack` is not in the export: the export's scoring screen has no way out at all. A TopBar above
/// this header was tried first and cost 64 points the screen does not have on a 430×932 phone — the
/// checkout card clipped and the turn indicator fell below the keypad. A 44-point chevron at the
/// header's leading edge costs nothing vertically.
public struct MatchHeader: View {
    private let competition: String
    private let round: String?
    private let board: String?
    private let format: String?
    private let onBack: (() -> Void)?

    public init(competition: String, round: String? = nil, board: String? = nil, format: String? = nil,
                onBack: (() -> Void)? = nil) {
        self.competition = competition
        self.round = round
        self.board = board
        self.format = format
        self.onBack = onBack
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
                .buttonStyle(.plain)
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
                ForEach(ScoreKeypad.quick, id: \.self) { q in
                    key(minHeight: ThroSpacing.touchTargetMinimum, background: ThroColor.colorSurfaceSecondary, action: { onQuick(q) }) {
                        Text("\(q)").thro(ThroTypography.label.family(.sport))
                    }
                    .accessibilityLabel("Score \(q)")
                }
            }
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: ThroSpacing.spacing2) {
                    ForEach(row, id: \.self) { d in
                        key(action: { onDigit(String(d)) }) { digit("\(d)") }
                    }
                }
            }
            HStack(spacing: ThroSpacing.spacing2) {
                key(action: onMiss) {
                    Text("Miss").thro(ThroTypography.label.weight(.bold).uppercase(true).tracking(em: 0.04))
                }
                key(action: { onDigit("0") }) { digit("0") }
                key(background: ThroColor.colorSurfaceSecondary, action: onClear) {
                    Icon(.undo2, size: 24)
                }
                .accessibilityLabel("Undo")
            }
            Button(action: onEnter) {
                Text(value.isEmpty ? "Enter score" : "Enter \(value)")
                    .thro(ThroTypography.bodyLarge.weight(.bold).uppercase(true).tracking(em: 0.04))
                    .foregroundStyle(ThroColor.throChalk)
                    .frame(maxWidth: .infinity, minHeight: ThroSpacing.touchTargetScoring)
                    .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusKeypad).fill(ThroColor.colorSurfaceBrand))
            }
            .buttonStyle(.plain)
            .disabled(value.isEmpty)
            .opacity(value.isEmpty ? 0.4 : 1)
        }
        .padding(.vertical, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        .background(ThroColor.colorBackgroundPrimary)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

    private func digit(_ text: String) -> some View {
        Text(text).thro(ThroTypography.heading2.family(.sport).weight(.semibold))
    }

    private func key<Label: View>(minHeight: CGFloat = ThroSpacing.touchTargetScoring,
                                  background: Color = ThroColor.colorSurfacePrimary,
                                  action: @escaping () -> Void,
                                  @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(ThroColor.colorTextPrimary)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusKeypad).fill(background))
                .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusKeypad).strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One figure on a result. `note` is where a bounded or unavailable statistic explains itself; the
/// export's Stat has no such slot (DESIGN_UNSPECIFIED #9), so it is rendered in the metadata role.
public struct StatItem: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String
    public let note: String?
    public var id: String { label }

    public init(label: String, value: String, note: String? = nil) {
        self.label = label
        self.value = value
        self.note = note
    }
}

/// The two-column figures grid from MatchSummary.jsx, usable on its own.
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
                    Text(s.value)
                        .thro(ThroTypography.heading2.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                    if let note = s.note {
                        Text(note)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
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
