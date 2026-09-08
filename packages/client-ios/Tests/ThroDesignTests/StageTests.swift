import XCTest
import SwiftUI
import ThroTokens
@testable import ThroDesign

/// The scoring screen's shape, held to the one claim that matters on it.
///
/// PD-005 made the screen fit by choosing a portrait phone and locking the app to it. The founder's
/// answer to that, from a player in a local league: *"People try use different or they're own
/// tablets most of the time"*, and *"Just make what's needed big — that's the main hiccup u see."*
/// So the screen has to fit on a phone held either way and on a tablet held either way, and the
/// number has to stay big while it does.
///
/// Every device below runs iOS 18, which is this app's floor. Sizes are points, portrait. The safe
/// area is taken off before the stage is asked, because a layout that fits the raw screen and not
/// the safe area is a layout that fits nothing.
final class StageTests: XCTestCase {

    /// name, width, height, and the insets iOS actually takes in each orientation.
    struct Device {
        let name: String
        let width: CGFloat
        let height: CGFloat
        /// Portrait: status bar or notch, and the home indicator.
        let portraitInsets: (top: CGFloat, bottom: CGFloat)
        /// Landscape: the bar is thinner, the notch eats the sides instead.
        let landscapeInsets: (top: CGFloat, bottom: CGFloat, sides: CGFloat)
    }

    static let devices: [Device] = [
        // The smallest phone that runs iOS 18. Everything has to work here first.
        Device(name: "iPhone SE (3rd gen)", width: 375, height: 667,
               portraitInsets: (20, 0), landscapeInsets: (0, 0, 0)),
        Device(name: "iPhone 13 mini", width: 375, height: 812,
               portraitInsets: (50, 34), landscapeInsets: (0, 21, 50)),
        Device(name: "iPhone 13 / 14", width: 390, height: 844,
               portraitInsets: (47, 34), landscapeInsets: (0, 21, 47)),
        Device(name: "iPhone 16", width: 393, height: 852,
               portraitInsets: (59, 34), landscapeInsets: (0, 21, 59)),
        Device(name: "iPhone 11 / XR", width: 414, height: 896,
               portraitInsets: (48, 34), landscapeInsets: (0, 21, 48)),
        Device(name: "iPhone 14 Plus", width: 428, height: 926,
               portraitInsets: (47, 34), landscapeInsets: (0, 21, 47)),
        Device(name: "iPhone 16 Pro Max", width: 440, height: 956,
               portraitInsets: (62, 34), landscapeInsets: (0, 21, 62)),
        Device(name: "iPad mini (6th gen)", width: 744, height: 1133,
               portraitInsets: (24, 20), landscapeInsets: (24, 20, 0)),
        Device(name: "iPad (10th gen)", width: 820, height: 1180,
               portraitInsets: (24, 20), landscapeInsets: (24, 20, 0)),
        Device(name: "iPad Pro 11-inch", width: 834, height: 1194,
               portraitInsets: (24, 20), landscapeInsets: (24, 20, 0)),
        Device(name: "iPad Pro 13-inch", width: 1024, height: 1366,
               portraitInsets: (24, 20), landscapeInsets: (24, 20, 0)),
    ]

    /// Every device, both ways up, as the size the scoring screen actually gets.
    static func everyScreen() -> [(name: String, width: CGFloat, height: CGFloat, landscape: Bool)] {
        devices.flatMap { d -> [(String, CGFloat, CGFloat, Bool)] in
            [(d.name + ", upright", d.width, d.height - d.portraitInsets.top - d.portraitInsets.bottom, false),
             (d.name + ", on its side",
              d.height - 2 * d.landscapeInsets.sides,
              d.width - d.landscapeInsets.top - d.landscapeInsets.bottom, true)]
        }
    }

    /// **Every** text size iOS offers, as the ratio it applies to large type — `largeTitle`'s own
    /// scale, which is what the board's figures use.
    ///
    /// The whole range and not a sample of it, because the scoring screen no longer caps its text.
    /// PD-024 capped it at `.accessibility1` and scrolled above that, which was the right answer for
    /// a screen with one layout; `ThroStage` reads the room and the text scale together and picks a
    /// shape that fits, so a player at the largest accessibility size gets a smaller rung and a
    /// shorter ledger rather than a scroll bar under their scoring thumb. That promise is only worth
    /// anything if the top of the range is actually walked.
    static let textScales: [CGFloat] = ThroDynamicType.allScales

    // MARK: - The claim

