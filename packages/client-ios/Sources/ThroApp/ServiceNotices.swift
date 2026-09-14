import Foundation
import ThroNet

/// The notice about people's information, as Home shows it (PD-094).
///
/// **Asked at launch and on every return to the front, and at most once a minute.** A phone flicked between apps
/// should not ask a web site the same question twenty times over, and a notice published this morning should be
/// on Home the next time anybody opens THRØ, not the next time they relaunch it.
///
/// **A notice already read stays up when the site cannot be reached**, and comes down only when the site says there
/// is nothing — an inactive file, or no file. Losing signal in a pub is not the notice being withdrawn.
@MainActor
public final class ServiceNotices: ObservableObject {
    /// The id of the notice somebody put away. One id rather than a list: only the current notice can be on screen,
    /// and a new id is exactly what brings a notice back.
    public static let putAwayKey = "app.thro.notice.putAway"
    /// The shortest gap between two looks.
    public static let interval: TimeInterval = 60

    @Published public private(set) var current: ServiceNotice?

    private let web: URL?
    private let transport: Transport
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastAsked: Date?

    public init(web: URL? = ServiceNotice.webSite(),
                transport: Transport = ServiceNotice.anonymousTransport(),
                defaults: UserDefaults = .standard,
                now: @escaping () -> Date = { Date() }) {
        self.web = web
        self.transport = transport
        self.defaults = defaults
        self.now = now
    }

    /// The notice to put on Home: the current one, unless it is the one somebody put away.
    public var showing: ServiceNotice? {
        guard let current, defaults.string(forKey: Self.putAwayKey) != current.id else { return nil }
        return current
    }

    /// The full notice on the web site, for an adult or for under-18s.
    public func page(underEighteen: Bool) -> URL? {
        web.map { ServiceNotice.page(on: $0, underEighteen: underEighteen) }
    }

    /// Asks the web site, unless it was asked less than `interval` ago. A build that names no web site asks nothing.
    public func refresh() async {
        guard let web else { return }
        let moment = now()
        if let lastAsked, moment.timeIntervalSince(lastAsked) < Self.interval { return }
        lastAsked = moment
        switch await ServiceNotice.ask(web, transport: transport) {
        case .notice(let notice): current = notice
        case .nothingLive: current = nil
        case .unknown: break
        }
    }

    /// Takes this notice off Home. An updated notice carries a new id and shows again.
    public func putAway() {
        guard let current else { return }
        defaults.set(current.id, forKey: Self.putAwayKey)
        objectWillChange.send()
    }
}
