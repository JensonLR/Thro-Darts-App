import SwiftUI
import ThroTokens

// Forms and identity: components/forms/TextField.jsx, components/forms/SegmentedControl.jsx,
// components/identity/PlayerIdentity.jsx and PlayerComparison.jsx.

/// TextField.jsx. The export sets `outline: none` on the input and supplies nothing in its place —
/// the audit's most serious finding. Nothing is removed here: the platform's focus behaviour stays.
public struct ThroTextField: View {
    private let label: String
    @Binding private var text: String
    private let placeholder: String
    private let helper: String?
    private let error: String?
    private let icon: ThroIcon?

    public init(_ label: String, text: Binding<String>, placeholder: String = "",
                helper: String? = nil, error: String? = nil, icon: ThroIcon? = nil) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.helper = helper
        self.error = error
        self.icon = icon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            Text(label)
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)
            HStack(spacing: ThroSpacing.spacing2) {
                if let icon {
                    Icon(icon, size: 18).foregroundStyle(ThroColor.colorTextSecondary)
                }
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .thro(ThroTypography.body)
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, ThroSpacing.spacing4)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusField).fill(ThroColor.colorSurfacePrimary))
            .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusField)
                .strokeBorder(error != nil ? ThroColor.colorStatusError : ThroColor.colorBorderStrong, lineWidth: 1))
            if let message = error ?? helper {
                HStack(spacing: 6) {
                    if error != nil { Icon(.circleAlert, size: 13) }
                    Text(message).thro(ThroTypography.metadata)
                }
                .foregroundStyle(error != nil ? ThroColor.colorStatusError : ThroColor.colorTextSecondary)
            }
        }
    }
}

/// SegmentedControl.jsx. The export's segment is 40 high, below the 44 minimum the audit enforces
/// (DESIGN_UNSPECIFIED, found mechanically); the segment here is the minimum, not the export's 40.
public struct SegmentedControl<ID: Hashable>: View {
    public struct Item: Identifiable {
        public let id: ID
        public let label: String
        public init(_ id: ID, _ label: String) {
            self.id = id
            self.label = label
        }
    }

    private let items: [Item]
    @Binding private var selection: ID

    public init(_ items: [Item], selection: Binding<ID>) {
        self.items = items
        self._selection = selection
    }

    /// `SegmentedControl([(301, "301"), (501, "501")], selection: $game)`.
    public init(_ pairs: [(ID, String)], selection: Binding<ID>) {
        self.init(pairs.map { Item($0.0, $0.1) }, selection: selection)
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item.id == selection
                Button { selection = item.id } label: {
                    Text(item.label)
                        .thro(on ? ThroTypography.label.weight(.bold) : ThroTypography.label.weight(.medium))
                        .foregroundStyle(on ? ThroColor.colorTextPrimary : ThroColor.colorTextSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, ThroSpacing.spacing3)
                        .frame(maxWidth: .infinity, minHeight: ThroSpacing.touchTargetMinimum)
                        .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusStatus, style: .continuous)
                            .fill(on ? ThroColor.colorBackgroundRaised : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: ThroSpacing.radiusStatus, style: .continuous).fill(ThroColor.colorSurfaceSecondary))
        .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusStatus, style: .continuous).strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
    }
}

/// What PlayerIdentity shows. Rating is optional and, under OD-001 (no validated rating model), is
/// never supplied by this app.
public struct PlayerRef: Equatable, Sendable {
    public let name: String
    public let rating: Int?
    public let team: String?
    public let region: String?
    public let verified: Bool

    public init(name: String, rating: Int? = nil, team: String? = nil, region: String? = nil, verified: Bool = false) {
        self.name = name
        self.rating = rating
        self.team = team
        self.region = region
        self.verified = verified
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}

/// PlayerIdentity.jsx: an initials mark, the name, and a metadata row.
public struct PlayerIdentity: View {
    public enum Size: Sendable { case small, medium, large }
    public enum Align: Sendable { case leading, trailing }

    private let player: PlayerRef
    private let size: Size
    private let align: Align

    public init(_ player: PlayerRef, size: Size = .medium, align: Align = .leading) {
        self.player = player
        self.size = size
        self.align = align
    }

    private var mark: CGFloat {
        switch size { case .small: return 32; case .medium: return 40; case .large: return 52 }
    }
    private var nameRole: ThroTypeRole {
        switch size {
        case .small: return ThroTypography.label
        case .medium: return ThroTypography.heading3
        case .large: return ThroTypography.heading2
        }
    }

    public var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            if align == .leading { initialsMark }
            VStack(alignment: align == .leading ? .leading : .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .thro(nameRole.weight(.bold).tracking(em: -0.005))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if player.verified {
                        Icon(.circleCheck, size: 14)
                            .foregroundStyle(ThroColor.colorStatusVerified)
                            .accessibilityLabel("THRØ verified")
                    }
                }
                HStack(spacing: 8) {
                    if let rating = player.rating {
                        Text(rating.formatted())
                            .thro(ThroTypography.metadata.family(.sport).weight(.semibold))
                            .foregroundStyle(ThroColor.colorTextPrimary)
                    }
                    if let team = player.team {
                        Text(team).thro(ThroTypography.metadata.family(.sport)).foregroundStyle(ThroColor.colorTextSecondary)
                    }
                    if let region = player.region {
                        Text(region).thro(ThroTypography.metadata.family(.sport)).foregroundStyle(ThroColor.colorTextSecondary)
                    }
                }
            }
            if align == .trailing { initialsMark }
        }
        .accessibilityElement(children: .combine)
    }

    private var initialsMark: some View {
        Text(player.initials)
            .thro(ThroTypeRole(family: .sport, size: (mark * 0.38).rounded(), lineHeight: (mark * 0.38).rounded(),
                               weight: .bold, relativeTo: .caption, tabularNumerals: true))
            .foregroundStyle(ThroColor.colorTextSecondary)
            .frame(width: mark, height: mark)
            .background(Circle().fill(ThroColor.colorSurfaceSecondary))
            .overlay(Circle().strokeBorder(ThroColor.colorBorderStrong, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// PlayerComparison.jsx: two identities either side of "vs", then rows of figures.
public struct PlayerComparison: View {
    public struct Row: Identifiable, Equatable, Sendable {
        public let label: String
        public let home: String
        public let away: String
        public var id: String { label }
        public init(_ label: String, home: String, away: String) {
            self.label = label
            self.home = home
            self.away = away
        }
    }

    private let home: PlayerRef
    private let away: PlayerRef
    private let rows: [Row]

    public init(home: PlayerRef, away: PlayerRef, rows: [Row] = []) {
        self.home = home
        self.away = away
        self.rows = rows
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
                PlayerIdentity(home, size: .medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("vs")
                    .thro(ThroTypography.labelStrong.weight(.bold).uppercase(true).tracking(em: 0.08))
                    .foregroundStyle(ThroColor.colorTextTertiary)
                    .padding(.top, 10)
                PlayerIdentity(away, size: .medium, align: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.bottom, ThroSpacing.spacing4)
            ForEach(rows) { row in
                HStack(spacing: ThroSpacing.spacing3) {
                    Text(row.home)
                        .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Eyebrow(row.label)
                    Text(row.away)
                        .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, ThroSpacing.spacing3)
                .overlay(alignment: .top) { Rectangle().fill(ThroColor.colorBorderDefault).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .background(ThroColor.colorBackgroundPrimary)
    }
}