    func testTheScoringScreenFitsOnEveryDeviceBothWaysUpAtEveryTextSize() {
        for screen in StageTests.everyScreen() {
            for scale in StageTests.textScales {
                for finish in [false, true] {
                    let stage = ThroStage.choose(width: screen.width, height: screen.height,
                                                 onAFinish: finish, textScale: scale)
                    let where_ = "\(screen.name) at \(scale)× \(finish ? "on a finish" : "")"

                    // Every key is hittable AND the tray fits. Both, because either alone is a
                    // lie: keyHeight is clamped at 44 so it never reports an unhittable key, which
                    // means a screen too short for six rows overflows instead of reporting small.
                    XCTAssertTrue(stage.keysFit(in: screen.height),
                                  "\(where_): keys are \(stage.keyHeight) pt in a tray of "
                                  + "\(stage.trayHeight) pt on a \(screen.height) pt screen")

                    // The number is still a number a player can read from the oche.
                    XCTAssertGreaterThanOrEqual(stage.hero, 40, where_)
                    XCTAssertTrue(ThroTypography.ladder.contains(stage.hero),
                                  "\(where_): hero at \(stage.hero) is off the ladder")

                    // And the whole thing adds up: rail + head + ledger + tray ≤ the screen.
                    let tray = stage.arrangement == .stacked
                        ? ThroStage.trayRows * stage.keyHeight
                            + (ThroStage.trayRows - 1) * ThroStage.trayGap + ThroStage.trayPadding
                        : 0
                    let head = ThroStage.headFurniture + (finish ? ThroStage.checkoutRow : 0)
                        + ThroStage.capBox(stage.hero, textScale: scale)
                    let ledger: CGFloat
                    switch stage.ledger {
                    case let .rows(n): ledger = CGFloat(n) * ThroStage.ledgerRow
                    case .tally: ledger = ThroStage.tallyHeight
                    case .hidden: ledger = 0
                    }
                    XCTAssertLessThanOrEqual(ThroStage.rail + head + ledger + tray,
                                             screen.height + 0.5,
                                             "\(where_): the screen does not fit")
                }
            }
        }
    }

    func testTwoScoresAlwaysFitSideBySideAcrossTheBoard() {
        // The head is two three-digit registers. If the chosen rung is too wide for the board they
        // overlap, which is the failure that made the old screen shrink its hero instead.
        for screen in StageTests.everyScreen() {
            for scale in StageTests.textScales {
                let stage = ThroStage.choose(width: screen.width, height: screen.height,
                                             textScale: scale)
                let boardWidth = stage.arrangement == .beside
                    ? screen.width * (1 - stage.trayFraction) : screen.width
                let register = 3 * (ThroFigure.cellRatio * stage.hero * scale).rounded()
                XCTAssertLessThanOrEqual(2 * register,
                                         boardWidth - 2 * ThroStage.gutter - ThroStage.columnGap + 0.5,
                                         "\(screen.name) at \(scale)×: the two registers overlap")
            }
        }
    }

    // MARK: - The arrangement

    func testAScreenTurnedOnItsSidePutsTheKeysBesideTheBoard() {
        // Which is the shape a scoreboard has always had, and the shape you get when a phone is
        // propped up at the oche.
        for screen in StageTests.everyScreen() where screen.landscape {
            let stage = ThroStage.choose(width: screen.width, height: screen.height)
            XCTAssertEqual(stage.arrangement, .beside, screen.name)
            XCTAssertGreaterThan(stage.trayFraction, 0)
            XCTAssertLessThan(stage.trayFraction, 0.5, "\(screen.name): the keys took over the board")
        }
    }

    func testATabletHeldUprightStaysStackedBecauseItHasRoomAbove() {
        for device in StageTests.devices where device.width >= 700 {
            let stage = ThroStage.choose(width: device.width,
                                         height: device.height - device.portraitInsets.top - device.portraitInsets.bottom)
            XCTAssertEqual(stage.arrangement, .stacked, device.name)
            XCTAssertEqual(stage.trayFraction, 0)
        }
    }

    func testTheTrayNeverGrowsWiderThanAHand() {
        // A keypad that scales with a 13-inch tablet is a keypad whose keys are further apart than
        // the hand using it.
        let stage = ThroStage.choose(width: 1366, height: 1024 - 44)
        XCTAssertEqual(stage.arrangement, .beside)
        XCTAssertLessThanOrEqual(1366 * stage.trayFraction, ThroStage.trayMaximum + 0.5)
    }

    // MARK: - Big, where a player needs it

