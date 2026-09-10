import SwiftUI
import ThroTokens
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The two families the design names, and whether they are actually present.
///
/// The token's own stack is `"Archivo", …, system-ui` for UI text and `"IBM Plex Sans Condensed",
/// "Archivo", system-ui` for sport figures — so the system face IS the designed fallback. What the
/// design forbids is *silent* substitution. The app target embeds ten static faces under the SIL Open
/// Font License (PD-006); a build without them — a package test, a target that forgot the files —
/// falls back to the system face and says so out loud rather than substituting quietly.
public enum ThroFont {
    public static let uiFamily = "Archivo"
    public static let sportFamily = "IBM Plex Sans Condensed"

    /// `CaseIterable` so a test can walk every family and hold that each has a measured cap ratio;
    /// `Hashable` because a family is a legitimate key. Adding a family is then a compile error at
    /// every exhaustive switch that has to know about it, which is the point.
    public enum Family: Hashable, Sendable, CaseIterable { case ui, sport }

    /// The embedded faces by PostScript name, one per weight the type roles use, so a weight resolves
    /// to the face that carries it rather than to whatever the system matches by family. The names are
    /// the `name` table's (ID 6) of the files in `apps/ios/ThroDarts/Fonts`; `apps/ios/check_fonts.py`
    /// holds the two in agreement on every push.
    public static func faceName(_ family: Family, weight: Font.Weight) -> String {
        switch family {
        case .ui:
            switch weight {
            case .medium: return "Archivo-Medium"
            case .semibold: return "Archivo-SemiBold"
            case .bold: return "Archivo-Bold"
            case .heavy: return "Archivo-ExtraBold"
            case .black: return "Archivo-Black"
            default: return "Archivo-Regular"
            }
        case .sport:
            // IBM Plex Sans Condensed stops at Bold; heavy and black take the family's heaviest face.
            switch weight {
            case .medium: return "IBMPlexSansCond-Medium"
            case .semibold: return "IBMPlexSansCond-SemiBold"
            case .bold, .heavy, .black: return "IBMPlexSansCond-Bold"
            default: return "IBMPlexSansCond-Regular"
            }
        }
    }

    /// Every face the app embeds, by PostScript name.
    public static let embeddedFaces: [String] = [
        "Archivo-Regular", "Archivo-Medium", "Archivo-SemiBold", "Archivo-Bold", "Archivo-ExtraBold", "Archivo-Black",
        "IBMPlexSansCond-Regular", "IBMPlexSansCond-Medium", "IBMPlexSansCond-SemiBold", "IBMPlexSansCond-Bold",
    ]

    /// True only when BOTH families are registered. Half a type system is not the type system.
    public static var customFacesRegistered: Bool {
        isRegistered(uiFamily) && isRegistered(sportFamily)
    }

    static func isRegistered(_ family: String) -> Bool {
        #if canImport(UIKit)
        return UIFont.familyNames.contains(family)
        #elseif canImport(AppKit)
        return NSFontManager.shared.availableFontFamilies.contains(family)
        #else
        return false
        #endif
    }

    /// Dynamic Type for the system fallback. Custom faces scale through `Font.custom(_:size:relativeTo:)`;
    /// a plain `Font.system(size:)` would ignore the user's text size entirely, which ADR-010 forbids
    /// for type roles.
    static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        return UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size)
        #else
        return size
        #endif
    }

    private static let log = Logger(subsystem: "app.thro", category: "typography")
    private static var reported = false

    /// Logged once per process, so a missing font is a line in the log rather than a silent swap.
    static func reportSubstitutionIfNeeded() {
        guard !reported, !customFacesRegistered else { return }
        reported = true
        log.warning("Custom fonts are not embedded (\(uiFamily, privacy: .public) / \(sportFamily, privacy: .public)); showing the system face. The design forbids silent substitution — see docs/runbooks/CLIENT_IOS.md.")
    }
}

#if canImport(UIKit)
extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
#endif

