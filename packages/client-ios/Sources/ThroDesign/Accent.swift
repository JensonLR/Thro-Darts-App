import SwiftUI
import ThroTokens

// A club's own colour, and the rule that keeps the app readable whatever it picks.
//
// **This is a port of `packages/organisation/Branding.kt`, and it exists because the client did not
// have it.** The Kotlin states the rule — *whichever of the brand's two neutrals reads better ON the
// accent, chosen and never configured* — `BrandingTest` sweeps the colour cube to prove no colour
// breaks it, and the pull request has claimed it since the clubs shipped. `Badge` meanwhile set its
// initials in `colorTextInverse` unconditionally. On a dark green that is right by luck; on a club's
// yellow it is chalk on yellow at about 1.4:1, which is not readable at any size.
//
// The lesson is the one this repository keeps relearning: a guarantee asserted on one side of a
// port is not a guarantee. `AccentTests` now holds the Swift to the same arithmetic and to the same
// answers on the same colours.

/// The two neutrals text is ever set in, and the accent a club wears until it chooses one.
///
/// Read from the token layer rather than typed, so the day the palette moves this moves with it —
/// and `AccentTests` asserts the headroom that makes the guarantee true, so if the two neutrals ever
/// drift towards each other a test says so rather than a club discovering it.
public enum AccentBranding {

    /// WCAG 2.x relative luminance. The same arithmetic as the token gate and as `Branding.kt`.
    public static func luminance(_ color: Color) -> Double {
        let (r, g, b) = components(color)
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG 2.x contrast ratio, 1:1 to 21:1.
    public static func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The brand's two neutrals as **fixed** sRGB, which is what they have to be here.
    ///
    /// Not `ThroColor.colorTextPrimary` and `colorTextInverse`, for two reasons and CI found the
    /// second one. They are *semantic pairs that swap*: primary is ink in light and chalk in dark.
    /// A club's badge is a fixed-colour surface, so the text on it must be fixed too — reading a
    /// semantic token would flip a badge's initials from ink to chalk when the phone got dark.
    /// And they are asset-catalogue colours: `NSColor.usingColorSpace` returns nil for a dynamic
    /// one, so resolving them for arithmetic gave black on macOS and every answer was wrong.
    ///
    /// These are the same two values `Branding.kt`'s `Palette` states, for the same reason.
    public static let ink = Color(.sRGB, red: 0x10 / 255, green: 0x12 / 255, blue: 0x11 / 255)
    public static let chalk = Color(.sRGB, red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF2 / 255)

    /// Whichever neutral reads better **on** `accent`. Chosen, never configured — a club picks its
    /// colour and THRØ picks what is legible on it.
    public static func textOn(_ accent: Color) -> Color {
        contrast(chalk, accent) >= contrast(ink, accent) ? chalk : ink
    }

    /// What `textOn` achieves. Shown to a club choosing a colour, because "this reads at 2.9:1 and
    /// the floor is 3:1" is something they can act on and "invalid" is not.
    public static func ratioOn(_ accent: Color) -> Double {
        contrast(textOn(accent), accent)
    }

    /// The floor a colour must clear to carry text at all, matching `Contrast.LARGE_TEXT_MINIMUM`.
    public static let floor = 3.0

    /// Whether the accent may also be used **as** text on the app's own surfaces. Most cannot: a
    /// mid-tone that carries chalk beautifully is unreadable *as* text on chalk.
    public static func usableAsText(_ accent: Color) -> Bool {
        // The app's two surfaces are the same two values as the neutrals, swapped — light paints
        // chalk and dark paints ink — so checking against both is checking both appearances.
        min(contrast(accent, chalk), contrast(accent, ink)) >= floor
    }

    /// The sRGB components of a colour, resolved on whichever platform this is.
    ///
    /// Resolved against the LIGHT appearance deliberately: the two neutrals are fixed brand values
    /// rather than semantic pairs, and an accent is a club's own hex. Resolving in the viewer's
    /// current appearance would make the chosen text colour depend on the phone's dark-mode setting,
    /// so a badge would flip its initials from chalk to ink at sunset.
    static func components(_ color: Color) -> (Double, Double, Double) {
        #if os(watchOS)
        // **Nothing to resolve here.** The trait resolution below pins the answer to the light
        // appearance so a badge does not flip its initials from chalk to ink at sunset; a watch has
        // one appearance and no dynamic colours, and every colour that reaches this function is a
        // fixed sRGB hex, so resolving would be a no-op if the API existed (PD-072).
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #elseif canImport(UIKit)
        let native = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #elseif canImport(AppKit)
        // A dynamic (asset-catalogue) colour has no single sRGB representation and returns nil here.
        // The old fallback was `?? .black`, which is a plausible colour — so a failed resolution
        // produced plausible-looking wrong answers instead of an obvious break. Every colour this
        // function is now asked about is a fixed sRGB value, so nil means a real defect and says so.
        guard let native = NSColor(color).usingColorSpace(.sRGB) else {
            assertionFailure("a colour reached AccentBranding that has no fixed sRGB value")
            return (0, 0, 0)
        }
        return (Double(native.redComponent), Double(native.greenComponent), Double(native.blueComponent))
        #else
        return (0, 0, 0)
        #endif
    }
}

/// The colours offered when a club picks one, so nobody has to type six hex digits.
///
/// **These are content, not design tokens.** They belong to the clubs that wear them, not to THRØ,
/// and the palette is a convenience rather than a constraint: `BrandingTest` proves by sweeping the
/// whole colour cube that *no* colour a club can choose breaks the app, so the custom picker beside
/// these swatches is safe by construction rather than by curation.
public struct AccentSwatch: Identifiable, Equatable, Sendable {
    public let name: String
    public let hex: String
    public var id: String { hex }

