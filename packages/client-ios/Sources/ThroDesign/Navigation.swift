import SwiftUI
import ThroTokens

// MARK: - Top bar

/// `navigation/TopBar`. Compact: back, eyebrow + title, actions in one row. Large: the row carries
/// back and actions; the eyebrow and heading-1 title sit beneath.
public struct TopBar: View {
    public struct Action: Identifiable {
        public var id: String { icon.rawValue }
        public let icon: ThroIcon
        public let label: String
        public let action: () -> Void

        public init(icon: ThroIcon, label: String, action: @escaping () -> Void) {
            self.icon = icon
            self.label = label
            self.action = action
        }
    }

    private let title: String
    private let eyebrow: String?
    private let onBack: (() -> Void)?
    private let actions: [Action]
    private let large: Bool

    public init(_ title: String, eyebrow: String? = nil, onBack: (() -> Void)? = nil, actions: [Action] = [], large: Bool = false) {
        self.title = title
        self.eyebrow = eyebrow
        self.onBack = onBack
        self.actions = actions
        self.large = large
    }

    /// Whether the phone is on its side, by PD-061's rule for a short screen.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// **Large upright, compact on its side** (PD-092). A large bar spends a row on a heading-one title beneath
    /// its buttons: a seventh of an upright phone, and a quarter of one turned sideways before anything on the
    /// page. The mastheads already fold on exactly this rule (PD-061); the bars were the last top-of-page that
    /// did not. Folded, the title and the actions share one row — the compact bar every pushed screen uses.
    private var showsLarge: Bool {
        large && ThroMasthead.shape(verticalSizeClassIsCompact: verticalSizeClass == .compact) == .stacked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: showsLarge ? ThroSpacing.spacing2 : 0) {
            HStack(spacing: ThroSpacing.spacing3) {
                if let onBack {
                    Button(action: onBack) {
                        Icon(.chevronLeft, size: 26)
                            .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .padding(.leading, -ThroSpacing.spacing3)
                    .accessibilityLabel("Back")
                }
                if showsLarge {
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        // A bar cannot grow, and its eyebrow carries a club or league name on a dozen
                        // screens, so both shrink a little before they give up and truncate (PD-052).
                        if let eyebrow { Eyebrow(eyebrow).lineLimit(1).minimumScaleFactor(0.8) }
                        Text(title)
                            .thro(ThroTypography.heading3)
                            .foregroundStyle(ThroColor.colorTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: ThroSpacing.spacing1) {
                    ForEach(actions) { a in
                        Button(action: a.action) {
                            Icon(a.icon, size: 22)
                                .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .accessibilityLabel(a.label)
                    }
                }
            }
            if showsLarge {
                VStack(alignment: .leading, spacing: 0) {
                    if let eyebrow { Eyebrow(eyebrow) }
                    Text(title)
                        .thro(ThroTypography.heading1)
                        .foregroundStyle(ThroColor.colorTextPrimary)
                }
            }
        }
        .padding(EdgeInsets(top: ThroHeaderMetrics.paperTop, leading: ThroHeaderMetrics.gutter,
                            bottom: ThroHeaderMetrics.paperBottom, trailing: ThroHeaderMetrics.gutter))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Paper and hairline to the glass on a phone turned sideways, as the bottom bar's are (PD-092): the bar is
        // laid out inside the Dynamic Island's insets and its hairline stopped short of both edges.
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea(edges: .horizontal))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ThroColor.colorBorderDefault).frame(height: ThroSpacing.borderWidthHairline)
                .ignoresSafeArea(edges: .horizontal)
        }
    }
}

// MARK: - Bottom bar

