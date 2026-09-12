import SwiftUI
import ThroTokens

// How much of a screen the brand field covers (PD-052, PD-060).
//
// Some pages open on the brand field: the green runs under the clock and behind the header, and the page's
// own paper carries the content below it. The field has one job — be taller than the clock plus however far
// somebody can drag the page down — because if a pull reveals paper above the field, the page looks like two
// screens stacked.
//
// It was written as a flat 400 points, and 400 points is not a design decision. It is the answer to "how far
// can this be pulled" measured on a phone held upright, and that question has a different answer on a screen
// of a different height. Turn the same phone on its side and 400 points is the whole screen: an iPhone 17 Pro
// is 402 points tall in landscape and an SE is 320. The field stopped being the top of the page and became
// the page.
//
// So the number keeps its ceiling and gains a share. Every portrait phone lands on the ceiling exactly as it
// did — 400 on a 17 Pro, 398 on an SE, which is the same screen to the eye — and a screen too short for the
// ceiling gets a field proportionate to it instead of one that swallows it.

/// The brand field behind the top of a page, and how tall it is allowed to be.
public enum ThroBrandField {

    /// Enough green that a hard pull on a portrait phone never reveals paper above the field. This is the
    /// number every portrait screen was drawn against and it does not move.
    public static let tallest: CGFloat = 400

    /// And never more of the screen than this, which is what makes it a field at the top of a page rather
    /// than the page itself. At 0.7 no portrait phone changes: the shortest, an SE at 568 points, asks for
    /// 398 and would have taken 400.
    public static let share: CGFloat = 0.7

    /// How tall to draw the field on a screen of this height.
    ///
    /// A container of no height is one that has not been laid out yet; it draws nothing either way, so the
    /// ceiling is returned rather than a zero that would flash paper on the first frame.
    public static func height(in containerHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0 else { return tallest }
        return min(tallest, containerHeight * share)
    }
}

public extension View {
    /// The brand field behind the top of a page whose header scrolls with it — under the clock, and above
    /// the page when it is pulled down — so it reads the same as a page whose header stays put.
    ///
    /// A page that opens on the field and has a paper strip above it looks like two screens stacked. The
    /// page's own content carries its paper below the header, so none of this shows between the cards; the
    /// field only has to be taller than the clock plus a pull, and never taller than the screen it is on.
    func throBrandFieldBehind() -> some View {
        background(alignment: .top) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    ThroColor.colorBackgroundBrand
                        .frame(height: ThroBrandField.height(in: proxy.size.height))
                    ThroColor.colorBackgroundPrimary
                }
            }
            .ignoresSafeArea()
        }
    }
}
