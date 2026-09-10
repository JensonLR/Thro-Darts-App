import CryptoKit
import Foundation

// ThroNet — the phone's side of the wire. Sign-in, the session THRØ issues, and the reads and
// commands the server offers. Nothing in the scoring path depends on this module (Package.swift
// says so and `tools/check_absence_claims.py` holds it): the journal writes the phone's own truth
// without it, and this module carries that truth nowhere — the only things it sends are a sign-in
// and, later, the commands a person explicitly makes.

/// Where the server is and how a sign-in provider knows this app.
public struct ServerConfiguration: Sendable, Equatable {
    public let baseURL: URL
    /// The Google OAuth iOS client id, or nil when this build has none — the button then says so.
    public let googleClientID: String?

    public init(baseURL: URL, googleClientID: String? = nil) {
        self.baseURL = baseURL
        self.googleClientID = googleClientID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    /// The WebAuthn relying party is the API's host; passkeys are bound to it.
    public var relyingParty: String { baseURL.host ?? "" }

    /// Google requires an iOS client's redirect to use its reversed client id as the URL scheme.
    public var googleRedirectScheme: String? {
        guard let id = googleClientID, id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return "com.googleusercontent.apps." + String(id.dropLast(".apps.googleusercontent.com".count))
    }

    /// Read from the app's Info.plist: `THROAPIBaseURL` and `THROGoogleClientID`.
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> ServerConfiguration? {
        guard let raw = bundle.object(forInfoDictionaryKey: "THROAPIBaseURL") as? String,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil else { return nil }
        return ServerConfiguration(baseURL: url, googleClientID: bundle.object(forInfoDictionaryKey: "THROGoogleClientID") as? String)
    }
}

/// THRØ's own session: a short-lived access token and a refresh token that rotates.
public struct Session: Codable, Sendable, Equatable {
    public let accountId: UUID
    public let playerId: UUID?
    public let accessToken: String
    public let refreshToken: String
    public let accessExpiresAt: Date
    /// True when this sign-in created the account.
    public let created: Bool

    public init(accountId: UUID, playerId: UUID?, accessToken: String, refreshToken: String, accessExpiresAt: Date, created: Bool) {
        self.accountId = accountId; self.playerId = playerId; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.accessExpiresAt = accessExpiresAt; self.created = created
    }
}

public struct Profile: Decodable, Sendable, Equatable {
    public let accountId: UUID?
    public let playerId: UUID?
    public let displayName: String?
    /// False while the name is the placeholder the server gives a new account.
    public let named: Bool
    public let ageBand: String
    /// How many ways into the account exist (PD-032): one is fragile, and the screen says so.
    public let credentials: Int?

    public init(accountId: UUID?, playerId: UUID?, displayName: String?, named: Bool, ageBand: String, credentials: Int?) {
        self.accountId = accountId; self.playerId = playerId; self.displayName = displayName
        self.named = named; self.ageBand = ageBand; self.credentials = credentials
    }
}

public struct InboxItem: Decodable, Sendable, Equatable, Identifiable {
    public let taskId: UUID
    public let kind: String
    public let reason: String
    public let dueAt: Date?
    public let state: String
    public var id: UUID { taskId }
}

/// A league as its public front shows it: seasons newest first, each with its divisions and teams,
/// each team with its home venue where one is known and the BASIS that venue was connected on.
/// Dates arrive as `yyyy-MM-dd` strings and stay strings: they are calendar days, not instants.
public struct PublicLeague: Decodable, Sendable, Equatable, Identifiable {
    public struct Source: Decodable, Sendable, Equatable {
        public let source: String
        public let url: String?
        public let retrievedOn: String
    }
    public struct Venue: Decodable, Sendable, Equatable {
        public let venueId: UUID
        public let name: String
        public let locality: String?
        public let postcode: String?
        public let latitude: Double?
        public let longitude: Double?
        /// "stated by the source", or "inferred from the team's name" — shown, never hidden.
        public let basis: String?
    }
    public struct Team: Decodable, Sendable, Equatable, Identifiable {
        public let teamId: UUID
        public let name: String
        public let venue: Venue?
        public var id: UUID { teamId }
    }
    public struct Division: Decodable, Sendable, Equatable, Identifiable {
        public let divisionId: UUID
        public let name: String
        public let ordinal: Int
        public let teams: [Team]
        public var id: UUID { divisionId }
    }
    public struct Season: Decodable, Sendable, Equatable, Identifiable {
        public let leagueSeasonId: UUID
        public let label: String
        public let startsOn: String
        public let endsOn: String
        public let current: Bool
        public let divisions: [Division]
        public var id: UUID { leagueSeasonId }
    }
    public let leagueId: UUID
    public let name: String
    public let shortName: String?
    public let playsOn: String?
    public let locality: String?
    public let sources: [Source]
    public let seasons: [Season]
    public var id: UUID { leagueId }

