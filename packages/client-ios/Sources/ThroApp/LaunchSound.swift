import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// The opening's two switches, in Settings under Opening (PD-007 v2).
public enum OpeningPreferences {
    public static let soundKey = "thro.openingSound"
    public static let hapticsKey = "thro.openingHaptics"
    /// The three sounds the app bundle carries, synthesised by docs/design/brand/render_sounds.py and
    /// meant to be replaced by recorded foley under the same names.
    public static let soundFiles = ["thro-whoosh", "thro-thud", "thro-chalk"]
}

/// Scores the opening: a whoosh for the flight, a thud for the dart in the board, chalk for the ring,
/// and one heavy haptic at the strike. Sound plays through the ambient session, so the phone's silent
/// switch silences it and other audio keeps playing. A bundle without the files stays silent.
final class LaunchSoundtrack {
    private var players: [String: AVAudioPlayer] = [:]
    private let sound: Bool
    private let haptics: Bool
    private var pending: [DispatchWorkItem] = []
    #if canImport(UIKit)
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    #endif

    init(sound: Bool, haptics: Bool) {
        self.sound = sound
        self.haptics = haptics
        guard sound else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        for name in OpeningPreferences.soundFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[name] = player
        }
    }

    /// Cues are named after their sound file's suffix; "haptic" is the strike's impact.
    func schedule(_ cues: [LaunchCue], from start: Date) {
        for cue in cues {
            let delay = max(0, cue.at - Date().timeIntervalSince(start))
            if cue.name == "haptic" {
                guard haptics else { continue }
                // The Taptic Engine is readied half a second ahead, which is as long as it stays ready.
                later(max(0, delay - 0.5)) { [weak self] in
                    #if canImport(UIKit)
                    self?.impact.prepare()
                    #endif
                }
                later(delay) { [weak self] in
                    #if canImport(UIKit)
                    self?.impact.impactOccurred(intensity: 1.0)
                    #endif
                }
            } else if let player = players["thro-" + cue.name] {
                // Scheduled on the audio device's own clock, which is exact; if the device has no clock
                // yet, on the main queue, which is close enough for a cue.
                let device = player.deviceCurrentTime
                if device > 0 {
                    _ = player.play(atTime: device + delay)
                } else {
                    later(delay) { _ = player.play() }
                }
            }
        }
    }

    private func later(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        pending.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// A tap skipped the opening: nothing more is heard.
    func stop() {
        for item in pending { item.cancel() }
        pending.removeAll()
        for player in players.values { player.stop() }
    }
}
