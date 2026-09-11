import SwiftUI
import ThroTokens
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Clubs, leagues and tournaments in the design system (PD-010).
//
// PD-010 lifted the no-invention rule for these screens only, and narrowly: tokens only, approved
// components first, and anything genuinely new drawn in the system's own idiom and put on the record
// rather than slipped in. One element here is new — `Badge` — and it is recorded in
// DESIGN_INVENTORY.md as engineering-drawn. Everything else is assembly.

/// A club, league or tournament's badge.
///
/// **Only a club's.** A person already has a mark in the system — `PlayerIdentity` draws a grey
/// circle with their initials, and this does not replace, extend or imitate it. The distinction is
/// the point: a club is a rounded square in its own colour and a person is a grey circle, so the two
/// never read as the same kind of thing in a list, and that difference costs no new component
/// because one of the two already existed.
///
/// A club that has chosen a colour wears it, and the initials on it are chalk or ink — whichever
/// reads better against it, chosen here rather than configured by the club. That is the same
/// guarantee `packages/organisation` makes for the accent, in the one place a club's colour is
/// allowed to be large.
///
/// Recorded in `docs/design/DESIGN_INVENTORY.md` as engineering-drawn under PD-010, not exported.
public struct Badge: View {
    private let initials: String
    private let accent: Color?
    private let size: CGFloat
    /// The club's own badge, when it has one (PD-014). It fills the same rounded square the initials
    /// would, so a list of clubs stays a list of one shape whether or not anybody uploaded anything.
    private let image: Image?

    public init(_ initials: String, size: CGFloat = 48, accent: Color? = nil, image: Image? = nil) {
        self.initials = String(initials.prefix(3)).uppercased()
        self.size = size
        self.accent = accent
        self.image = image
    }

    /// The initials, in the same face and at the same proportion as `PlayerIdentity`'s mark uses —
    /// so the two marks are siblings even though their shapes say different things.
    private var role: ThroTypeRole {
        ThroTypeRole(family: .sport, size: (size * 0.38).rounded(), lineHeight: (size * 0.38).rounded(),
                     weight: .bold, relativeTo: .caption, tabularNumerals: true)
    }
    private var fill: Color { accent ?? ThroColor.throGreenTint }

    /// Chosen, never configured — and now actually chosen.
    ///
    /// This read `accent == nil ? throGreen : colorTextInverse`, which is **always chalk on any
    /// accent**. That is right by luck on a dark green and wrong on a club's yellow, where chalk on
    /// yellow is about 1.4:1. `Branding.kt` has stated the rule since clubs shipped and
    /// `BrandingTest` sweeps the colour cube to prove it holds; the Swift never implemented it. A
    /// guarantee asserted on one side of a port is not a guarantee.
    private var ink: Color {
        guard let accent else { return ThroColor.throGreen }   // the untinted brand badge
        return AccentBranding.textOn(accent)
    }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
    }

    public var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(shape)
            } else {
                Text(initials)
                    .thro(role)
                    .foregroundStyle(ink)
                    .frame(width: size, height: size)
                    .background(fill, in: shape)
            }
        }
        .overlay(shape.strokeBorder(ThroColor.colorTextPrimary.opacity(0.06), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

public extension Image {
    /// A picture from bytes this device holds, or nil when the bytes are not one.
    ///
    /// `Image(data:)` does not exist, and the platform's decoders live in different frameworks, so
    /// this is the one place that knows which. Returning nil rather than a placeholder is deliberate:
    /// a badge that cannot be read falls back to the initials, which is a mark, rather than to a
    /// broken-image glyph, which is a complaint.
    static func thro(data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }
}

/// One club, league or tournament in a list.
public struct OrganisationRow: View {
    private let initials: String
    private let name: String
    private let meta: String
    private let accent: Color?
    private let trailing: String?
    private let image: Image?

    public init(initials: String, name: String, meta: String, accent: Color? = nil,
                trailing: String? = nil, image: Image? = nil) {
        self.initials = initials
        self.name = name
        self.meta = meta
        self.accent = accent
        self.trailing = trailing
        self.image = image
    }

    public var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            Badge(initials, size: 48, accent: accent, image: image)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .thro(ThroTypography.label.weight(.bold))
                    .foregroundStyle(ThroColor.colorTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                // The meta is a three-part join — "Thursday nights · 18 teams · Stockton-on-Tees" — which
                // does not fit one line of a phone, and this row is the backbone of Discover, You and a
                // club's page. So it wraps: two readable lines beat one line of type too small to read
                // (PD-052).
                Text(meta)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(ThroColor.colorTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: ThroSpacing.spacing2)
            if let trailing { Tag(trailing) }
        }
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
    }
}

/// A club's colour, its badge and its name.
///
/// The band is the one place a club's colour is allowed to be large, and it carries no text — so the
/// contrast verdict never has to be consulted for it. The badge sits ON the band with a ring in the
/// page's own background, so it reads as an object in front rather than a shape that overlaps.
public struct OrganisationHeader: View {
    private let initials: String
    private let name: String
    private let kind: String
    private let meta: String
    private let image: Image?
    private let accent: Color
    private let verified: Bool
    private let role: String?

    public init(initials: String, name: String, kind: String, meta: String,
                accent: Color = ThroColor.throGreen, verified: Bool = false, role: String? = nil,
                image: Image? = nil) {
        self.image = image
        self.initials = initials
        self.name = name
        self.kind = kind
        self.meta = meta
        self.accent = accent
        self.verified = verified
        self.role = role
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accent
                .frame(height: 64)
                .padding(.horizontal, -ThroSpacing.spaceScreenGutter)
            Badge(initials, size: 62, accent: accent, image: image)
                .padding(5)
                .background(
                    ThroColor.colorBackgroundPrimary,
                    in: RoundedRectangle(cornerRadius: ThroSpacing.radiusCard + 3, style: .continuous)
                )
                .offset(y: -26)
                .padding(.bottom, -26 + ThroSpacing.spacing3)
            HStack(spacing: 8) {
                Text(name).thro(ThroTypography.heading2).foregroundStyle(ThroColor.colorTextPrimary)
                if verified {
                    Icon(.circleCheck, size: 17)
                        .foregroundStyle(ThroColor.colorStatusVerified)
                        .accessibilityLabel("THRØ verified")
                }
                Spacer(minLength: ThroSpacing.spacing2)
                if let role { Tag(role, tone: .brand) }
            }
            Text("\(kind) · \(meta)")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .padding(.top, 2)
        }
    }
}

extension Color {
    /// A club's colour, as six hex digits. Returns nil rather than guessing — three-digit shorthand
    /// and anything else is refused, for the same reason `packages/organisation` refuses it: a club
    /// pasting `#fc0` and getting `#ffcc00` is a guess about what they meant, and it is visible.
    public static func thro(hex text: String) -> Color? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
