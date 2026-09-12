import SwiftUI
import ThroTokens

// The keypad that takes three darts, one at a time.
//
// **Six rows, the same as the visit keypad**, and that constraint produced the design rather than
// something the design had to survive. A nine-row tray — a ring row, five rows of sectors, a bull
// row and Enter — needs 644 points on a phone that has 707 of usable height, which leaves 63 for
// the board, and no rung of the hero ladder fits in 63 points. So the tray holds only what has to
// be tapped:
//
//   1     SINGLE · DOUBLE · TREBLE        the ring, held
//   2–5   the twenty sectors, five a row, 20 down to 1
//   6     25 · BULL · MISS · ENTER        the darts that have no sector, and the commit
//
// and **the darts entered so far are drawn on the board**, under the head, where the chalk is —
// which is where a player looks anyway, and where SLATE says what is being written belongs.
//
// Two orderings are deliberate.
//
// **The sectors count down from 20** (PD-034). The first version laid them out in the board's
// clockwise order, `20 1 18 4 13` first, which had to be learned and split four board neighbours
// across row ends. Counting order needs no learning; the founder set it to run 20 → 1 so the
// numbers a scorer reads most — 20, 19, 18, 17, 16 — are the first row and read left to right in
// the order a player says them. (The ergonomic alternative, 1 → 20 with the big five on the bottom
// row nearest the thumb, was put to the founder and not taken.)
//
// **MISS sits between BULL and ENTER.** Enter is the one control in this app that commits evidence,
// so the key next to it should be the one that costs nothing when it is hit by mistake. A fat-thumb
// slip onto MISS adds zero; the same slip onto BULL would add fifty.

/// The keypad in per-dart mode.
public struct DartKeypad: View {
    @AppStorage(ThroHaptics.enabledKey) private var haptics: Bool = true
    /// Which ring the next sector tap lands in.
    @State private var ring: ThroDart.Ring = .single

    private let entry: ThroDartEntry
    private let disabled: Bool
    /// Whether the entry may be committed. Decided by the caller, because it is a rules question —
    /// three darts, or a visit already settled — and this layer holds no darts rules.
    private let ready: Bool
    private let onDart: (ThroDart) -> Void
    private let onEnter: () -> Void

    public init(entry: ThroDartEntry, disabled: Bool = false, ready: Bool,
                onDart: @escaping (ThroDart) -> Void,
                onEnter: @escaping () -> Void) {
        self.entry = entry
        self.disabled = disabled
        self.ready = ready
        self.onDart = onDart
        self.onEnter = onEnter
    }

    /// The ring row, in the order a player says them.
    public static let rings: [ThroDart.Ring] = [.single, .double, .treble]

    /// The sectors as the keypad lays them out: four rows of five, counting DOWN from 20, so the
    /// first row is 20 to 16 and the last is 5 to 1 (PD-034, as the founder set it).
    ///
    /// `[[20, 19, 18, 17, 16], [15, 14, 13, 12, 11], [10, 9, 8, 7, 6], [5, 4, 3, 2, 1]]`.
    public static let rows: [[Int]] = stride(from: 20, through: 1, by: -5).map { Array(stride(from: $0, through: $0 - 4, by: -1)) }

    /// The three darts on the bottom row that have no sector of their own.
    public static let centres: [ThroDart] = [.outerBull, .bull, .miss]

    /// What a ring key says. The ring is a state and not a verb, so the label is a noun.
    static func ringLabel(_ ring: ThroDart.Ring) -> String {
        switch ring {
        case .single: return "SINGLE"
        case .double: return "DOUBLE"
        case .treble: return "TREBLE"
        case .miss: return "MISS"
        case .outerBull: return "25"
        case .bull: return "BULL"
        }
    }

    /// The label a sector key shows, given the ring that is held: `20`, `D20`, `T20`. A player who
    /// has pressed DOUBLE should see D20 on the key **before** they commit to it, not afterwards.
    static func sectorLabel(_ sector: Int, ring: ThroDart.Ring) -> String {
        ThroDart(ring: ring, sector: sector)?.written ?? "\(sector)"
    }

