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
/// This is that number, and it is important to be exact about which number it is.
///
/// **It is the cost of building a frame, not of painting one.** `ThroColor` is an asset-catalogue
/// colour and the catalogue does not resolve inside this test bundle: every token here is fully
/// transparent, which was found by rendering a frame and reading its pixels — the whole film came back
/// as nothing over a red background. So the arithmetic, the four hundred dust positions, the path
/// construction, the gradient construction and every `fill` call all happen exactly as they do on a
/// phone, and then Core Graphics is handed clear paint and does very little with it.
///
/// That is still the number worth watching. What runs on the main thread sixty times a second is this
/// closure, and a frame that costs too much to *build* is a dropped frame whatever the GPU does. What
/// it cannot tell anyone is how expensive the film is to rasterise, or whether it holds 60 Hz on an
/// A19. For that there is a device and a pair of eyes, and for the picture itself there is
/// `tools/check_opening_is_never_flat.py`, which reads real screenshots off a real simulator.
///
/// The empty canvas of the same size is measured alongside it and subtracted, so what is reported is
/// `LaunchFrame.draw` rather than the fixed cost of producing a bitmap.
@MainActor
final class OpeningCostTests: XCTestCase {
    /// An iPhone 17 Pro's points, which is the device the film has been judged on.
    private static let size = CGSize(width: 402, height: 874)

    /// Frames sampled evenly across the whole film, so the expensive parts are all in the average:
    /// the dust field, the board, the flight with its smear, the strike, and the wordmark's type.
    private static let samples = 16

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

    /// A yardstick drawn in the same canvas, in the same run, on the same machine.
    ///
    /// **An absolute millisecond ceiling was the wrong instrument.** It passed on a quiet machine and
    /// failed at 77 ms on the same machine with the rest of the suite running beside it — the film had
    /// not changed, the host had. A threshold wide enough to survive a loaded runner would be too wide
    /// to catch anything.
    ///
    /// So the question becomes a ratio: *how many of these is a frame of the opening worth?* Load
    /// slows the yardstick and the film together and the ratio holds. Fourteen hundred filled dots and
    /// three hundred strokes is roughly the shape of the work the film does — a dust field and some paths —
    /// without being any of its actual code, so a change to the film cannot quietly change its own
    /// measuring stick.
    private struct Yardstick: View {
        var body: some View {
            Canvas { context, size in
                for i in 0..<1400 {
                    let a = Double(i) * 0.7391, r = Double(i) / 1400
                    let x = size.width * 0.5 + CGFloat(cos(a * 12) * r) * size.width * 0.48
                    let y = size.height * 0.5 + CGFloat(sin(a * 12) * r) * size.height * 0.48
                    let d = 2 + CGFloat(r) * 6
                    context.fill(Path(ellipseIn: CGRect(x: x - d, y: y - d, width: d * 2, height: d * 2)),
                                 with: .color(.white.opacity(0.35)))
                }
                for i in 0..<320 {
                    var line = Path()
                    let y = size.height * CGFloat(i) / 320
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y + 12))
                    context.stroke(line, with: .color(.white.opacity(0.2)), lineWidth: 1.5)
                }
            }
        }
    }

    func testAFrameOfTheOpeningCostsWhatWeCanAccountFor() {
        // Warm the type cache and whatever else first touch allocates, or the first frame carries
        // everyone else's setup and the mean is a lie.
        _ = profile { LaunchFrame(t: $0, timeline: .standard) }

        let blank = profile { _ in Canvas { _, _ in } }
        let yard = profile { _ in Yardstick() }
        let film = profile { LaunchFrame(t: $0, timeline: .standard) }

        let one = yard.mean - blank.mean
        print(String(format: "opening frame cost: mean %.2f ms, worst %.2f ms at t=%.2f s "
            + "(%.1f and %.1f yardsticks, one being %.2f ms here)",
            film.mean - blank.mean, film.peak - blank.mean, film.peakAt,
            (film.mean - blank.mean) / one, (film.peak - blank.mean) / one, one))
        print("  dearest frames — \(dearest)")

        // **A smoke alarm, not a stopwatch.** Measured across runs the film costs roughly two to
        // three yardsticks a frame and its worst frame four to six, and those figures still move by
        // about forty per cent between runs on the same machine — timing anything on a host that is
        // also running nine hundred other tests is not a precise instrument, and pretending
        // otherwise would produce a test that fails for reasons nobody can act on.
        //
        // So the ceilings are set where only a change of *kind* reaches them: a per-pixel shader, a
        // filter inside the dust loop, a second full pass over the frame. A ten per cent regression
        // will not fail this and is not meant to. What the test is really for is the number it
        // prints, which is how the budget was known before the barrel's material was spent out of it.
        //
        // The worst frame is the one that matters — 60 Hz is a promise about every frame, not about
        // the average.
        XCTAssertGreaterThan(one, 0.05, "the yardstick measured nothing, so the ratios mean nothing")
        XCTAssertLessThan((film.peak - blank.mean) / one, 20.0, "the most expensive frame has multiplied in cost")
        XCTAssertLessThan((film.mean - blank.mean) / one, 10.0, "the average frame has multiplied in cost")
        // A floor, because the ceilings alone cannot tell a fast frame from a frame that was never
        // drawn. A cached render, a `LaunchFrame` that returns early, a renderer handed a zero size:
        // all of those read as free, and all of them would have passed the two ceilings above.
        XCTAssertGreaterThan((film.mean - blank.mean) / one, 0.15, "the film is not being drawn at all")
    }
}
