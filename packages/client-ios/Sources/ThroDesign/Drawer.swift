import SwiftUI
import ThroTokens

// A board over a map (PD-046). The leagues map is the first screen whose ground is a map rather
// than paper, and what sits over it is a board rising from the bottom edge — the lamp at its top
// edge, chalk dust, rounded top corners, a chalk dash to take hold of — with round board coins for
// the two things a map needs at its top: back, and where am I.

/// Which way a drawer was pushed. Outside the drawer's own type, which is generic in its content: a
/// caller's handler names this without having to name what the drawer holds.
public enum ThroDrawerDrag: Sendable { case up, down }

/// A board that rises from the bottom of the screen. Drag it up or down; the caller decides what up
/// and down mean. Only a drag that starts on its top edge moves it, so a list inside it scrolls.
public struct ThroDrawer<Content: View>: View {
    public typealias Drag = ThroDrawerDrag

    private let seed: UInt32
    private let onDrag: (Drag) -> Void
    private let content: Content

    public init(seed: UInt32 = 11, onDrag: @escaping (Drag) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
        self.seed = seed
        self.onDrag = onDrag
        self.content = content()
    }

    /// How far down from its top edge a drag may start and still move the drawer.
    public static var grip: CGFloat { 64 }

    public var body: some View {
        VStack(spacing: 0) {
            ChalkRule(weight: 4, seedAngle: 17)
                .fill(ThroColor.colorMarkOnBoard)
                .frame(width: 40, height: 8)
                .padding(.top, ThroSpacing.spacing2)
                .padding(.bottom, ThroSpacing.spacing1)
                .accessibilityHidden(true)
            content
        }
        .frame(maxWidth: .infinity)
        .background {
            // The lamp hangs over the top edge: the drawer is brightest where it meets the map and
            // falls to the bottom stop at the screen's edge, the board's one gradient and no veil.
            GeometryReader { geo in
                ZStack {
                    RadialGradient(gradient: Gradient(stops: ThroBoard<EmptyView>.stops), center: UnitPoint(x: 0.5, y: 0),
                                   startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * ThroBoard<EmptyView>.reach)
                    ChalkField(seed: seed, density: 0.5)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: ThroSpacing.radiusSheet,
                                              topTrailingRadius: ThroSpacing.radiusSheet, style: .continuous))
            .ignoresSafeArea(edges: .bottom)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard value.startLocation.y < Self.grip else { return }
                    let dy = value.predictedEndTranslation.height
                    if dy < -48 { onDrag(.up) } else if dy > 48 { onDrag(.down) }
                }
        )
    }
}

/// A round board coin over a map: a glyph in chalk on the field stop, ringed in the boundary ink.
public struct ThroCoinButton: View {
    private let icon: ThroIcon
    private let label: String
    private let action: () -> Void

    public init(_ icon: ThroIcon, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Icon(icon, size: 20)
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .frame(width: ThroSpacing.touchTargetMinimum, height: ThroSpacing.touchTargetMinimum)
                .background(Circle().fill(ThroColor.colorBoardField))
                .overlay(Circle().strokeBorder(ThroColor.colorMarkOnBoard, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(ThroPressStyle(radius: ThroSpacing.touchTargetMinimum / 2))
        .accessibilityLabel(label)
    }
}
