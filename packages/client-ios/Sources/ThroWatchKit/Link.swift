import Foundation
import ThroLiveKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// The link between the phone and the wrist — both ends of it, in one file.
//
// Both ends together for the reason `ThroLiveKit` holds both ends of the Live Activity: the app
// starts and updates it, the extension draws it, and the thing that can go wrong is the two halves
// disagreeing about the shape. A payload written in one module and read in another is the same
// mistake at a longer distance.
//
// **Application context, not messages and not user info.** WatchConnectivity offers three ways to
// move a dictionary and only one of them suits a scoreboard:
//
//   * `sendMessage` needs the counterpart reachable *right now* and fails when it is not, which is
//     most of the time — a watch screen is off between glances.
//   * `transferUserInfo` is a FIFO queue that delivers every item in order, so a wrist that was out
//     of range walks forward through a dozen dead scores before reaching the live one. A scoreboard
//     showing 180 remaining because that is where the replay has got to is worse than showing
//     nothing.
//   * `updateApplicationContext` keeps exactly **one** dictionary, replaces it on every write, and
//     hands the latest one over the moment the counterpart next runs. Which is the whole
//     requirement, stated.
//
// **This is not sync, and the rule that sync is never last-write-wins is not being bent.** Nothing
// on the watch is a source of truth: the wrist has no journal, writes nothing back, and holds
// exactly the projection the Lock Screen and the widgets hold. Last-write-wins is not a conflict
// policy here — there is no second writer to conflict with. The moment the watch can *score*, this
// transport stops being sufficient and a leg from a wrist becomes journal events like any other.

/// What crosses the link, apart from the sending, so the shape can be tested without two devices.
///
/// Property-list types only, because that is all `updateApplicationContext` accepts — the state
/// travels as the JSON it already knows how to be, since it was made `Codable` for ActivityKit.
public enum ThroWristPayload {
    /// Marks a dictionary as ours and says which shape it is. A context that is not ours is ignored
    /// rather than read as "nothing live": a wrist that blanked itself on an unrecognised message
    /// would be reporting a link failure as an idle phone.
    static let markKey = "thro"
    static let mark = 1
    static let legKey = "leg"
    static let formatKey = "format"

    public static func context(_ state: ThroLiveState?, format: String) -> [String: Any] {
        var context: [String: Any] = [markKey: mark, formatKey: format]
        if let state, let data = try? JSONEncoder().encode(state) {
            context[legKey] = data
        }
        return context
    }

    /// Reads one back. `nil` means the dictionary is not ours; a `nil` *state* inside means the
    /// phone is telling us there is nothing on, which is a fact and not an absence of one.
    public static func read(_ context: [String: Any]) -> (state: ThroLiveState?, format: String)? {
        guard context[markKey] as? Int == mark else { return nil }
        let format = context[formatKey] as? String ?? ""
        guard let data = context[legKey] as? Data else { return (nil, format) }
        guard let state = try? JSONDecoder().decode(ThroLiveState.self, from: data) else {
            // Ours, but unreadable — a phone running a newer shape than this watch. Say nothing is
            // on rather than draw a guess.
            return (nil, format)
        }
        return (state, format)
    }
}

/// The link itself: the phone's side sends, the watch's side receives, and off both it does nothing.
///
/// Every platform guard is in here rather than scattered through the callers, which is the pattern
/// `LiveBoard` already sets for ActivityKit — a scoring path riddled with conditional compilation is
/// a scoring path nobody can read.
public final class ThroWristLink: NSObject {
    public static let shared = ThroWristLink()

    /// Where a received context lands. Only the watch's side ever writes to it.
    private let wrist: ThroWrist

    /// The last thing the phone was asked to send, kept until a session exists to take it.
    ///
    /// Activation is asynchronous, and the first thing a launch does is tell the wrist that nothing
    /// is on — which would otherwise be dropped on the floor, leaving a watch showing the leg a
    /// phone was killed in the middle of, forever. Holding one dictionary is not a queue: it is the
    /// same latest-wins rule the transport itself has, applied a moment earlier.
    private var latest: [String: Any]?
    private let lock = NSLock()

    public init(wrist: ThroWrist = .shared) {
        self.wrist = wrist
        super.init()
    }

    /// Activates the session, once, at launch on both ends.
    ///
    /// The watch must activate before it can be handed the context that was waiting for it, and the
    /// phone must activate before it can leave one. Calling it twice is harmless.
    public func start() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() }
        #endif
    }

    /// Leaves the latest leg where the watch will find it. Silent when there is no watch, which is
    /// the normal state of most phones and not a fault.
    public func send(_ state: ThroLiveState?, format: String) {
        lock.lock()
        latest = ThroWristPayload.context(state, format: format)
        lock.unlock()
        flush()
    }

    /// Writes whatever is latest, if there is anywhere to write it.
    ///
    /// Called on every send, when activation completes, and when a watch appears — a player who
    /// installs the watch app in the middle of a night out should not have to end the match to see
    /// it work. Writing the same context twice is free: the transport keeps one and replaces it.
    private func flush() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        lock.lock()
        let context = latest
        lock.unlock()
        guard let context else { return }
        // Throws only for a dictionary the system cannot carry or a session that is not up; there
        // is nothing useful to do about either from the middle of a leg, and a scoring screen that
        // stopped to complain about a watch would be the worse failure. It stays in `latest`, so the
        // next visit carries it.
        try? session.updateApplicationContext(context)
        #endif
    }

    /// Hands an arrived context to the wrist. Separate from the delegate method so a test can call
    /// it without a `WCSession`, which no test process has.
    public func receive(_ context: [String: Any]) {
        guard let (state, format) = ThroWristPayload.read(context) else { return }
        if let state {
            wrist.show(state, format: format)
        } else {
            wrist.clear()
        }
    }
}

#if canImport(WatchConnectivity)
extension ThroWristLink: WCSessionDelegate {
    public func session(_ session: WCSession,
                        activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {
        #if os(iOS)
        // Anything the launch asked for before the session was up.
        guard state == .activated else { return }
        flush()
        #endif
        #if os(watchOS)
        // The context that was waiting is already on the session by the time activation completes;
        // it does not arrive as a delegate callback. Reading it here is what makes a watch opened
        // mid-leg show the leg rather than an empty board.
        guard state == .activated else { return }
        let waiting = session.receivedApplicationContext
        guard !waiting.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.receive(waiting) }
        #endif
    }

    public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        // Delivered off the main thread. `ThroWrist` publishes, so the hop happens here — one place,
        // for the same reason every platform guard is in one place.
        DispatchQueue.main.async { [weak self] in self?.receive(context) }
    }

    #if os(iOS)
    /// A watch was paired, unpaired, or had the app installed. The one that matters is the install:
    /// until then every send is refused, so without this the first leg after installing would be
    /// the first one the wrist ever saw.
    public func sessionWatchStateDidChange(_ session: WCSession) {
        flush()
    }

    // Required on iOS only, and only because a phone can be handed to a second watch. Neither is a
    // moment to keep showing the first watch's leg, so the session is simply activated again.
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
