import Foundation

// A notice about people's information, read from THRØ's public web site (PD-094).
//
// **Why the web site and not the API.** UK GDPR Art 34 asks THRØ to tell people without undue delay when a breach
// is likely to put them at high risk, and THRØ holds no email address, no phone number and no push token — so the
// app is the only way to reach anybody. The day that is needed may be the day the API is switched off to contain
// the breach. The web is a static site that answers whatever the API is doing, so the notice lives there as one
// file, `notice.json`, and publishing it is an edit and a push.
//
// **The rules are the ones `apps/web/thro.js` and `tools/check_notice.py` apply to the same file**, and a test reads
// the committed file through this parser, so the three cannot quietly disagree.

public struct ServiceNotice: Equatable, Sendable {
    /// What one reader is shown on Home: a title and a summary. The full account is on the web page.
    public struct Words: Equatable, Sendable {
        public let title: String
        public let summary: String
        public init(title: String, summary: String) {
            self.title = title
            self.summary = summary
        }
    }

    /// What asking the web site found.
    public enum Answer: Equatable, Sendable {
        /// A readable, active notice.
        case notice(ServiceNotice)
        /// The site says there is nothing: the file is inactive, or it has been taken down.
        case nothingLive
        /// The site could not be asked, or answered with something this build cannot read. That says nothing either
        /// way, so a notice already on screen stays on it.
        case unknown
    }

    public let id: String
    public let published: Date
    public let adult: Words
    public let under18: Words

    public init(id: String, published: Date, adult: Words, under18: Words) {
        self.id = id
        self.published = published
        self.adult = adult
        self.under18 = under18
    }

    // MARK: - Reading the file

    private struct File: Decodable {
        struct Part: Decodable {
            let title: String?
            let summary: String?
            let body: [String]?
        }
        // Typed, so `"active": 1` is not true and `"format": true` is not 1 — the decoder refuses both.
        let format: Int
        let active: Bool
        let id: String?
        let published: String?
        let title: String?
        let summary: String?
        let body: [String]?
        let under18: Part?
    }

    /// Reads `notice.json`. Anything short of a readable, active notice is not a notice: half a breach notice is worse
    /// than none.
    public static func answer(from data: Data) -> Answer {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.format == 1 else { return .unknown }
        guard file.active else { return .nothingLive }
        guard let id = filled(file.id),
              let published = moment(file.published),
              let adult = words(title: file.title, summary: file.summary, body: file.body),
              let young = file.under18,
              let under18 = words(title: young.title, summary: young.summary, body: young.body)
        else { return .unknown }
        return .notice(ServiceNotice(id: id, published: published, adult: adult, under18: under18))
    }

    private static func filled(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// One reader's words, when all of them are there — the body too, though Home does not show it, because a card
    /// that sends somebody to an empty page has told them less than nothing.
    private static func words(title: String?, summary: String?, body: [String]?) -> Words? {
        guard let title = filled(title), let summary = filled(summary),
              let body, !body.isEmpty, body.allSatisfy({ filled($0) != nil }) else { return nil }
        return Words(title: title, summary: summary)
    }

    /// A date and a time with its zone, as `check_notice.py` insists — a bare date reads differently in every
    /// parser that meets it.
    private static func moment(_ text: String?) -> Date? {
        guard let text = filled(text) else { return nil }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    // MARK: - Who reads what

    /// The words for somebody of this age band, and whether they belong on the under-18 page. Under 18, an age nobody
    /// has said, and nobody signed in all get the under-18 words: unknown is not adult.
    public func forReader(ageBand: String?) -> (words: Words, underEighteen: Bool) {
        ageBand == "adult" ? (adult, false) : (under18, true)
    }

    /// The full notice on the web site.
    public static func page(on web: URL, underEighteen: Bool) -> URL {
        web.appendingPathComponent(underEighteen ? "notice-under-18.html" : "notice.html")
    }

    // MARK: - Asking

    /// The public web site, from `THROWebBaseURL`, which `tools/host.py` keeps with the other hosts. A Debug build
    /// may be pointed elsewhere, as `-ThroAPIBaseURL` is, so the card can be looked at against a local copy:
    ///
    ///     xcrun simctl launch <device> app.thro.darts -ThroWebBaseURL http://127.0.0.1:8787
    public static func webSite(_ bundle: Bundle = .main,
                               arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        var raw = bundle.object(forInfoDictionaryKey: "THROWebBaseURL") as? String
        #if DEBUG
        if let flag = arguments.firstIndex(of: "-ThroWebBaseURL"), arguments.indices.contains(flag + 1) {
            raw = arguments[flag + 1]
        }
        #endif
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil
        else { return nil }
        return url
    }

    /// The request for `notice.json`. **It says nothing about who is asking**: no device id, no account, no token,
    /// no cookie, and no copy kept from an earlier answer. A notice meant for everybody is not a reason to learn
    /// who read it.
    public static func request(on web: URL) -> URLRequest {
        var request = URLRequest(url: web.appendingPathComponent("notice.json"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        return request
    }

    /// Asks the web site. A file that has been taken down is nothing live; every other failure is unknown.
    public static func ask(_ web: URL, transport: Transport) async -> Answer {
        do {
            let (data, http) = try await transport.send(request(on: web))
            switch http.statusCode {
            case 200: return answer(from: data)
            case 404, 410: return .nothingLive
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    /// A transport that keeps nothing between requests — no cookies, no cache, no credentials.
    public static func anonymousTransport() -> Transport {
        URLSessionTransport(session: URLSession(configuration: .ephemeral))
    }
}
