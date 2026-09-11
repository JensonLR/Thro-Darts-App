#if DEBUG
import Foundation
import ThroNet

/// A signed-in account for screenshots, and for nothing else.
///
/// **Why it exists.** The simulator cannot sign in to anything real, so every screen that is only
/// shown to a signed-in person — the profile, friends, the delete screen — could be seen on the
/// founder's phone and nowhere else, and was being designed blind. Launched with
/// `-ThroScreenshotAccount`, a Debug build stands up an account store over a transport that answers
/// from memory. No request leaves the phone and nothing is stored; a Release build does not contain
/// this file at all.
///
///     xcrun simctl launch <device> app.thro.darts -ThroScreenshotAccount adult
///
/// The value picks who is signed in: `adult` (named, 18 or over, two ways in), `new` (no name, age
/// not said, one way in), or `failing` (every change is refused, to see the failure states).
enum ScreenshotAccount {
    static let argument = "-ThroScreenshotAccount"

    @MainActor static func storeIfAsked(arguments: [String] = ProcessInfo.processInfo.arguments) -> AccountStore? {
        guard let i = arguments.firstIndex(of: argument) else { return nil }
        let who = arguments.indices.contains(i + 1) ? arguments[i + 1] : "adult"
        let stage = Stage(who)
        let configuration = ServerConfiguration(baseURL: URL(string: "https://screenshots.invalid")!,
                                                googleClientID: "screenshots.apps.googleusercontent.com")
        // Placeholders, not credentials: nothing here is sent anywhere, because `Stage` is the only
        // transport this store has and it answers from memory.
        let session = Session(accountId: Stage.accountId, playerId: Stage.playerId, accessToken: "staged-not-a-token",
                              refreshToken: "staged-not-a-token", accessExpiresAt: .distantFuture, created: false)
        let api = ThroAPI(configuration: configuration, deviceId: UUID(), store: MemorySessionStore(session), transport: stage)
        return AccountStore(api: api, configuration: configuration, services: Refusing(), transport: stage)
    }

    /// The server, played from memory.
    final class Stage: Transport, @unchecked Sendable {
        static let accountId = UUID(uuidString: "5C4EE45E-0000-4000-8000-000000000001")!
        static let playerId = UUID(uuidString: "5C4EE45E-0000-4000-8000-000000000002")!
        private let lock = NSLock()
        private var name: String?
        private var band: String
        private let credentials: Int
        private let failing: Bool

        init(_ who: String) {
            failing = who == "failing"
            if who == "new" {
                name = nil; band = "unknown"; credentials = 1
            } else {
                name = "Jenson R."; band = "adult"; credentials = 2
            }
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let method = request.httpMethod ?? "GET"
            let path = request.url?.path ?? ""
            let (code, body) = lock.withLock { answer(method, path, request.httpBody) }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }

        private func answer(_ method: String, _ path: String, _ body: Data?) -> (Int, String) {
            switch (method, path) {
            case ("GET", "/v1/me"):
                return (200, profile)
            case ("PUT", "/v1/me/profile"):
                if failing { return (503, #"{"error":"THRØ could not save that just now. Nothing changed."}"#) }
                let sent = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                if let n = sent["displayName"] as? String { name = n }
                if let b = sent["ageBand"] as? String { band = b }
                return (200, profile)
            case ("DELETE", "/v1/me"):
                if failing { return (500, #"{"error":"the account could not be erased"}"#) }
                return (200, #"{"erased":true,"credentials":\#(credentials),"sessions":3,"devices":1,"friendships":1,"claims":1,"consents":1}"#)
            case ("GET", "/v1/friends"):
                return (200, #"{"friends":[{"accountId":"5c4ee45e-0000-4000-8000-00000000000a","displayName":"Ethan T.","since":"2026-09-10T19:00:00Z"}]}"#)
            case ("POST", "/v1/friends/invite"):
                return (200, #"{"code":"K7TQ2M4X","expiresAt":"2026-09-18T12:00:00Z"}"#)
            case ("POST", "/v1/auth/logout"):
                return (200, "{}")
            default:
                if path.hasPrefix("/v1/me/inbox") || path.contains("discovery") { return (200, #"{"sections":{}}"#) }
                return (404, #"{"error":"not staged for screenshots"}"#)
            }
        }

        private var profile: String {
            let n = name.map { "\"\($0)\"" } ?? "\"New player\""
            return #"{"accountId":"\#(Stage.accountId.uuidString.lowercased())","playerId":"\#(Stage.playerId.uuidString.lowercased())","displayName":\#(n),"named":\#(name != nil),"ageBand":"\#(band)","credentials":\#(credentials)}"#
        }
    }

    /// Ceremonies that never open anything: a screenshot has no Apple ID to sign in with.
    struct Refusing: SignInServices {
        func appleIdentityToken(nonce: String) async throws -> String? { nil }
        func googleIdentityToken(configuration: ServerConfiguration, transport: Transport, nonce: String) async throws -> String? { nil }
        func createPasskey(_ options: PasskeyCreationOptions) async throws -> PasskeyRegistration? { nil }
        func usePasskey(_ options: PasskeyRequestOptions) async throws -> PasskeyAssertion? { nil }
    }
}
#endif
