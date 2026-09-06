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

    public var body: some View {
        VStack(alignment: .leading, spacing: large ? ThroSpacing.spacing2 : 0) {
            HStack(spacing: ThroSpacing.spacing3) {
                if let onBack {
                    Button(action: onBack) {
                        Icon(.chevronLeft, size: 26)
                            .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .padding(.leading, -ThroSpacing.spacing3)
                    .accessibilityLabel("Back")
                }
                if large {
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if let eyebrow { Eyebrow(eyebrow).lineLimit(1) }
                        Text(title)
                            .thro(ThroTypography.heading3)
                            .foregroundStyle(ThroColor.colorTextPrimary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: ThroSpacing.spacing1) {
                    ForEach(actions) { a in
                        Button(action: a.action) {
                            Icon(a.icon, size: 22)
                                .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .accessibilityLabel(a.label)
                    }
                }
            }
            if large {
                VStack(alignment: .leading, spacing: 0) {
                    if let eyebrow { Eyebrow(eyebrow) }
                    Text(title)
                        .thro(ThroTypography.heading1)
                        .foregroundStyle(ThroColor.colorTextPrimary)
                }
            }
        }
        .padding(EdgeInsets(top: ThroSpacing.spacing3, leading: ThroSpacing.spaceScreenGutter,
                            bottom: ThroSpacing.spacing4, trailing: ThroSpacing.spaceScreenGutter))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThroColor.colorBackgroundPrimary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ThroColor.colorBorderDefault).frame(height: ThroSpacing.borderWidthHairline)
        }
    }
}

// MARK: - Bottom bar

/// `navigation/BottomBar`. Five worlds. The export sets the label at 11px, which is off the approved
/// type scale and recorded as a bypass in TOKEN_HEALTH.md; this uses the nearest on-scale role
/// (metadata, 13) rather than reproduce the bypass in a platform source.
public struct BottomBar: View {
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

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let on = tab == selection
                Button { onChange(tab) } label: {
                    VStack(spacing: ThroSpacing.spacing1) {
                        Icon(tab.icon, size: 24)
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
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(on ? ThroColor.colorTextPrimary : ThroColor.colorTextSecondary)
                    .overlay(alignment: .top) {
                        if on {
                            Rectangle()
                                .fill(ThroColor.colorTextPrimary)
                                .frame(width: 22, height: 2)
                                .offset(y: -ThroSpacing.spacing2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.top, ThroSpacing.spacing2)
        .padding(.bottom, 10)
        .background(ThroColor.colorBackgroundPrimary)
        .overlay(alignment: .top) {
            Rectangle().fill(ThroColor.colorBorderDefault).frame(height: ThroSpacing.borderWidthHairline)
        }
    }
}
