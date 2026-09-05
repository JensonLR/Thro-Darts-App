import SwiftUI
import ThroTokens

// Core components, each a direct reading of its JSX counterpart under docs/design/extracted.
// Every colour is a ThroColor, every size a token. Where the design is silent — pressed appearance,
// disabled treatment beyond an opacity multiplier — the platform's own behaviour is kept, never
// removed and never replaced with an invention. DESIGN_UNSPECIFIED.md records each such gap.

extension ThroTypeRole {
    /// A copy with a different tracking, for the components whose JSX sets letter-spacing inline.
    public func tracking(em: CGFloat) -> ThroTypeRole {
        ThroTypeRole(family: family, size: size, lineHeight: lineHeight, weight: weight, trackingEm: em,
                     relativeTo: relativeTo, uppercase: uppercase, tabularNumerals: tabularNumerals)
    }

    public func uppercase(_ on: Bool) -> ThroTypeRole {
        ThroTypeRole(family: family, size: size, lineHeight: lineHeight, weight: weight, trackingEm: trackingEm,
                     relativeTo: relativeTo, uppercase: on, tabularNumerals: tabularNumerals)
    }
}

// MARK: - Elevation

/// The shadow tokens. The generator does not yet emit shadows to Swift, so the values are stated
/// here against the token they come from; the colour is the ink primitive at the token's alpha.
struct Elevation3: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        // --elevation-3: 0 8px 24px rgba(16,18,17,0.10) light; 0 8px 24px rgba(0,0,0,0.55) dark.
        // A CSS blur of 24 is roughly a SwiftUI radius of 12.
        content.shadow(
            color: scheme == .dark ? ThroColor.throInkSunken.opacity(0.55) : ThroColor.throInk.opacity(0.10),
            radius: 12, x: 0, y: 8
        )
    }
}

extension View {
    public func throElevation3() -> some View { modifier(Elevation3()) }
}

// MARK: - Button

/// `core/Button`. Five variants, three sizes. The label is `--font-ui`, semibold, 0.005em.
///
/// Pressed appearance is DESIGN_UNSPECIFIED #2 and is not invented here: `.plain` keeps the
/// platform's own press feedback. Disabled is the design's flat opacity multiplier, as specified,
/// and #15 records that this produces contrast failures the design has yet to resolve.
public struct ThroButton: View {
    public enum Variant: Sendable { case primary, secondary, ink, ghost, destructive }
    public enum Size: Sendable { case large, medium, small }

    private let title: String
    private let variant: Variant
    private let size: Size
    private let icon: ThroIcon?
    private let iconAfter: ThroIcon?
    private let fullWidth: Bool
    private let disabled: Bool
    private let loading: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        variant: Variant = .primary,
        size: Size = .medium,
        icon: ThroIcon? = nil,
        iconAfter: ThroIcon? = nil,
        fullWidth: Bool = false,
        disabled: Bool = false,
        loading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.size = size
        self.icon = icon
        self.iconAfter = iconAfter
        self.fullWidth = fullWidth
        self.disabled = disabled
        self.loading = loading
        self.action = action
    }

    private var height: CGFloat {
        switch size { case .large: return 56; case .medium: return 48; case .small: return ThroSpacing.touchTargetMinimum }
    }
    private var paddingX: CGFloat {
        switch size { case .large: return ThroSpacing.spacing6; case .medium: return ThroSpacing.spacing5; case .small: return ThroSpacing.spacing4 }
    }
    private var role: ThroTypeRole {
        let base: ThroTypeRole
        switch size {
        case .large: base = ThroTypography.bodyLarge
        case .medium: base = ThroTypography.body
        case .small: base = ThroTypography.label
        }
        return base.weight(.semibold).tracking(em: 0.005)
    }
    private var foreground: Color {
        switch variant {
        case .primary: return ThroColor.throChalk
        case .secondary, .ghost: return ThroColor.colorTextPrimary
        case .ink: return ThroColor.colorTextInverse
        case .destructive: return ThroColor.colorStatusError
        }
    }
    private var background: Color {
        switch variant {
        case .primary: return ThroColor.colorSurfaceBrand
        case .ink: return ThroColor.colorBackgroundInverse
        case .secondary, .ghost, .destructive: return .clear
        }
    }
    private var border: Color {
        switch variant {
        case .secondary: return ThroColor.colorBorderStrong
        case .destructive: return ThroColor.colorStatusError
        case .primary, .ink, .ghost: return .clear
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing2) {
                if loading {
                    Icon(.loader, size: 18)
                } else if let icon {
                    Icon(icon, size: 18)
                }
                Text(title).thro(role).lineLimit(1)
                if let iconAfter { Icon(iconAfter, size: 18) }
            }
            .padding(.horizontal, paddingX)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: ThroSpacing.radiusControl)
                    .strokeBorder(border, lineWidth: ThroSpacing.borderWidthStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusControl))
            .contentShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusControl))
        }
        .buttonStyle(.plain)
        .disabled(disabled || loading)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityAddTraits(loading ? .updatesFrequently : [])
    }
}