/// `navigation/BottomBar`. Five worlds. The export sets the label at 11px, which is off the approved
/// type scale and recorded as a bypass in TOKEN_HEALTH.md; this uses the nearest on-scale role
/// (metadata, 13) rather than reproduce the bypass in a platform source.
public struct BottomBar: View {
    /// How large the bar's own labels are allowed to get (PD-140).
    ///
    /// **Why a ceiling here, when the rule everywhere else is that text grows.** Looked at on the phone at
    /// the largest accessibility size, this bar stopped being a bar: "Home" wrapped to "Ho/me", "Discover"
    /// to "Dis/cov/er", the five items pushed each other into three lines apiece, the bar reached roughly
    /// 500 points — more than half the screen — and *Your teams* was pushed off the bottom of You. A player
    /// at that size could not see their own team.
    ///
    /// Apple's own `TabView` does not grow either: past a point it stops being a row of labels and becomes
    /// a list. A hand-built bar inherits none of that, so the ceiling is written here. The label is capped,
    /// shrinks a little before it truncates, and never wraps; the icon and the 44-point target are
    /// untouched, so nothing a finger aims at gets smaller. Everything *inside* the tabs still grows.
    public static let labelCeiling: DynamicTypeSize = .xxLarge

    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case home, play, live, discover, you
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .home: return "Home"
            case .play: return "Play"
            case .live: return "Live"
            case .discover: return "Discover"
            case .you: return "You"
            }
        }

        public var icon: ThroIcon {
            switch self {
            case .home: return .house
            case .play: return .target
            case .live: return .radio
            case .discover: return .compass
            case .you: return .circleUser
            }
        }
    }

    private let selection: Tab
    private let badges: Set<Tab>
    private let onChange: (Tab) -> Void

    public init(selection: Tab, badges: Set<Tab> = [], onChange: @escaping (Tab) -> Void) {
        self.selection = selection
        self.badges = badges
        self.onChange = onChange
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// **On its side, each label goes beside its icon** (PD-092), the way the system's own tab bar does it.
    /// A phone turned sideways is about 390 points tall, and a label stacked under its icon asked for 52 of
    /// them plus the bar's margins — on every tab, under every screen, the content was cut short by the bar.
    /// Side by side the tabs need one line: `touchTargetMinimum`, the height Apple gives a tap target, and no
    /// margin above or below it. The rule is the masthead's (PD-061), so the bar folds when the large title does.
    private var sideways: Bool {
        ThroMasthead.shape(verticalSizeClassIsCompact: verticalSizeClass == .compact) == .oneLine
    }

    private var item: AnyLayout {
        sideways ? AnyLayout(HStackLayout(spacing: ThroSpacing.spacing2))
                 : AnyLayout(VStackLayout(spacing: ThroSpacing.spacing1))
    }

    /// How far the tabs sit below the bar's top edge, which is where the selected tab's mark is drawn.
    private var inset: CGFloat { sideways ? 0 : ThroSpacing.spacing2 }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let on = tab == selection
                Button { onChange(tab) } label: {
                    item {
                        Icon(tab.icon, size: sideways ? 20 : 24)
                            .overlay(alignment: .topTrailing) {
                                if badges.contains(tab) {
                                    Circle()
                                        .fill(ThroColor.colorStatusLive)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 6, y: -2)
                                }
                            }
                        Text(tab.label)
                            .thro(ThroTypography.metadata.weight(on ? .bold : .medium).tracking(em: 0.02))
                            .dynamicTypeSize(...Self.labelCeiling)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityLabel(tab.label)
                    }
                    .frame(maxWidth: .infinity, minHeight: sideways ? ThroSpacing.touchTargetMinimum : 52)
                    .foregroundStyle(on ? ThroColor.colorTextPrimary : ThroColor.colorTextSecondary)
                    .overlay(alignment: .top) {
                        if on {
                            Rectangle()
                                .fill(ThroColor.colorTextPrimary)
                                .frame(width: 22, height: 2)
                                .offset(y: -inset)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusStatus, scales: false))
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        // The bar is the screen's edge and stays the width of it; the five tabs are not, and spread across
        // a tablet into five small marks a hand's width apart (PD-052). They sit in the same measure the
        // content does, centred, with the bar's paper and hairline still running the whole way.
        .frame(maxWidth: ThroReadable.measure)
        .frame(maxWidth: .infinity)
        .padding(.top, inset)
        .padding(.bottom, sideways ? 0 : 10)
        // **To the glass, not to the safe area.** The comment above promised the paper and hairline run the
        // whole way, and on an upright phone they did — its side insets are zero. Turned on its side, the
        // Dynamic Island takes about 59 points at each end, the bar is laid out inside them, and the
        // hairline stopped a thumb's width short of both edges while the board above it ran to the glass.
        // Only the horizontal edges are released, so nothing upright moves; the hairline stays an overlay
        // so it still draws over the selected tab's mark exactly as it did.
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea(edges: .horizontal))
        .overlay(alignment: .top) {
            Rectangle().fill(ThroColor.colorBorderDefault).frame(height: ThroSpacing.borderWidthHairline)
                .ignoresSafeArea(edges: .horizontal)
        }
    }
}