    public init(_ name: String, _ hex: String) {
        self.name = name
        self.hex = hex
    }

    public var color: Color { Color.thro(hex: hex) ?? ThroColor.throGreen }

    /// A spread across the hue circle in tones a darts team would actually wear. The brand's own
    /// green is first because it is what a club wears until it chooses.
    public static let palette: [AccentSwatch] = [
        AccentSwatch("THRØ green", "0F3D2E"),
        AccentSwatch("Bottle", "1B5E3A"),
        AccentSwatch("Navy", "1F3A5F"),
        AccentSwatch("Royal", "2456A6"),
        AccentSwatch("Teal", "156B6B"),
        AccentSwatch("Claret", "6E1F35"),
        AccentSwatch("Scarlet", "B4232A"),
        AccentSwatch("Tangerine", "D2601A"),
        AccentSwatch("Gold", "E8B004"),
        AccentSwatch("Amber", "F2C744"),
        AccentSwatch("Plum", "4A2A5A"),
        AccentSwatch("Slate", "44504F"),
        AccentSwatch("Ink", "101211"),
    ]
}

/// Picking a club's colour, without typing six hex digits.
///
/// The founder's note: *"Can we use a better option than hex codes for colour select, not very user
/// friendly."* They were right twice over — a hex field is unfriendly, and it also hid the thing that
/// actually matters. Every swatch here is drawn **as the badge will be drawn**, with the club's own
/// initials in whichever neutral THRØ chooses for that colour, so the choice is made by looking at
/// the result rather than by imagining it.
///
/// The custom well is a plain system `ColorPicker`, and it is safe by construction rather than by
/// curation: `AccentTests` sweeps the colour cube to prove nothing in it breaks the floor.
public struct AccentPicker: View {
    /// Six hex digits, or empty for the brand's own. The stored shape is unchanged — `ClubBook`
    /// refuses anything else, and a picker that produced something the store refuses would be an
    /// app that lies.
    @Binding private var hex: String
    private let initials: String

    public init(hex: Binding<String>, initials: String) {
        self._hex = hex
        self.initials = initials
    }

    private var chosen: Color? { Color.thro(hex: hex) }

    /// The custom well's binding. Reading gives the current colour; writing normalises back to the
    /// six digits the store takes.
    private var custom: Binding<Color> {
        Binding(get: { chosen ?? ThroColor.throGreen },
                set: { hex = AccentPicker.hex(of: $0) })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
            Text("Colour")
                .thro(ThroTypography.labelStrong.weight(.semibold))
                .foregroundStyle(ThroColor.colorTextSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ThroSpacing.spacing3) {
                    ForEach(AccentSwatch.palette) { swatch in
                        Button { hex = swatch.hex } label: {
                            Badge(initials, size: 52, accent: swatch.color)
                                .overlay {
                                    RoundedRectangle(cornerRadius: ThroSpacing.radiusCard + 3,
                                                     style: .continuous)
                                        .strokeBorder(ThroColor.colorTextPrimary, lineWidth: 2)
                                        .padding(-3)
                                        .opacity(hex.uppercased() == swatch.hex ? 1 : 0)
                                }
                                .throRowTapTarget()
                        }
                        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard))
                        .accessibilityLabel(swatch.name)
                        .accessibilityAddTraits(hex.uppercased() == swatch.hex ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -4)

            HStack(spacing: ThroSpacing.spacing3) {
                // `ColorPicker` exists on neither watchOS nor tvOS, and neither does the act: nobody
                // sets a club's colours from a wrist, and nobody drags a colour wheel with a remote.
                // The swatches above are the whole control on both — which is also the only
                // arrangement a watch has room for (PD-072, extended to the TV by PD-079).
                #if !os(watchOS) && !os(tvOS)
                ColorPicker(selection: custom, supportsOpacity: false) {
                    Text("Any other colour")
                        .thro(ThroTypography.body)
                        .foregroundStyle(ThroColor.colorTextPrimary)
                }
                #endif
                if chosen != nil {
                    ThroTextButton("Use THRØ's") { hex = "" }
                }
            }

            // The rule, said out loud where the choice is made. A club that is told its colour reads
            // at 12.4:1 learns something; one told "valid" learns nothing.
            Text(AccentPicker.explain(chosen))
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the screen says about the current choice.
    static func explain(_ accent: Color?) -> String {
        guard let accent else {
            return "No colour chosen, so this wears THRØ's own green. Pick one and the initials on it "
                 + "are set in whichever of THRØ's two colours reads better — you never choose that, "
                 + "so there is nothing you can pick that makes the badge unreadable."
        }
        let ratio = AccentBranding.ratioOn(accent)
        let neutral = AccentBranding.textOn(accent) == ThroColor.colorTextInverse ? "light" : "dark"
        return String(format: "The initials on this are %@, reading at %.1f:1. THRØ picks that for "
                      + "you from the colour, so there is nothing you can choose that makes the badge "
                      + "unreadable.", neutral, ratio)
    }

    /// A picked colour as the six digits the store takes.
    static func hex(of color: Color) -> String {
        let (r, g, b) = AccentBranding.components(color)
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
