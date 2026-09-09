import SwiftUI
import ThroTokens

// SLATE, B.1 and B.2 — the board itself.
//
// A dark green field under one lamp, with chalk dust on it. It is one `RadialGradient` between three
// named tokens and a static `Canvas` of specks, and that is the whole of it: no veil layer, no
// alpha over a solid, no `GeometryReader` reading its own frame back to itself.
//
// **THE BOARD LAW.** No drawing operation on a board may produce a pixel lighter than
// `colorBoardLit` or darker than `colorBoardSunken`, except ink and status ink. That is what makes
// the contrast matrix a description of what renders rather than of an assumed midpoint: `board-lit`
// is the worst ground for every light ink and `board-sunken` is the best, both are named, and
// `build.py --check` measures exactly those.
//
// It is also why the chalk field's specks are `colorBoardLit` and never white. A speck brighter than
// the lamp's own centre would be a pixel the matrix does not cover, drawn under text the matrix
// says is legible.

/// A small deterministic generator, so every speck is where it was on the last frame.
///
/// Moved out of the opening (`ThroApp/LaunchSequence.swift`) and made `public` — an access change,
/// which is why it did not travel with `Easing` and `MarkGeometry` in the move that claimed all four
/// were already public. The dust in the opening and the dust on the board are now the same grain
/// rather than two noises that happen to look alike.
public struct Grain {
    private var state: UInt32
    public init(seed: UInt32) { state = seed }
    /// Uniform in 0..<1.
    public mutating func next() -> CGFloat {
        state = state &* 1_664_525 &+ 1_013_904_223
        return CGFloat(state >> 8) / CGFloat(1 << 24)
    }
}

/// Where the lamp is, for children that need to know. Published by `ThroBoard`; nothing reads its
/// own frame to find out.
public struct ThroLampKey: EnvironmentKey {
    public static let defaultValue = UnitPoint(x: 0.5, y: 0.30)
}

public extension EnvironmentValues {
    var throLamp: UnitPoint {
        get { self[ThroLampKey.self] }
        set { self[ThroLampKey.self] = newValue }
    }
}

/// The board: one lamp, three stops, and chalk dust.
public struct ThroBoard<Content: View>: View {
    private let lamp: UnitPoint
    private let grainSeed: UInt32
    private let content: Content

    public init(lamp: UnitPoint = UnitPoint(x: 0.5, y: 0.30),
                grainSeed: UInt32,
                @ViewBuilder content: () -> Content) {
        self.lamp = lamp
        self.grainSeed = grainSeed
        self.content = content()
    }

    /// The lamp's reach, as a fraction of the longer side. Under 0.86 the corners go flat black
    /// before the edge and the board reads as a vignette filter; over it the pool stops being a pool.
    public static var reach: CGFloat { 0.86 }

    /// The three stops. One gradient IS the lamp pool and the vignette; a separate veil would be a
    /// second layer with an alpha in it, and the alpha is what the board law exists to keep out.
    public static var stops: [Gradient.Stop] {
        [Gradient.Stop(color: ThroColor.colorBoardLit, location: 0),
         Gradient.Stop(color: ThroColor.colorBoardField, location: 0.55),
         Gradient.Stop(color: ThroColor.colorBoardSunken, location: 1)]
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            ZStack {
                RadialGradient(gradient: Gradient(stops: ThroBoard.stops),
                               center: lamp, startRadius: 0, endRadius: ThroBoard.reach * side)
                ChalkField(seed: grainSeed)
                content
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .environment(\.throLamp, lamp)
    }
}

/// The dust on the board. A fixed scatter, the same on every visit.
///
/// Grain, not noise: seeded per screen, so a player who looks twice sees the same board. Drawn as at
/// most five `Path` fills in one static `Canvas` — never a `TimelineView`, which would re-run the
/// whole closure every frame for specks that do not move.
public struct ChalkField: View {
    private let seed: UInt32
    private let density: Double

    /// Hidden entirely under Reduce Transparency. It is the only translucency in the language, so
    /// that setting has exactly one job here and does it completely.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(seed: UInt32, density: Double = 0.6) {
        self.seed = seed
        self.density = density
    }

    /// 180, not the opening's 420. This is a background; the opening's dust is its foreground and
    /// is lit by a beam. A background that competes with the figure on it is not a background.
    public static let speckCount = 180
    /// Quantised so the whole field is at most this many fills.
    public static let tiers = 5
    /// The brightest a speck may be. The ground is never lighter than `colorBoardLit`, and a speck
    /// at half alpha over it cannot exceed it, so the board law holds by construction.
    public static let maximumAlpha: Double = 0.5

    /// The scatter, as unit coordinates and a brightness tier. Deterministic in the seed, and
    /// √-distributed in neither axis — a flat rectangle wants uniform, and the opening's radial
    /// √-distribution is a different problem with a different answer.
    static func scatter(seed: UInt32, count: Int = ChalkField.speckCount) -> [(x: CGFloat, y: CGFloat, r: CGFloat, tier: Int)] {
        var rng = Grain(seed: seed)
        return (0..<count).map { _ in
            let x = rng.next(), y = rng.next()
            let size = 0.4 + 0.9 * rng.next()
            let tier = min(tiers - 1, max(0, Int(rng.next() * CGFloat(tiers))))
            return (x, y, size, tier)
        }
    }

    /// The alpha of one tier. Tier 0 is nearly gone; the top tier is `maximumAlpha`.
    static func alpha(tier: Int, density: Double) -> Double {
        let step = maximumAlpha / Double(tiers)
        return density * step * Double(tier + 1)
    }

    public var body: some View {
        if reduceTransparency {
            Color.clear
        } else {
            Canvas(rendersAsynchronously: false) { context, size in
                let specks = ChalkField.scatter(seed: seed)
                for tier in 0..<ChalkField.tiers {
                    var path = Path()
                    for speck in specks where speck.tier == tier {
                        path.addEllipse(in: CGRect(x: speck.x * size.width - speck.r,
                                                   y: speck.y * size.height - speck.r,
                                                   width: 2 * speck.r, height: 2 * speck.r))
                    }
                    guard !path.isEmpty else { continue }
                    context.fill(path, with: .color(ThroColor.colorBoardLit
                        .opacity(ChalkField.alpha(tier: tier, density: density))))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The seeds boards are drawn with. Held together so two screens cannot accidentally share one and
/// so a screen's field is the same on every visit.
public enum ThroBoardSeed {
    /// `THR\0` — Home.
    public static let home: UInt32 = 0x5448_5200
    /// A match's own field, from its identifier, so a player's board is that match's board.
    public static func match(_ id: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        // Never zero: a zero seed makes the generator emit the same value forever, and the field
        // would be 180 specks in one place.
        return hash == 0 ? 0x5448_5201 : hash
    }
}