/// One type role from the token layer: family, size, line, weight, tracking, and the text style it
/// scales relative to. ADR-010 encodes the scalable-versus-fixed split in the token type — type roles
/// scale with Dynamic Type, spacing and radius do not — so the scaling lives here and nowhere else.
///
/// The min/max clamps and what hero numerals do at accessibility sizes are DESIGN_UNSPECIFIED #1
/// and are not invented here: roles scale by the platform's own curve, and the runbook records the
/// gap.
public struct ThroTypeRole: Equatable, Sendable {
    public let family: ThroFont.Family
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let weight: Font.Weight
    /// In em, as the token states it. Points are `size * trackingEm`.
    public let trackingEm: CGFloat
    public let relativeTo: Font.TextStyle
    public let uppercase: Bool
    /// `font-variant-numeric: tabular-nums` — every sport figure sets it, so a score does not jitter.
    public let tabularNumerals: Bool

    public init(
        family: ThroFont.Family, size: CGFloat, lineHeight: CGFloat, weight: Font.Weight,
        trackingEm: CGFloat = 0, relativeTo: Font.TextStyle, uppercase: Bool = false,
        tabularNumerals: Bool = false
    ) {
        self.family = family
        self.size = size
        self.lineHeight = lineHeight
        self.weight = weight
        self.trackingEm = trackingEm
        self.relativeTo = relativeTo
        self.uppercase = uppercase
        self.tabularNumerals = tabularNumerals
    }

    public var font: Font {
        ThroFont.reportSubstitutionIfNeeded()
        let base: Font
        if ThroFont.customFacesRegistered {
            // The weight is in the face's name; asking CoreText to weight a family would let it guess.
            base = Font.custom(ThroFont.faceName(family, weight: weight), size: size, relativeTo: relativeTo)
        } else {
            base = Font.system(size: ThroFont.scaled(size, relativeTo: relativeTo), weight: weight)
        }
        return tabularNumerals ? base.monospacedDigit() : base
    }

    public var tracking: CGFloat { size * trackingEm }

    /// The height of this role's capitals at the user's text size: the family's measured cap ratio
    /// against the scaled point size. What a strike or a basis rule sizes itself from, because a bar
    /// laid through a figure is proportioned to the figure and not to the line box round it.
    public var capHeight: CGFloat {
        ThroTypography.capRatio(family) * ThroFont.scaled(size, relativeTo: relativeTo)
    }
    /// SwiftUI has no line-height; line spacing is the gap above the font's own height.
    public var lineSpacing: CGFloat { max(0, lineHeight - size) }

    public func family(_ f: ThroFont.Family) -> ThroTypeRole {
        ThroTypeRole(family: f, size: size, lineHeight: lineHeight, weight: weight, trackingEm: trackingEm,
                     relativeTo: relativeTo, uppercase: uppercase,
                     tabularNumerals: f == .sport ? true : tabularNumerals)
    }

    public func weight(_ w: Font.Weight) -> ThroTypeRole {
        ThroTypeRole(family: family, size: size, lineHeight: lineHeight, weight: w, trackingEm: trackingEm,
                     relativeTo: relativeTo, uppercase: uppercase, tabularNumerals: tabularNumerals)
    }

    /// The same role at another size, with the line height carried across in proportion.
    ///
    /// This exists for the density ladder: a screen with less room steps the board's hero DOWN the
    /// approved scale rather than shrinking it with `minimumScaleFactor`, which is what a figure
    /// does when nobody chose a size for it. Every size passed here is expected to be on the
    /// approved scale, and `ThroTypography.ladder` is the list of the ones that are.
    public func sized(_ points: CGFloat) -> ThroTypeRole {
        guard size > 0 else { return self }
        return ThroTypeRole(family: family, size: points,
                            lineHeight: (lineHeight / size * points).rounded(),
                            weight: weight, trackingEm: trackingEm, relativeTo: relativeTo,
                            uppercase: uppercase, tabularNumerals: tabularNumerals)
    }
}