    /// What Enter says. It carries the running total, because that is the number a player checks
    /// against what they threw — the same contract the visit keypad's Enter key has.
    ///
    /// When it is not ready it says how many darts are still to come, rather than sitting unlit and
    /// unexplained: a key out of the light with nothing to say is a key a player taps twice and then
    /// distrusts.
    static func enterLabel(_ entry: ThroDartEntry, ready: Bool) -> String {
        if entry.isEmpty { return "Enter score" }
        guard ready else {
            let left = ThroDartEntry.perVisit - entry.darts.count
            return left == 1 ? "One more dart" : "\(left) more darts"
        }
        return "Enter \(entry.total)"
    }

    /// A sector or centre key is out of the light once the hand is spent. Three darts is three
    /// darts: the fourth tap is refused by being unavailable rather than by a buzz after the fact.
    private var spent: Bool { disabled || entry.handIsSpent }

    public var body: some View {
        VStack(spacing: ThroSpacing.spacing2) {
            HStack(spacing: ThroSpacing.spacing2) {
                ForEach(Array(DartKeypad.rings.enumerated()), id: \.element) { option in
                    Button(action: { hold(option.element) }) {
                        Text(DartKeypad.ringLabel(option.element))
                            .thro(ThroTypography.labelStrong.uppercase(true).tracking(em: 0.06))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(ScoreKeypad.keyInk(disabled: spent))
                    }
                    .buttonStyle(ChalkKeyStyle(DartKeypad.ringLighting(option.element, held: ring,
                                                                      disabled: spent),
                                               seedAngle: Double(option.offset) * 83 + 29))
                    .disabled(spent)
                    .accessibilityLabel(DartKeypad.ringLabel(option.element).lowercased())
                    .accessibilityAddTraits(ring == option.element ? [.isSelected] : [])
                }
            }
            ForEach(Array(DartKeypad.rows.enumerated()), id: \.element) { row in
                HStack(spacing: ThroSpacing.spacing2) {
                    ForEach(Array(row.element.enumerated()), id: \.element) { column in
                        key(action: { throwDart(ThroDart(ring: ring, sector: column.element)) },
                            seedAngle: Double(row.offset * 5 + column.offset) * 47 + 101) {
                            Text(DartKeypad.sectorLabel(column.element, ring: ring))
                                .thro(ThroTypography.heading2.family(.sport).weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .accessibilityLabel(ThroDart(ring: ring, sector: column.element)?.spoken
                                            ?? "\(column.element)")
                    }
                }
            }
            HStack(spacing: ThroSpacing.spacing2) {
                HStack(spacing: ThroSpacing.spacing2) {
                    ForEach(Array(DartKeypad.centres.enumerated()), id: \.element) { centre in
                        key(action: { throwDart(centre.element) },
                            seedAngle: Double(centre.offset) * 149 + 353) {
                            Text(DartKeypad.centreLabel(centre.element))
                                .thro(ThroTypography.labelStrong.family(.sport).uppercase(true))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .accessibilityLabel(centre.element.spoken)
                    }
                }
                Button(action: { ThroHaptics.play(.commit, enabled: haptics); onEnter() }) {
                    Text(DartKeypad.enterLabel(entry, ready: ready))
                        .thro(ThroTypography.bodyLarge.weight(.bold).uppercase(true).tracking(em: 0.04))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(ScoreKeypad.ink(ready: ready, disabled: disabled))
                }
                .buttonStyle(ChalkKeyStyle(ScoreKeypad.enterLighting(ready: ready, disabled: disabled),
                                           seedAngle: 631))
                .disabled(!ready || disabled)
            }
        }
        .padding(.vertical, ThroSpacing.spacing4)
        .padding(.horizontal, ThroSpacing.spaceScreenGutter)
        // The entry is announced as darts and then the running total, so a player who switches
        // between the two keypads is not told two different kinds of thing about the same visit.
        .onChange(of: entry) { was, now in
            guard was != now, !now.isEmpty else { return }
            AccessibilityNotification.Announcement(now.spoken).post()
        }
    }

    /// What the centre keys say. `ThroDart.written` renders a miss as an em dash, which is right on
    /// a scoresheet and useless on a key: a key has to say what pressing it does.
    static func centreLabel(_ dart: ThroDart) -> String {
        dart.ring == .miss ? "MISS" : dart.written
    }

    /// Where a ring key sits in the lamp's pool. The held ring is the lit one — availability and
    /// selection are both a place in the light, never an opacity, so the whole row stays on the
    /// contrast matrix.
    static func ringLighting(_ option: ThroDart.Ring, held: ThroDart.Ring,
                             disabled: Bool) -> ChalkKeyStyle.Lighting {
        if disabled { return .sunken }
        return option == held ? .lit : .field
    }

    private func hold(_ option: ThroDart.Ring) {
        ThroHaptics.play(.key, enabled: haptics)
        ring = option
    }

    /// A dart lands. **The ring falls back to single afterwards.** Holding TREBLE across one dart is
    /// a convenience; holding it across a visit is a mis-key waiting to happen, because the tap that
    /// would turn a 5 into a 15 is the tap that isn't there.
    private func throwDart(_ dart: ThroDart?) {
        guard let dart, !entry.handIsSpent else { return }
        ThroHaptics.play(.key, enabled: haptics)
        onDart(dart)
        ring = .single
    }

    private func key<Label: View>(action: @escaping () -> Void,
                                  seedAngle: Double,
                                  @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label().foregroundStyle(ScoreKeypad.keyInk(disabled: spent))
        }
        .buttonStyle(ChalkKeyStyle(ScoreKeypad.keyLighting(disabled: spent), seedAngle: seedAngle))
        .disabled(spent)
    }
}

/// The darts entered so far, drawn on the board rather than in the tray.
///
/// Each dart is a tap target of its own, and tapping one takes back everything from it onwards —
/// which is what a player means when they point at the middle dart and say *"that one was a five"*.
public struct ThroDartLine: View {
    private let entry: ThroDartEntry
    private let onTakeBackTo: (Int) -> Void

    public init(entry: ThroDartEntry, onTakeBackTo: @escaping (Int) -> Void) {
        self.entry = entry
        self.onTakeBackTo = onTakeBackTo
    }

    /// The three slots, filled and empty. An empty slot is drawn and not hidden, so the line does
    /// not change width as darts land — the same reason a register keeps its leading cells. An empty
    /// slot is an **empty box**, out of the light: the first version put a dot in it as a
    /// placeholder, which read as three marks the app had made on the board before the player had
    /// thrown anything. Empty means nothing written.
    static func slots(_ entry: ThroDartEntry) -> [ThroDart?] {
        entry.darts.map(Optional.init)
            + Array(repeating: nil, count: max(0, ThroDartEntry.perVisit - entry.darts.count))
    }

    public var body: some View {
        HStack(spacing: ThroSpacing.spacing2) {
            ForEach(Array(ThroDartLine.slots(entry).enumerated()), id: \.offset) { slot in
                Button(action: { onTakeBackTo(slot.offset) }) {
                    Text(ThroDartLine.slotLabel(slot.element))
                        .thro(ThroTypography.heading3.family(.sport).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(ThroColor.colorTextOnBoard)
                }
                .buttonStyle(ChalkKeyStyle(slot.element == nil ? .sunken : .field,
                                           minHeight: ThroSpacing.touchTargetMinimum,
                                           seedAngle: Double(slot.offset) * 71 + 17))
                .disabled(slot.element == nil)
                .accessibilityLabel(slot.element.map { "\($0.spoken), take back from here" }
                                    ?? "no dart yet")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// What a slot shows: the dart as written, or nothing at all. A space and not an empty string,
    /// so the empty slot keeps the text's height and the three boxes stay level.
    static func slotLabel(_ dart: ThroDart?) -> String { dart?.written ?? " " }
}