    /// The season to show: the one running today, else the newest.
    public var shownSeason: Season? { seasons.first(where: \.current) ?? seasons.first }
}

/// An open-entry event as its public notice shows it: what, where, when, how many places. Who is
/// in it, and whether you may be, is the signed-in discovery model's business.
public struct PublicEvent: Decodable, Sendable, Equatable, Identifiable {
    public let eventId: UUID
    public let name: String
    public let tournament: String?
    public let venue: PublicLeague.Venue?
    public let venueLabel: String?
    public let startsAt: Date
    public let entriesCloseAt: Date?
    public let entrantKind: String
    public let capacity: Int?
    public var id: UUID { eventId }
}

public struct DiscoveryCard: Decodable, Sendable, Equatable, Identifiable {
    public let eventId: UUID
    public let name: String
    public let tournament: String?
    public let venue: String?
    public let locality: String?
    public let startsAt: Date
    public let entriesCloseAt: Date?
    public let entrantKind: String
    public let access: String
    public let capacity: Int?
    public let spotsRemaining: Int?
    public let entered: Bool
    public let qualifies: Bool
    public let series: [String]
    /// Every card says why it is there; the screen shows these and invents nothing.
    public let reasons: [String]
    public var id: UUID { eventId }
}

public enum Provider: String, Sendable { case apple, google }

public enum APIError: Error, Equatable, Sendable {
    /// The server answered with a status this call does not accept, and what it said.
    case status(Int, String)
    /// No session, or a session the server no longer honours; the person signs in again.
    case signedOut
    /// The request never got an answer.
    case unreachable(String)
    /// An answer this build cannot read.
    case malformed(String)

    /// Words for the screen. Never a status code on its own.
    public var message: String {
        switch self {
        case .status(let code, let body):
            if let why = APIError.errorField(body) { return why }
            return code == 429 ? "Too many attempts. Wait a minute and try again." : "The server answered \(code)."
        case .signedOut: return "You are signed out. Sign in again to continue."
        case .unreachable(let why): return "THRØ could not be reached: \(why)"
        case .malformed(let why): return "THRØ answered in a way this build cannot read: \(why)"
        }
    }

    static func errorField(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["error"] as? String) ?? (obj["why"] as? String)
    }
}

/// How bytes reach the server. `URLSession` in the app; a scripted fake in tests.
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable("not an HTTP response") }
        return (data, http)
    }
}

/// The result of a passkey registration ceremony, as the platform hands it back.
public struct PasskeyRegistration: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let attestationObject: Data
    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID; self.clientDataJSON = clientDataJSON; self.attestationObject = attestationObject
    }
}

public struct PasskeyAssertion: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data) {
        self.credentialID = credentialID; self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData; self.signature = signature
    }
}

/// What the server asks the platform to do before a passkey is created.
public struct PasskeyCreationOptions: Sendable, Equatable {
    public let challengeId: String
    public let challenge: Data
    public let relyingParty: String
    public let userID: Data
    public let userName: String
}

public struct PasskeyRequestOptions: Sendable, Equatable {
    public let challengeId: String
    public let challenge: Data
    public let relyingParty: String
}

