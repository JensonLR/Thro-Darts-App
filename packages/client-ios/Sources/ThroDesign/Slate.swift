import SwiftUI
import ThroTokens

// The brand on the paper side.
//
// The chalkboard has been the app's only unmistakable surface, and it lived on one screen. These
// three pieces carry it — and the mark — to the rest of the journey without turning every screen
// green: a **slate** is a board-coloured panel a paper screen can hold one thing on (the fixture,
// where you are, what is near), the **mark** is the Ø drawn from its own measured geometry rather
// than a bitmap, and a **bottom action** is the primary button of a screen pinned where a thumb is,
// on a hairline, so a set-up screen ends in a decision and not in scroll.

/// The founder's mark — the ring and the dart through it — as a shape, at the proportions measured
/// off the artwork (`MarkGeometry.Ratios.mark`). Tip to tip fills the shorter side of the rect.
public struct ThroMark: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let geometry = MarkGeometry(tipToTip: min(rect.width, rect.height))
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = geometry.ringShape(at: centre)
        path.addPath(geometry.bar(at: centre))
        return path
    }
}

/// A board-coloured panel on a paper screen: the lamp's three stops, the chalk dust, square-ish
/// card corners. Whatever is put on it is written in chalk, so the caller draws its content in
/// `colorTextOnBoard` and its secondary lines in `colorTextOnBoardSecondary`.
public struct ThroSlate<Content: View>: View {
    private let seed: UInt32
    private let lamp: UnitPoint
    private let content: Content

    public init(seed: UInt32 = 7, lamp: UnitPoint = UnitPoint(x: 0.5, y: 0.25), @ViewBuilder content: () -> Content) {
        self.seed = seed
        self.lamp = lamp
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geo in
                    ZStack {
                        RadialGradient(gradient: Gradient(stops: ThroBoard<EmptyView>.stops), center: lamp,
                                       startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * ThroBoard<EmptyView>.reach)
                        ChalkField(seed: seed, density: 0.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ThroSpacing.radiusCard, style: .continuous))
    }
}

/// A fixture written on a slate: two names either side of the mark, the format under them in
/// chalk boxes, and one line of small print. What Match ready shows, and what a fixture row opens to.
public struct ThroFixtureSlate: View {
    private let home: String
    private let away: String
    private let tags: [String]
    private let footnote: String?

    public init(home: String, away: String, tags: [String] = [], footnote: String? = nil) {
        self.home = home
        self.away = away
        self.tags = tags
        self.footnote = footnote
    }

    public var body: some View {
        ThroSlate {
            VStack(spacing: ThroSpacing.spacing5) {
                HStack(alignment: .center, spacing: ThroSpacing.spacing4) {
                    name(home, alignment: .trailing)
                    ThroMark()
                        .fill(ThroColor.colorMarkOnBoard)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    name(away, alignment: .leading)
                }
                if !tags.isEmpty {
                    HStack(spacing: ThroSpacing.spacing2) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .thro(ThroTypography.label.family(.sport).uppercase(true).tracking(em: 0.06))
                                .foregroundStyle(ThroColor.colorTextOnBoard)
                                .padding(.vertical, ThroSpacing.spacing2)
                                .padding(.horizontal, ThroSpacing.spacing3)
                                .overlay(ChalkBox(weight: 2).fill(ThroColor.colorMarkOnBoard))
                        }
                    }
                }
                if let footnote {
                    Text(footnote)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, ThroSpacing.spacing7)
            .padding(.horizontal, ThroSpacing.spacing5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(home) versus \(away)" + (tags.isEmpty ? "" : ", " + tags.joined(separator: ", ")))
    }

    private func name(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .thro(ThroTypography.heading1.family(.sport).weight(.bold).tracking(em: 0))
            .foregroundStyle(ThroColor.colorTextOnBoard)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// The screen's one decision, pinned at the bottom on a hairline. A screen that ends in this does
/// not need to scroll to be finished.
public struct ThroBottomAction<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 0) {
            ThroDivider()
            content
                .padding(.horizontal, ThroSpacing.spaceScreenGutter)
                .padding(.top, ThroSpacing.spacing4)
                .padding(.bottom, ThroSpacing.spacing3)
        }
        .background(ThroColor.colorBackgroundPrimary.ignoresSafeArea(edges: .bottom))
    }
}

/// A labelled choice on one line: the eyebrow on the left, the control taking the rest. Four of
/// these are a format; four stacked eyebrows-over-controls were a scroll.
public struct ThroChoiceRow<Control: View>: View {
    private let label: String
    private let control: Control
    /// The label column. Wide enough for "THROWS FIRST" on one line at the eyebrow's tracking;
    /// fixed so four rows line up.
    public static var labelWidth: CGFloat { 108 }

    public init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: ThroSpacing.spacing3) {
            Eyebrow(label)
                .frame(width: ThroChoiceRow<EmptyView>.labelWidth, alignment: .leading)
            control
        }
        .accessibilityElement(children: .contain)
    }
}
