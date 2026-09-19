import XCTest
import SwiftUI
@testable import ThroApp

/// What one frame of the opening costs.
///
/// The film is one `Canvas` redrawn at 60 Hz from a pure function of `t`, and every change to it so far
/// has added drawing: a board, a lamp that travels, a camera that moves. The next changes want gradients
/// and blend modes, which are the expensive kind. **Nobody had a number**, so "can we afford this" had
/// only ever been answered by looking at it, on a device fast enough to hide the answer.
///
/// This is that number. It is not the phone's number and does not pretend to be: it renders through
/// `ImageRenderer` on the test host's CPU, with no GPU path and no display link. What it is good for is
/// the two things a budget is actually for — knowing the order of magnitude before spending, and failing
/// loudly if a change makes the frame several times more expensive than it was.
///
/// The empty canvas of the same size is measured alongside it and subtracted, so what is reported is the
/// cost of `LaunchFrame.draw` rather than the cost of rasterising a bitmap.
@MainActor
final class OpeningCostTests: XCTestCase {
    /// An iPhone 17 Pro's points, which is the device the film has been judged on.
    private static let size = CGSize(width: 402, height: 874)

    /// Frames sampled evenly across the whole film, so the expensive parts are all in the average:
    /// the dust field, the board, the flight with its smear, the strike, and the wordmark's type.
    private static let samples = 24

    /// The four dearest sampled instants of the last profile, so the peak can be attributed rather than
    /// guessed at — the answer is the flight, and the reason is that a smear is fourteen more darts.
    private var dearest = ""

    private func profile<V: View>(_ make: (Double) -> V) -> (mean: Double, peak: Double, peakAt: Double) {
        var each: [(t: Double, ms: Double)] = []
        for i in 0..<Self.samples {
            let t = LaunchTimeline.standard.total * Double(i) / Double(Self.samples - 1)
            // The median of three, not one: a test host with anything else running on it produces
            // single renders three and four times the true cost, and a threshold wide enough to
            // survive those would be too wide to catch a real regression.
            //
            // **A fresh renderer for every run.** `ImageRenderer.cgImage` memoises, so three reads of
            // one renderer time the drawing once and a cache lookup twice — which is what the first
            // version of this did, and it reported the whole film as costing nothing. The floor
            // assertion at the end of the test exists because of that hour.
            let runs = (0..<3).map { _ -> Double in
                let renderer = ImageRenderer(content:
                    make(t).frame(width: Self.size.width, height: Self.size.height))
                renderer.scale = 3
                let taken = ContinuousClock().measure { _ = renderer.cgImage }
                return Double(taken.components.seconds) * 1000
                    + Double(taken.components.attoseconds) / 1e15
            }.sorted()
            each.append((t, runs[1]))
        }
        let worst = each.max { $0.ms < $1.ms }!
        self.dearest = each.sorted { $0.ms > $1.ms }.prefix(4)
            .map { String(format: "%.2f s: %.1f ms", $0.t, $0.ms) }.joined(separator: ", ")
        return (each.reduce(0) { $0 + $1.ms } / Double(each.count), worst.ms, worst.t)
    }

    func testAFrameOfTheOpeningCostsWhatWeCanAccountFor() {
        // Warm the type cache and whatever else first touch allocates, or the first frame carries
        // everyone else's setup and the mean is a lie.
        _ = profile { LaunchFrame(t: $0, timeline: .standard) }

        let blank = profile { _ in Canvas { _, _ in } }
        let film = profile { LaunchFrame(t: $0, timeline: .standard) }

        print(String(format: "opening frame cost: mean %.2f ms, worst %.2f ms at t=%.2f s; "
            + "an empty canvas of the same size costs %.2f ms",
            film.mean - blank.mean, film.peak - blank.mean, film.peakAt, blank.mean))
        print("  dearest frames — \(dearest)")

        // Ceilings with room in them. Measured on an M-series Mac the film costs about 3 ms of
        // drawing per frame, and its dearest frames — all of them inside the flight, where a smear
        // is fourteen more darts — about twice that. These sit at five or six times today's figures:
        // wide enough that a loaded CI runner never fails them, tight enough to catch somebody
        // putting a per-pixel shader or a hundred more gradients inside the dust loop.
        //
        // The worst frame is the one that matters — 60 Hz is a promise about every frame, not about
        // the average.
        XCTAssertLessThan(film.peak - blank.mean, 30.0, "the most expensive frame has multiplied in cost")
        XCTAssertLessThan(film.mean - blank.mean, 18.0, "the average frame has multiplied in cost")
        // A floor, because the ceilings alone cannot tell a fast frame from a frame that was never
        // drawn. A cached render, a `LaunchFrame` that returns early, a renderer handed a zero size:
        // all of those read as free, and all of them would have passed the two ceilings above.
        XCTAssertGreaterThan(film.mean - blank.mean, 0.5, "the film is not being drawn at all")
    }
}
