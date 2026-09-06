import XCTest
import SwiftUI
import ThroTokens
@testable import ThroApp

/// PD-007's opening: the timeline, the easings it runs on, and the mark's geometry.
final class LaunchSequenceTests: XCTestCase {
    func testSegmentsAreContiguousAndTheWholeOpeningIsBrief() {
        for timeline in [LaunchTimeline.standard, LaunchTimeline.reduced] {
            let s = timeline.segments
            XCTAssertEqual(s.first?.start, 0)
            for (a, b) in zip(s, s.dropFirst()) { XCTAssertEqual(a.end, b.start, "\(a.name) must hand straight to \(b.name)") }
            XCTAssertLessThanOrEqual(timeline.total, 2.4, "an opening is a door, not a wait")
        }
        XCTAssertEqual(LaunchTimeline.standard.total, 2.30, accuracy: 1e-9)
        XCTAssertEqual(LaunchTimeline.standard.finishAt, 2.00, accuracy: 1e-9)
    }

    func testReduceMotionHasNoMotionSegments() {
        let r = LaunchTimeline.reduced
        for seg in [r.approach, r.loop, r.strike, r.impact, r.name] { XCTAssertEqual(seg.duration, 0, seg.name) }
        // From the very first frame every motion segment reads complete, so the finished composition shows at once.
        for seg in [r.approach, r.loop, r.strike, r.impact, r.name] { XCTAssertEqual(seg.progress(at: 0), 1, seg.name) }
        XCTAssertGreaterThan(r.hold.duration, 0.5, "a moment to read the name")
    }

    func testProgressClampsAndIsLinearWithin() {
        let loop = LaunchTimeline.standard.loop
        XCTAssertEqual(loop.progress(at: 0), 0)
        XCTAssertEqual(loop.progress(at: loop.start + loop.duration / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(loop.progress(at: 9), 1)
    }

    func testTokenEasingsAreMonotoneAndHitTheirEnds() {
        for curve in [ThroMotion.motionEasingThrow, ThroMotion.motionEasingImpact, ThroMotion.motionEasingResolve, ThroMotion.motionEasingSet] {
            XCTAssertEqual(Easing.cubicBezier(curve, 0), 0, accuracy: 1e-6)
            XCTAssertEqual(Easing.cubicBezier(curve, 1), 1, accuracy: 1e-6)
            var last = -1.0
            for i in 0...50 {
                let y = Easing.cubicBezier(curve, Double(i) / 50)
                XCTAssertGreaterThanOrEqual(y, last - 1e-6); last = y
            }
        }
        // The throw curve is front-loaded: most of the distance goes early, as a thrown dart's does.
        XCTAssertGreaterThan(Easing.throwCurve(0.3), 0.6)
    }

    func testTheGeometryKeepsTheMeasuredProportions() {
        let g = MarkGeometry(tipToTip: 104)
        XCTAssertEqual(g.tipToTip, 104, accuracy: 1e-9)
        XCTAssertEqual(g.ringOuter / g.unit, 0.364, accuracy: 1e-9)
        XCTAssertEqual(g.ringInner / g.unit, 0.250, accuracy: 1e-9)
        XCTAssertEqual(g.ringWidth, g.ringOuter - g.ringInner, accuracy: 1e-9)
        // The finished dart spans tip to tip on the 45° axis.
        let box = g.dart(at: CGPoint(x: 100, y: 100)).boundingRect
        XCTAssertEqual(box.width, 2 * g.tip * CGFloat(0.5).squareRoot(), accuracy: 0.01)
        XCTAssertEqual(box.height, box.width, accuracy: 0.01)
    }

    func testTheStrikeEndsOnTheFinishedDart() {
        let g = MarkGeometry(unit: 300)
        let c = CGPoint(x: 200, y: 300)
        let finished = g.dart(at: c).boundingRect
        let struck = g.dart(at: c, headAt: g.tip, tailAt: -g.tip).boundingRect
        XCTAssertEqual(finished, struck)
        // Half-way through the strike the head is inside the ring and the tail already behind it.
        let mid = g.dart(at: c, headAt: 0, tailAt: -g.tip).boundingRect
        XCTAssertLessThan(mid.width, finished.width)
    }

    func testTheRingArcSweepsFromTheLowerLeft() {
        let g = MarkGeometry(unit: 300)
        let c = CGPoint(x: 0, y: 0)
        let (start, heading) = g.onRing(c, degrees: 135)
        XCTAssertLessThan(start.x, 0); XCTAssertGreaterThan(start.y, 0)          // lower-left on screen
        XCTAssertLessThan(heading.dy, 0)                                         // setting off upward
        XCTAssertTrue(g.ringArc(at: c, sweepDegrees: 0).isEmpty)
        XCTAssertFalse(g.ringArc(at: c, sweepDegrees: 360).isEmpty)
    }
}