    func testATabletGetsTheBiggestNumberOnTheLadder() {
        // "People try use different or they're own tablets most of the time." A tablet is a
        // scoreboard on a table and it should look like one.
        for device in StageTests.devices where device.width >= 700 {
            let stage = ThroStage.choose(width: device.width,
                                         height: device.height - device.portraitInsets.top - device.portraitInsets.bottom)
            XCTAssertEqual(stage.hero, ThroTypography.ladder.first, device.name)
        }
    }

    func testTheSmallestPhoneStillGetsAHeroWorthLookingAt() {
        let d = StageTests.devices[0]   // iPhone SE, the floor
        let stage = ThroStage.choose(width: d.width,
                                     height: d.height - d.portraitInsets.top - d.portraitInsets.bottom)
        XCTAssertGreaterThanOrEqual(stage.hero, 56, "the SE's hero fell below the third rung")
        XCTAssertEqual(stage.keyHeight, ThroSpacing.touchTargetScoring,
                       "the SE has room for full-size keys and should get them")
    }

    func testTheOpponentIsOneRungDownAndNeverTheSameSizeAsTheThrower() {
        for screen in StageTests.everyScreen() {
            let stage = ThroStage.choose(width: screen.width, height: screen.height)
            XCTAssertTrue(ThroTypography.ladder.contains(stage.opponent), screen.name)
            if stage.hero != ThroTypography.ladder.last {
                XCTAssertLessThan(stage.opponent, stage.hero,
                                  "\(screen.name): both scores are the same size, so neither leads")
            }
        }
    }

    // MARK: - The ledger

    func testTheLedgerIsNeverClippedAndDegradesInDeclaredSteps() {
        // Three declared states and no fourth. A list that is cut off at the bottom is the one
        // outcome that makes a player doubt what is on the board.
        for screen in StageTests.everyScreen() {
            let stage = ThroStage.choose(width: screen.width, height: screen.height)
            switch stage.ledger {
            case let .rows(n):
                XCTAssertGreaterThan(n, 0, "\(screen.name): zero rows should be .tally or .hidden")
                XCTAssertLessThanOrEqual(n, 6, screen.name)
                XCTAssertEqual(stage.ledgerRows, n)
            case .tally, .hidden:
                XCTAssertEqual(stage.ledgerRows, 0)
            }
        }
    }

    func testAShortScreenGivesUpTheLedgerBeforeItGivesUpTheNumber() {
        // The order of sacrifice. A leg's history is worth having; the score is the product. The
        // iPhone SE upright is the real case: 647 points of safe area, a 434 pt tray, and what is
        // left after the head is 29 — a tally strip, declared, rather than three rows clipped.
        let d = StageTests.devices[0]
        let se = ThroStage.choose(width: d.width,
                                  height: d.height - d.portraitInsets.top - d.portraitInsets.bottom)
        XCTAssertEqual(se.hero, 96, "the smallest phone still gets the biggest number")
        XCTAssertEqual(se.keyHeight, ThroSpacing.touchTargetScoring)
        XCTAssertEqual(se.ledger, .tally, "and it is the ledger that gives way, not the score")
    }

    func testAKeyHeightAtTheFloorIsNotTheSameThingAsATrayThatFits() {
        // 568 × 299 is a 4-inch phone on its side. It does not run iOS 18 and is not in the device
        // list, but it is the shape that proves the two halves are different questions: the clamp
        // holds the key at 44, and six 44 pt rows plus their gaps need 314 points of a 299 pt
        // screen. A check that only read the key height would call this fine.
        let tiny = ThroStage.choose(width: 568, height: 299)
        XCTAssertEqual(tiny.keyHeight, ThroSpacing.touchTargetMinimum)
        XCTAssertFalse(tiny.keysFit(in: 299), "the tray overflows and the check did not notice")
    }

    // MARK: - It is a function, so it answers the same way twice

    func testTheSameScreenAlwaysGetsTheSameShape() {
        let a = ThroStage.choose(width: 390, height: 763, onAFinish: true, textScale: 1.12)
        let b = ThroStage.choose(width: 390, height: 763, onAFinish: true, textScale: 1.12)
        XCTAssertEqual(a, b)
    }

    func testABiggerTextSizeNeverProducesABiggerHero() {
        // Dynamic Type makes every glyph larger, so the rung can only come down. A ladder that went
        // up under larger text would be reading its own output.
        for screen in StageTests.everyScreen() {
            var previous = CGFloat.greatestFiniteMagnitude
            for scale in StageTests.textScales {
                let stage = ThroStage.choose(width: screen.width, height: screen.height, textScale: scale)
                XCTAssertLessThanOrEqual(stage.hero, previous, "\(screen.name) at \(scale)×")
                previous = stage.hero
            }
        }
    }
}
