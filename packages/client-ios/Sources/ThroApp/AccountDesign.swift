import SwiftUI
import ThroDesign
import ThroTokens

// The account and settings screens, drawn in THRØ's own hand.
//
// **What was wrong.** The founder, on Settings: *"the spacing on settings page is really ugly &
// design is too colour palette & style, branding & design needs to be aligned throughout our E2E
// journey."* Right on both counts. Every section title sat on the hairline of the row above it —
// the export's list gives each section eight points above and sixteen below, and ours had dropped
// both — and the whole area was grey icons on a system list: the one corner of the app that looked
// like every other app, straight after an opening and a welcome drawn on the board.
//
// **What it is now is made of what Home and the You tab are already made of, and nothing new:**
//  - the brand field at the top, chalk on `colorBackgroundBrand` — Home's masthead;
//  - the slate, for whoever is signed in — the You tab's;
//  - raised cards for the rows — Home's `ContinueCard`: `colorBackgroundRaised`, one hairline, the
//    card radius — with each row's icon on a tile of the brand, so the green runs through the list
//    instead of stopping at the header.
// Sections sit `spaceSectionGap` apart, which is the token that exists to say how far apart
// sections sit.

/// The top of an account or settings page: the brand field, chalk on it, and the way back.
///
/// Home's masthead, with a title and a back chevron. The chevron is `PageBar`'s, so the gutter rule
/// `check_screen_bars.py` holds every page bar to holds here as well.
struct BoardHeader: View {
    let title: String
    var eyebrow: String? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack {
                PageBar(onBack: onBack, ink: ThroColor.throChalk)
            }
            VStack(alignment: .leading, spacing: ThroSpacing.spacing1) {
                if let eyebrow {
                    Eyebrow(eyebrow, color: ThroColor.throChalk.opacity(0.78))
                }
                Text(title)
                    .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
                    .foregroundStyle(ThroColor.throChalk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, ThroSpacing.spaceScreenGutter)
            .padding(.top, onBack == nil ? ThroSpacing.spacing6 : ThroSpacing.spacing1)
            .padding(.bottom, ThroSpacing.spacing5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The field the app launches on, as Home's masthead is — throGreen in light, throGreenDeep in
        // dark — with chalk on it rather than an inverse token, which is ink in dark mode (1.99:1).
        .background(ThroColor.colorBackgroundBrand)
    }
}

/// A group of rows on one raised card, under an eyebrow, with the explanation under the card
/// rather than inside it — so the rows stay rows and the prose stays readable.
struct CardGroup<Content: View>: View {
    private let title: String?
    private let footnote: String?
    private let alarming: Bool
    private let content: Content

    init(_ title: String? = nil, footnote: String? = nil, alarming: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.alarming = alarming
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThroSpacing.spacing2) {
            if let title {
                Eyebrow(title)
                    .padding(.horizontal, ThroSpacing.spacing1)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ThroColor.colorBackgroundRaised)
                .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous)
                    .strokeBorder(ThroColor.colorBorderDefault, lineWidth: 1))
            if let footnote {
                Text(footnote)
                    .thro(ThroTypography.metadata)
                    .foregroundStyle(alarming ? ThroColor.colorStatusError : ThroColor.colorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ThroSpacing.spacing1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row's icon on a tile of the brand: the green, running through the list.
struct IconTile: View {
    enum Tone: Equatable { case brand, destructive }

    let icon: ThroIcon?
    /// A system symbol where a mark is required rather than chosen — Apple's, on a Sign in with
    /// Apple control.
    var symbol: String? = nil
    var tone: Tone = .brand

    static let side: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ThroSpacing.radiusControl, style: .continuous)
                .fill(tone == .brand ? ThroColor.colorBackgroundBrandSubtle : ThroColor.colorStatusErrorSurface)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            } else if let icon {
                Icon(icon, size: 17)
            }
        }
        .foregroundStyle(tone == .brand ? ThroColor.colorTextBrand : ThroColor.colorStatusError)
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }
}

/// One row of a card that does something: a tile, the words, and a chevron only when it goes
/// somewhere. A row that acts where it sits does not pretend to lead anywhere.
struct CardRow: View {
    let icon: ThroIcon?
    var symbol: String? = nil
    let label: String
    var value: String? = nil
    var tone: IconTile.Tone = .brand
    var leads: Bool = true
    let action: () -> Void

    static let height: CGFloat = 56
    /// Where a row's words start. The hairline between two rows starts there too.
    static let textInset: CGFloat = ThroSpacing.spacing4 + IconTile.side + ThroSpacing.spacing3

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThroSpacing.spacing3) {
                IconTile(icon: icon, symbol: symbol, tone: tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .thro(ThroTypography.body)
                        .foregroundStyle(tone == .destructive ? ThroColor.colorStatusError : ThroColor.colorTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let value {
                        Text(value)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: ThroSpacing.spacing2)
                if leads {
                    Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextTertiary)
                }
            }
            .padding(.horizontal, ThroSpacing.spacing4)
            .padding(.vertical, ThroSpacing.spacing3)
            .frame(maxWidth: .infinity, minHeight: CardRow.height, alignment: .leading)
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: 0, pressedFill: ThroColor.colorSurfaceSecondary, scales: false))
        .accessibilityElement(children: .combine)
    }
}

