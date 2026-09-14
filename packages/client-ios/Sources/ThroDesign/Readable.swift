import SwiftUI
import ThroTokens

// How wide a screen is allowed to get (PD-052).
//
// Every screen in THRØ was drawn for a phone held in one hand, and the app is on iPad too — the target
// carries both device families. Left alone, a paragraph on a 13-inch iPad runs to about 180 characters a
// line, a row's name and its trailing figure end up a hand's width apart, and a form's fields stretch to
// the width of a desk. None of that is a phone screen made bigger; it is a phone screen pulled apart.
//
// So a screen's content sits in a column of comfortable measure and the room around it stays room. The
// measure is 560 points: at the body role's 17-point size that is 60 to 70 characters a line, which is the
// range typography has agreed on for a century and the one the design's own line lengths were drawn at.
// A screen whose subject IS the width — the map, a board at room size, the keypad under a thumb — says so
// by not using this.

/// A column of comfortable measure, centred, with the room around it left as room.
public struct ThroReadable: ViewModifier {
    /// 60–70 characters at the body role. Wider is not more generous; it is harder to read.
    public static let measure: CGFloat = 560

    private let measure: CGFloat

    public init(measure: CGFloat = ThroReadable.measure) {
        self.measure = measure
    }

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: measure)
            .frame(maxWidth: .infinity)
    }
}

public extension View {
    /// Holds this content to a readable column on a wide screen, and changes nothing on a phone, where
    /// the screen is already narrower than the measure.
    func throReadable(_ measure: CGFloat = ThroReadable.measure) -> some View {
        modifier(ThroReadable(measure: measure))
    }
}