// MARK: - Tag

/// `core/Tag`. Eight tones; outlined draws the tone colour as a hairline instead of a fill.
public struct Tag: View {
    public enum Tone: Sendable { case neutral, brand, success, warning, error, info, live, achievement }

    private let text: String
    private let tone: Tone
    private let icon: ThroIcon?
    private let outlined: Bool
    private let uppercase: Bool

    public init(_ text: String, tone: Tone = .neutral, icon: ThroIcon? = nil, outlined: Bool = false, uppercase: Bool = true) {
        self.text = text
        self.tone = tone
        self.icon = icon
        self.outlined = outlined
        self.uppercase = uppercase
    }

    private var colors: (background: Color, foreground: Color) {
        switch tone {
        case .neutral: return (ThroColor.colorStatusNeutralSurface, ThroColor.colorTextSecondary)
        case .brand: return (ThroColor.colorBackgroundBrandSubtle, ThroColor.colorTextBrand)
        case .success: return (ThroColor.colorStatusSuccessSurface, ThroColor.colorStatusSuccess)
        case .warning: return (ThroColor.colorStatusWarningSurface, ThroColor.colorStatusWarning)
        case .error: return (ThroColor.colorStatusErrorSurface, ThroColor.colorStatusError)
        case .info: return (ThroColor.colorStatusInfoSurface, ThroColor.colorStatusInfo)
        case .live: return (ThroColor.colorStatusLiveSurface, ThroColor.colorStatusLive)
        case .achievement: return (ThroColor.throBronzeTint, ThroColor.colorTextAchievement)
        }
    }

    public var body: some View {
        let c = colors
        HStack(spacing: ThroSpacing.spacing1) {
            if let icon { Icon(icon, size: 13) }
            Text(text)
                .thro(ThroTypography.labelStrong.weight(.semibold).tracking(em: uppercase ? 0.06 : 0).uppercase(uppercase))
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
        .foregroundStyle(c.foreground)
        .background(outlined ? Color.clear : c.background)
        .overlay(Capsule().strokeBorder(outlined ? c.foreground : Color.clear, lineWidth: ThroSpacing.borderWidthHairline))
        .clipShape(Capsule())
    }
}

// MARK: - Section header

/// `core/SectionHeader`. The title is the eyebrow role at bold weight; `meta` is a sport figure.
public struct SectionHeader: View {
    private let title: String
    private let meta: String?
    private let action: String?
    private let onAction: (() -> Void)?

    public init(_ title: String, meta: String? = nil, action: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.meta = meta
        self.action = action
        self.onAction = onAction
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
            HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
                Text(title)
                    .thro(ThroTypography.eyebrow.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextSecondary)
                if let meta {
                    Text(meta)
                        .thro(ThroTypography.metadata.family(.sport))
                        .foregroundStyle(ThroColor.colorTextTertiary)
                }
            }
            Spacer(minLength: 0)
            if let action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(action).thro(ThroTypography.labelStrong.weight(.semibold))
                        Icon(.chevronRight, size: 14)
                    }
                    .foregroundStyle(ThroColor.colorTextBrand)
                    .frame(minHeight: ThroSpacing.touchTargetMinimum)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, ThroSpacing.spacing3)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Divider

/// `core/Divider`. One hairline, default or strong, optionally inset from the leading edge.
public struct ThroDivider: View {
    private let inset: CGFloat
    private let strong: Bool
    private let vertical: Bool

    public init(inset: CGFloat = 0, strong: Bool = false, vertical: Bool = false) {
        self.inset = inset
        self.strong = strong
        self.vertical = vertical
    }

    private var color: Color { strong ? ThroColor.colorBorderStrong : ThroColor.colorBorderDefault }

    public var body: some View {
        if vertical {
            Rectangle().fill(color).frame(width: ThroSpacing.borderWidthHairline)
        } else {
            Rectangle().fill(color).frame(height: ThroSpacing.borderWidthHairline).padding(.leading, inset)
        }
    }
}