/// A switch, as a row of a card. The switch is the platform's, in the brand's colour.
struct CardToggleRow: View {
    let icon: ThroIcon
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            IconTile(icon: icon)
            Toggle(isOn: $isOn) {
                Text(label).thro(ThroTypography.body).foregroundStyle(ThroColor.colorTextPrimary)
            }
            .tint(ThroColor.colorSurfaceBrand)
        }
        .padding(.horizontal, ThroSpacing.spacing4)
        .padding(.vertical, ThroSpacing.spacing2)
        .frame(minHeight: CardRow.height)
    }
}

/// A fact, as a row of a card. It goes nowhere, so it has no chevron and does not press.
struct CardInfoRow: View {
    let icon: ThroIcon
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: ThroSpacing.spacing3) {
            IconTile(icon: icon)
            Text(label)
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ThroSpacing.spacing3)
            Text(value)
                .thro(ThroTypography.label)
                .foregroundStyle(ThroColor.colorTextSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, ThroSpacing.spacing4)
        .padding(.vertical, ThroSpacing.spacing3)
        .frame(minHeight: CardRow.height)
        .accessibilityElement(children: .combine)
    }
}

/// A sentence, as a row of a card: for lists that are statements rather than choices.
struct CardLine: View {
    let icon: ThroIcon
    var tone: IconTile.Tone = .brand
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: ThroSpacing.spacing3) {
            IconTile(icon: icon, tone: tone)
            // LocalizedStringKey, so emphasis in the sentence is emphasis and not four asterisks — the
            // same bargain `Note` makes. A string with no emphasis in it renders exactly as before.
            Text(LocalizedStringKey(text))
                .thro(ThroTypography.body)
                .foregroundStyle(ThroColor.colorTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ThroSpacing.spacing1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ThroSpacing.spacing4)
        .padding(.vertical, ThroSpacing.spacing3)
        .accessibilityElement(children: .combine)
    }
}

/// Anything inside a card that is not a row — a segmented control, a sentence — on the card's padding.
struct CardPad<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(ThroSpacing.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The hairline between two rows of a card, starting where the words do.
struct CardDivider: View {
    var body: some View { ThroDivider(inset: CardRow.textInset) }
}

// The brand field moved to ThroDesign, where its height can be held to the screen it is on
// rather than to a constant measured in portrait (PD-060): `throBrandFieldBehind()`.

/// Whoever is signed in, on the You tab's slate: the first thing in Settings, because it is the row
/// people come for and it used to be the last one on the screen.
struct AccountSlate: View {
    let account: YouScreen.Account
    let picture: Image?
    /// Nil when there is nowhere to go — a build that names no server.
    let action: (() -> Void)?

    /// The slate's words. Shorter than the You tab's, because this is a row to tap and not a page.
    static func words(_ account: YouScreen.Account) -> (title: String, detail: String) {
        switch account {
        case .none: return ("This phone", "This build names no server, so what you score stays here.")
        case .signedOut: return ("Sign in", "Get your name on your darts. It takes one tap.")
        case .busy(let what): return (what, "One moment.")
        case .unverified: return ("Signed in on this phone", "THRØ could not confirm it just now.")
        case .signedIn(let name, let band, let friends):
            // One line, the You tab's own: it wrapped when it tried to list what was behind the row.
            let age = band == "adult" ? "18 or over" : band == "minor" ? "Under 18" : "Age not said yet"
            let mates = friends.map { $0 == 1 ? "1 friend" : "\($0) friends" } ?? "Your profile"
            return (name ?? "No name yet", "\(age) · \(mates)")
        }
    }

    /// The same two-letter rule every roster in the app uses.
    static func initials(_ name: String?) -> String {
        let letters = (name ?? "").split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        let w = Self.words(account)
        Button { action?() } label: {
            ThroSlate(seed: 71) {
                HStack(spacing: ThroSpacing.spacing4) {
                    mark
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.title)
                            .thro(ThroTypography.heading2.family(.sport).weight(.bold).tracking(em: 0))
                            .foregroundStyle(ThroColor.colorTextOnBoard)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(w.detail)
                            .thro(ThroTypography.metadata)
                            .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ThroSpacing.spacing2)
                    if action != nil {
                        Icon(.chevronRight, size: 16).foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                    }
                }
                .padding(ThroSpacing.spacing4)
            }
            .throRowTapTarget()
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.radiusCard))
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var mark: some View {
        if case .signedIn(let name, _, _) = account {
            PersonMark(initials: Self.initials(name), size: 52, picture: picture)
        } else {
            ThroMark()
                .fill(ThroColor.colorMarkOnBoard)
                .frame(width: 34, height: 34)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
    }
}