/// The client. One per app; holds the session and refreshes it behind every authorised call.
public actor ThroAPI {
    public let configuration: ServerConfiguration
    public let deviceId: UUID
    private let store: SessionStore
    private let transport: Transport
    private let now: @Sendable () -> Date
    public private(set) var session: Session?

    public init(configuration: ServerConfiguration, deviceId: UUID, store: SessionStore,
                transport: Transport = URLSessionTransport(), now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.deviceId = deviceId
        self.store = store
        self.transport = transport
        self.now = now
        self.session = store.load()
    }

    public var isSignedIn: Bool { session != nil }

    // MARK: sign-in

    /// A provider's ID token becomes THRØ's session. With a session already held, an unheld
    /// subject is added to that account instead (PD-032: a second way in).
    public func signIn(_ provider: Provider, idToken: String) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: ["idToken": idToken, "deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/\(provider.rawValue)", body: body, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try adopt(data)
    }

    /// Revokes the session's family on the server and forgets it here whatever the server says:
    /// a sign-out that could fail would leave a person holding a token they asked to drop.
    public func signOut() async {
        if let s = session {
            _ = try? await send("POST", "/v1/auth/logout", body: Data("{}".utf8), bearer: s.accessToken)
        }
        session = nil
        store.clear()
    }

    // MARK: passkeys

    public func passkeyCreationOptions() async throws -> PasskeyCreationOptions {
        let body = try JSONSerialization.data(withJSONObject: ["deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/passkey/register/options", body: body, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeId = obj["challengeId"] as? String,
              let pk = obj["publicKey"] as? [String: Any],
              let challenge = (pk["challenge"] as? String).flatMap(Base64URL.decode),
              let rp = (pk["rp"] as? [String: Any])?["id"] as? String,
              let user = pk["user"] as? [String: Any],
              let userID = (user["id"] as? String).flatMap(Base64URL.decode),
              let userName = user["name"] as? String
        else { throw APIError.malformed("passkey creation options") }
        return PasskeyCreationOptions(challengeId: challengeId, challenge: challenge, relyingParty: rp, userID: userID, userName: userName)
    }

    public func registerPasskey(_ options: PasskeyCreationOptions, _ result: PasskeyRegistration) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: [
            "challengeId": options.challengeId, "deviceId": deviceId.uuidString.lowercased(),
            "credentialId": Base64URL.encode(result.credentialID),
            "clientDataJSON": Base64URL.encode(result.clientDataJSON),
            "attestationObject": Base64URL.encode(result.attestationObject),
        ])
        let (data, http) = try await send("POST", "/v1/auth/passkey/register", body: body, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try adopt(data)
    }

    public func passkeyRequestOptions() async throws -> PasskeyRequestOptions {
        let body = try JSONSerialization.data(withJSONObject: ["deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/passkey/options", body: body, bearer: nil)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeId = obj["challengeId"] as? String,
              let pk = obj["publicKey"] as? [String: Any],
              let challenge = (pk["challenge"] as? String).flatMap(Base64URL.decode),
              let rp = pk["rpId"] as? String
        else { throw APIError.malformed("passkey request options") }
        return PasskeyRequestOptions(challengeId: challengeId, challenge: challenge, relyingParty: rp)
    }

    public func signInWithPasskey(_ options: PasskeyRequestOptions, _ result: PasskeyAssertion) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: [
            "challengeId": options.challengeId, "deviceId": deviceId.uuidString.lowercased(),
            "credentialId": Base64URL.encode(result.credentialID),
            "clientDataJSON": Base64URL.encode(result.clientDataJSON),
            "authenticatorData": Base64URL.encode(result.authenticatorData),
            "signature": Base64URL.encode(result.signature),
        ])
        let (data, http) = try await send("POST", "/v1/auth/passkey", body: body, bearer: nil)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try adopt(data)
    }

    // MARK: the signed-in person

    public func me() async throws -> Profile { try decode(await authorised("GET", "/v1/me")) }

    public func setDisplayName(_ name: String) async throws -> Profile {
        let body = try JSONSerialization.data(withJSONObject: ["displayName": name])
        return try decode(await authorised("PUT", "/v1/me/profile", body: body))
    }

    public func inbox() async throws -> [String: [InboxItem]] {
        struct Envelope: Decodable { let sections: [String: [InboxItem]] }
        return try (decode(await authorised("GET", "/v1/me/inbox")) as Envelope).sections
    }

    public func discovery(locality: String? = nil) async throws -> [String: [DiscoveryCard]] {
        struct Envelope: Decodable { let sections: [String: [DiscoveryCard]] }
        var path = "/v1/me/discovery"
        if let locality, let q = locality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { path += "?locality=\(q)" }
        return try (decode(await authorised("GET", path)) as Envelope).sections
    }

    /// The leagues' public front (PD-033): no session needed, so a phone that has never signed in
    /// can still see who plays where. A locality narrows it to leagues in that town.
    public func leagues(locality: String? = nil) async throws -> [PublicLeague] {
        struct Envelope: Decodable { let leagues: [PublicLeague] }
        var path = "/v1/leagues"
        if let locality, let q = locality.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { path += "?locality=\(q)" }
        let (data, http) = try await send("GET", path, bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try (decode(data) as Envelope).leagues
    }

    /// Open-entry events that have not started (the notice on the pub door). No session needed.
    public func events() async throws -> [PublicEvent] {
        struct Envelope: Decodable { let events: [PublicEvent] }
        let (data, http) = try await send("GET", "/v1/events", bearer: session?.accessToken)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return try (decode(data) as Envelope).events
    }

    // MARK: plumbing

    /// An authorised call: bearer, one refresh on a 401, and a session that stops being honoured
    /// becomes `.signedOut` rather than a loop.
    private func authorised(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let current = session else { throw APIError.signedOut }
        var (data, http) = try await send(method, path, body: body, bearer: current.accessToken)
        if http.statusCode == 401 {
            try await refresh()
            guard let renewed = session else { throw APIError.signedOut }
            (data, http) = try await send(method, path, body: body, bearer: renewed.accessToken)
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return data
    }

    /// Rotates the refresh token. A refusal means the family is gone — reused, expired, or
    /// revoked — and the session is dropped so the person is told rather than retried.
    private func refresh() async throws {
        guard let current = session else { throw APIError.signedOut }
        let body = try JSONSerialization.data(withJSONObject: ["refreshToken": current.refreshToken, "deviceId": deviceId.uuidString.lowercased()])
        let (data, http) = try await send("POST", "/v1/auth/refresh", body: body, bearer: nil)
        guard http.statusCode == 200 else {
            session = nil
            store.clear()
            throw APIError.signedOut
        }
        _ = try adopt(data)
    }

    private func adopt(_ data: Data) throws -> Session {
        let s: Session = try decode(data)
        session = s
        store.save(s)
        return s
    }

    private func send(_ method: String, _ path: String, body: Data? = nil, bearer: String?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else { throw APIError.malformed("path \(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId.uuidString.lowercased(), forHTTPHeaderField: "X-Thro-Device")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        } else if method != "GET" {
            request.httpBody = Data()
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        do {
            return try await transport.send(request)
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.unreachable(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try Wire.decoder.decode(T.self, from: data) } catch { throw APIError.malformed(String(describing: error)) }
    }
}

/// The wire's conventions: base64url without padding, and ISO-8601 instants with or without fractions.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func decode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

public enum Wire {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter(); withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO-8601 instant: \(s)"))
        }
        return d
    }()
}

/// PKCE for the Google flow: the verifier stays on the phone, its hash goes to the browser.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        self.init(verifierBytes: Data(bytes))
    }
    init(verifierBytes: Data) {
        verifier = Base64URL.encode(verifierBytes)
        challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// Google's authorization-code flow for an iOS client, which has no secret: the code is exchanged
/// for an ID token straight from the phone, with the PKCE verifier proving it is the same phone.
public enum GoogleOAuth {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public static func redirectURI(for configuration: ServerConfiguration) -> String? {
        configuration.googleRedirectScheme.map { "\($0):/oauth2redirect" }
    }

    public static func authorizationURL(configuration: ServerConfiguration, pkce: PKCE, nonce: String) -> URL? {
        guard let clientID = configuration.googleClientID, let redirect = redirectURI(for: configuration) else { return nil }
        var c = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: pkce.challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "nonce", value: nonce),
        ]
        return c.url
    }

    /// The `code` from the callback URL, or nil when Google sent an error instead.
    public static func code(from callback: URL) -> String? {
        URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
    }

    public static func exchange(code: String, configuration: ServerConfiguration, pkce: PKCE, transport: Transport) async throws -> String {
        guard let clientID = configuration.googleClientID, let redirect = redirectURI(for: configuration) else { throw APIError.malformed("no Google client id") }
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["code": code, "client_id": clientID, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": pkce.verifier]
        // Form encoding leaves the unreserved characters alone, so a base64url verifier travels as it is.
        var unreserved = CharacterSet.alphanumerics; unreserved.insert(charactersIn: "-._~")
        request.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }.joined(separator: "&").utf8)
        let (data, http) = try await transport.send(request)
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, String(decoding: data, as: UTF8.self)) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = obj["id_token"] as? String else {
            throw APIError.malformed("Google's token answer carried no id_token")
        }
        return token
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