/// The roles, sized from the token layer. Named ThroTypography because `ThroType` is the generated
/// enum of raw sizes.
public enum ThroTypography {
    public static let scoreHero = ThroTypeRole(
        family: .sport, size: ThroType.typographyScoreHeroSize, lineHeight: ThroSpacing.typographyScoreHeroLine,
        weight: .bold, trackingEm: -0.03, relativeTo: .largeTitle, tabularNumerals: true)
    public static let sportHero = ThroTypeRole(
        family: .sport, size: ThroType.typographySportHeroSize, lineHeight: ThroSpacing.typographySportHeroLine,
        weight: .bold, trackingEm: -0.02, relativeTo: .largeTitle, tabularNumerals: true)
    public static let ratingHero = ThroTypeRole(
        family: .sport, size: ThroType.typographyRatingHeroSize, lineHeight: ThroSpacing.typographyRatingHeroLine,
        weight: .bold, trackingEm: -0.02, relativeTo: .largeTitle, tabularNumerals: true)
    public static let display = ThroTypeRole(
        family: .ui, size: ThroType.typographyDisplaySize, lineHeight: ThroSpacing.typographyDisplayLine,
        weight: .heavy, trackingEm: -0.015, relativeTo: .largeTitle)
    public static let heading1 = ThroTypeRole(
        family: .ui, size: ThroType.typographyHeading1Size, lineHeight: ThroSpacing.typographyHeading1Line,
        weight: .heavy, trackingEm: -0.01, relativeTo: .title)
    public static let heading2 = ThroTypeRole(
        family: .ui, size: ThroType.typographyHeading2Size, lineHeight: ThroSpacing.typographyHeading2Line,
        weight: .bold, relativeTo: .title2)
    public static let heading3 = ThroTypeRole(
        family: .ui, size: ThroType.typographyHeading3Size, lineHeight: ThroSpacing.typographyHeading3Line,
        weight: .bold, relativeTo: .title3)
    public static let bodyLarge = ThroTypeRole(
        family: .ui, size: ThroType.typographyBodyLargeSize, lineHeight: ThroSpacing.typographyBodyLargeLine,
        weight: .regular, relativeTo: .body)
    public static let body = ThroTypeRole(
        family: .ui, size: ThroType.typographyBodyDefaultSize, lineHeight: ThroSpacing.typographyBodyDefaultLine,
        weight: .regular, relativeTo: .body)
    public static let label = ThroTypeRole(
        family: .ui, size: ThroType.typographyLabelDefaultSize, lineHeight: ThroSpacing.typographyLabelDefaultLine,
        weight: .semibold, relativeTo: .subheadline)
    public static let labelStrong = ThroTypeRole(
        family: .ui, size: ThroType.typographyLabelStrongSize, lineHeight: ThroSpacing.typographyLabelStrongLine,
        weight: .bold, relativeTo: .footnote)
    public static let metadata = ThroTypeRole(
        family: .ui, size: ThroType.typographyMetadataSize, lineHeight: ThroSpacing.typographyMetadataLine,
        weight: .regular, relativeTo: .caption)
    /// `.thro-eyebrow`: 13/16, 0.09em, uppercase, semibold, text-secondary.
    public static let eyebrow = ThroTypeRole(
        family: .ui, size: ThroType.typographyEyebrowSize, lineHeight: ThroSpacing.typographyEyebrowLine,
        weight: .semibold, trackingEm: 0.09, relativeTo: .caption, uppercase: true)

    /// The figure on a board (SLATE B.5). `scoreHero`'s size and weight with **tracking forced to
    /// zero**, because a fixed-cell register and negative tracking are incompatible: `scoreHero`
    /// carries −0.03 em, which at 96 pt is −2.88 pt per glyph and tears the grid apart.
    ///
    /// SLATE specified 88 pt for this. **88 is not on the approved type scale**, so it would have
    /// been an off-scale bypass of the kind the design's own gate rejects in every platform source
    /// — and at 0.540 em per cell, two three-digit registers at 88 pt come to 285 pt, which does not
    /// fit the 320 pt iPhone SE either. The size lives on the scale and the density ladder chooses
    /// which rung, which is the honest version of the same intent.
    public static let boardHero = ThroTypeRole(
        family: .sport, size: ThroType.typographyScoreHeroSize,
        lineHeight: ThroSpacing.typographyScoreHeroLine,
        weight: .bold, trackingEm: 0, relativeTo: .largeTitle, tabularNumerals: true)

    /// The rungs the board's hero may stand on, largest first. Every one is on the approved scale,
    /// which is what stops a density ladder from becoming a licence to invent a size.
    public static let ladder: [CGFloat] = [96, 72, 56, 40]

    /// Cap height as a fraction of point size, measured per family off the embedded faces rather
    /// than assumed: IBM Plex Sans Condensed's cap is 0.698 em and Archivo's is 0.686 em.
    ///
    /// A `switch` and not a dictionary, so there is **no fallback**. A dictionary lookup with a
    /// default is how a new family silently gets somebody else's cap height and every figure drawn
    /// in it sits a point or two off its own baseline, on a screen nobody re-measured.
    public static func capRatio(_ family: ThroFont.Family) -> CGFloat {
        switch family {
        case .ui: return 0.686
        case .sport: return 0.698
        }
    }

    /// The height a figure actually needs: its capitals, and two points so the chalk edge is not
    /// shaved. **A line box is not a cap box.** The box a `Text` occupies reserves ascent, descent
    /// and leading that a row of digits never reaches into — at `boardHero` the cap box is 69
    /// points against a 96 point em box, so **27 points per figure** come back to whatever sits
    /// under it, which is what funds the ledger. (SLATE put that saving at 55.8; it is not a number
    /// these ratios produce, and 27 is what they do produce.)
    public static func capBox(_ role: ThroTypeRole) -> CGFloat {
        let scaled = ThroFont.scaled(role.size, relativeTo: role.relativeTo)
        return (capRatio(role.family) * scaled).rounded() + 2
    }

    /// How far to lift a cell so its capitals sit on the box's baseline: half the leftover line box,
    /// less the descender the digits do not use.
    public static func capTrim(_ role: ThroTypeRole) -> CGFloat {
        let scaled = ThroFont.scaled(role.size, relativeTo: role.relativeTo)
        let natural = max(scaled, ThroFont.scaled(role.lineHeight, relativeTo: role.relativeTo))
        let cap = capRatio(role.family) * scaled
        let descender = 0.22 * scaled
        return ((natural - cap) / 2 - descender).rounded()
    }

    /// Every role, for the test that holds each size to the approved scale.
    public static let all: [ThroTypeRole] = [
        scoreHero, sportHero, ratingHero, display, heading1, heading2, heading3,
        bodyLarge, body, label, labelStrong, metadata, eyebrow, boardHero,
    ]
}

extension View {
    /// Applies a type role: font, tracking, line spacing and case. Colour is the caller's.
    public func thro(_ role: ThroTypeRole) -> some View {
        self.font(role.font)
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
            .textCase(role.uppercase ? .uppercase : nil)
    }
}

/// `.thro-eyebrow` as a view. Colour defaults to text-secondary as the class does.
public struct Eyebrow: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color = ThroColor.colorTextSecondary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text).thro(ThroTypography.eyebrow).foregroundStyle(color)
    }
}

/// Shown when the custom faces are not embedded. The design forbids silent substitution; this makes
/// it visible on the device rather than buried in a log. It renders nothing when the fonts are there.
public struct FontSubstitutionNotice: View {
    public init() {}

    public var body: some View {
        if !ThroFont.customFacesRegistered {
            HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
                Icon(.triangleAlert, size: 18)
                    .foregroundStyle(ThroColor.colorStatusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fonts not embedded")
                        .thro(ThroTypography.label.weight(.bold))
                        .foregroundStyle(ThroColor.colorTextPrimary)
                    Text("Showing the system face. Archivo and IBM Plex Sans Condensed must be added to the app once the licence is confirmed.")
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextSecondary)
                }
            }
            .padding(ThroSpacing.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThroColor.colorStatusWarningSurface)
            .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusMedium))
            .accessibilityElement(children: .combine)
        }
    }
}
