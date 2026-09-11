import AuthenticationServices
import CryptoKit
import Foundation
import ThroNet

// The account, as the app sees it: PD-030's sign-in (Apple and Google first, a passkey as the
// fallback) and THRØ's own session. The store is the only thing the screens talk to; the platform
// services behind it are injected, so every state below is reached in a test with no device.

/// The platform ceremonies. The live implementation talks to AuthenticationServices; a test's does not.
public protocol SignInServices: Sendable {
    /// Sign in with Apple: the identity token, or nil when the person cancelled.
    func appleIdentityToken(nonce: String) async throws -> String?
    /// Sign in with Google through a system web session: the ID token, or nil when cancelled.
    func googleIdentityToken(configuration: ServerConfiguration, transport: Transport, nonce: String) async throws -> String?
    /// A passkey is created for the relying party; nil when the person cancelled.
    func createPasskey(_ options: PasskeyCreationOptions) async throws -> PasskeyRegistration?
    /// A passkey signs a challenge; nil when the person cancelled.
    func usePasskey(_ options: PasskeyRequestOptions) async throws -> PasskeyAssertion?
}

@MainActor
public final class AccountStore: ObservableObject {
    public enum State: Equatable {
        case signedOut
        /// Something is in flight; the text says what, so a slow network is not a frozen screen.
        case busy(String)
        case signedIn(Profile)
        /// The last attempt failed; the person is still whatever they were before it.
        case failed(String, wasSignedIn: Bool)
    }

    @Published public private(set) var state: State = .signedOut
    public let api: ThroAPI
    public let configuration: ServerConfiguration
    private let services: SignInServices
    private let transport: Transport

    public init(api: ThroAPI, configuration: ServerConfiguration, services: SignInServices, transport: Transport = URLSessionTransport()) {
        self.api = api
        self.configuration = configuration
        self.services = services
        self.transport = transport
    }

    public var profile: Profile? { if case .signedIn(let p) = state { return p } else { return nil } }
    public var isSignedIn: Bool { profile != nil }

    /// On launch: a held session is asked who it is; one the server no longer honours is dropped.
    public func start() async {
        guard await api.isSignedIn else { state = .signedOut; return }
        state = .busy("Checking your sign-in")
        await load()
    }

    public func signInWithApple() async {
        await ceremony("Signing in with Apple") {
            // The RAW nonce goes to the server. Apple's token carries its SHA-256, and the server
            // accepts either the value or its hash — so one field serves both providers.
            let nonce = Nonce.fresh()
            guard let token = try await services.appleIdentityToken(nonce: nonce) else { return false }
            _ = try await api.signIn(.apple, idToken: token, nonce: nonce)
            return true
        }
    }

    public func signInWithGoogle() async {
        guard configuration.googleClientID != nil else {
            state = .failed("Sign in with Google is not set up in this build yet.", wasSignedIn: isSignedIn); return
        }
        await ceremony("Signing in with Google") {
            let nonce = Nonce.fresh()
            guard let token = try await services.googleIdentityToken(configuration: configuration, transport: transport, nonce: nonce) else { return false }
            _ = try await api.signIn(.google, idToken: token, nonce: nonce)
            return true
        }
    }

    /// Signs in with an existing passkey (no account held), or adds one to the account (signed in).
    public func usePasskey() async {
        if isSignedIn {
            await ceremony("Adding a passkey") {
                let options = try await api.passkeyCreationOptions()
                guard let made = try await services.createPasskey(options) else { return false }
                _ = try await api.registerPasskey(options, made)
                return true
            }
        } else {
            await ceremony("Signing in with a passkey") {
                let options = try await api.passkeyRequestOptions()
                guard let signed = try await services.usePasskey(options) else { return false }
                _ = try await api.signInWithPasskey(options, signed)
                return true
            }
        }
    }

    /// A first account made with a passkey alone — the path for someone with neither Apple nor Google.
    public func createAccountWithPasskey() async {
        await ceremony("Creating your account") {
            let options = try await api.passkeyCreationOptions()
            guard let made = try await services.createPasskey(options) else { return false }
            _ = try await api.registerPasskey(options, made)
            return true
        }
    }

    public func setDisplayName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let before = state
        state = .busy("Saving your name")
        do { state = .signedIn(try await api.setDisplayName(trimmed)) } catch { state = failure(error, before: before) }
    }

    public func signOut() async {
        state = .busy("Signing out")
        await api.signOut()
        state = .signedOut
        friends = nil; invite = nil; friendsNote = nil
    }

    /// Erase the account (V031). Signed out here whatever the server says, for the reason
    /// `ThroAPI.eraseAccount` gives: a phone still acting signed in to an account that has gone is
    /// worse than a failure the person can see.
    ///
    /// Returns the sentence to show when it did not work, and nil when it did.
    @discardableResult
    public func eraseAccount() async -> String? {
        state = .busy("Erasing your account")
        defer { friends = nil; invite = nil; friendsNote = nil }
        do {
            _ = try await api.eraseAccount()
            state = .signedOut
            return nil
        } catch {
            state = .signedOut
            return SignInProblem.words(error)
        }
    }

    // MARK: friends (V028)

    /// Nil until read; empty when read and none.
    @Published public private(set) var friends: [Friend]?
    @Published public private(set) var invite: FriendInvite?
    /// The last thing the server said about friends — a refusal's own sentence, or an error.
    @Published public private(set) var friendsNote: String?

    public func declareAdult() async {
        let before = state
        state = .busy("Saving")
        do { state = .signedIn(try await api.declareAge(adult: true)) } catch { state = failure(error, before: before) }
    }

    public func loadFriends() async {
        do { friends = try await api.friends(); friendsNote = nil } catch { friendsNote = ThroAPI.refusal(error) ?? "Your friends could not be read just now." }
    }

    public func makeInvite() async {
        do { invite = try await api.inviteFriend(); friendsNote = nil } catch { friendsNote = ThroAPI.refusal(error) ?? "A code could not be made just now." }
    }

    /// True when the code was accepted; the note says why when it was not.
    @discardableResult
    public func acceptCode(_ code: String) async -> Bool {
        do {
            let friend = try await api.acceptFriend(code: code)
            friends = [friend] + (friends ?? []).filter { $0.accountId != friend.accountId }
            friendsNote = nil
            return true
        } catch { friendsNote = ThroAPI.refusal(error) ?? "The code could not be used just now."; return false }
    }

    public func removeFriend(_ friend: Friend) async {
        do { try await api.removeFriend(friend.accountId); friends = (friends ?? []).filter { $0.accountId != friend.accountId } }
        catch { friendsNote = ThroAPI.refusal(error) ?? "That could not be done just now." }
    }

    public func dismissFailure() {
        if case .failed(_, let was) = state { state = was ? .busy("Checking your sign-in") : .signedOut; if was { Task { await load() } } }
    }

    // MARK: -

    /// One ceremony: busy while it runs, the profile when it ends, the state it started from when
    /// the person cancels, and words when it fails. A cancel is not a failure and is not shown as one.
    private func ceremony(_ what: String, _ run: () async throws -> Bool) async {
        let before = state
        state = .busy(what)
        do {
            if try await run() { await load() } else { state = before }
        } catch {
            state = failure(error, before: before)
        }
    }

    private func load() async {
        do { state = .signedIn(try await api.me()) } catch APIError.signedOut { state = .signedOut } catch { state = failure(error, before: .signedOut) }
    }

    private func failure(_ error: Error, before: State) -> State {
        let was: Bool = { if case .signedIn = before { return true } else { return false } }()
        if let e = error as? ASAuthorizationError, e.code == .canceled { return before }
        if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return before }
        return .failed(SignInProblem.words(error), wasSignedIn: was)
    }
}

/// What a person is told when a way in does not work.
///
/// **Never a domain and a code.** `error.localizedDescription` put
/// *"The operation couldn't be completed. (com.apple.AuthenticationServices.AuthorizationError
/// error 1000.)"* on the founder's phone, which names no cause, offers no action, and is the
/// app admitting it has not thought about the case. Every sentence here says what happened and,
/// where there is one, the thing to go and do.
public enum SignInProblem {
    public static func words(_ error: Error) -> String {
        // The server's own sentence is already the best one available: it knows exactly what it
        // refused and why, and it is written for a person.
        if let e = error as? APIError { return e.message }

        let raw = error.localizedDescription
        // A passkey on a domain the phone could not tie to this app. The message names the domain,
        // which is right, and then stops — so it gets the part that says what still works.
        if raw.contains("is not associated with domain") {
            return "This phone could not confirm that THRØ owns its sign-in domain, so a passkey "
                + "cannot be used yet. Continue with Apple or Google instead — both work without it."
        }
        if let e = error as? ASAuthorizationError {
            switch e.code {
            case .unknown:
                // 1000. Apple does not say why; being signed out of the Apple Account on the phone
                // is far and away the most common reason, so that is what to check first.
                return "Apple could not finish the sign-in. Check you are signed in to your Apple "
                    + "Account in iPhone Settings, then try again."
            case .invalidResponse, .notHandled:
                return "Apple sent back a sign-in this build could not read. Try again."
            case .failed:
                return "Apple refused the sign-in. Try again, or use Google instead."
            case .notInteractive:
                return "The sign-in could not be shown. Bring THRØ to the front and try again."
            default:
                return "Sign in with Apple did not finish. Try again, or use Google instead."
            }
        }
        if error is ASWebAuthenticationSessionError {
            return "The sign-in window closed before it finished. Try again."
        }
        // A network that was not there. URLError's own sentences are decent English; the codes are
        // the ones a phone in a pub actually hits.
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "This phone is not online, so THRØ could not reach the server. "
                    + "You can still score a match without signing in."
            case .timedOut:
                return "THRØ did not answer in time. The free server sleeps; try once more."
            default: return e.localizedDescription
            }
        }
        return raw
    }
}

enum Nonce {
    static func fresh() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Base64URL.encode(Data(bytes))
    }
    /// Apple wants the SHA-256 of the nonce in the request and returns the nonce in the token.
    static func hashed(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - the live services

/// The real ceremonies. Each one is a continuation around an AuthenticationServices controller,
/// and each answers nil for a cancel so the store can put the screen back where it was.
public final class LiveSignInServices: NSObject, SignInServices, @unchecked Sendable {
    public override init() { super.init() }

    public func appleIdentityToken(nonce: String) async throws -> String? {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        request.nonce = Nonce.hashed(nonce)
        let credential = try await perform([request])
        guard let apple = credential as? ASAuthorizationAppleIDCredential, let token = apple.identityToken else { return nil }
        return String(decoding: token, as: UTF8.self)
    }

    public func googleIdentityToken(configuration: ServerConfiguration, transport: Transport, nonce: String) async throws -> String? {
        let pkce = PKCE()
        guard let url = GoogleOAuth.authorizationURL(configuration: configuration, pkce: pkce, nonce: nonce),
              let scheme = configuration.googleRedirectScheme else { throw APIError.malformed("no Google client id") }
        let callback: URL? = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { continuation.resume(returning: nil); return }
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = Anchor.shared
            session.prefersEphemeralWebBrowserSession = false
            DispatchQueue.main.async { session.start() }
        }
        guard let callback, let code = GoogleOAuth.code(from: callback) else { return nil }
        return try await GoogleOAuth.exchange(code: code, configuration: configuration, pkce: pkce, transport: transport)
    }

    public func createPasskey(_ options: PasskeyCreationOptions) async throws -> PasskeyRegistration? {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingParty)
        let request = provider.createCredentialRegistrationRequest(challenge: options.challenge, name: options.userName, userID: options.userID)
        request.userVerificationPreference = .required
        guard let made = try await perform([request]) as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = made.rawAttestationObject else { return nil }
        return PasskeyRegistration(credentialID: made.credentialID, clientDataJSON: made.rawClientDataJSON, attestationObject: attestation)
    }

    public func usePasskey(_ options: PasskeyRequestOptions) async throws -> PasskeyAssertion? {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        request.userVerificationPreference = .required
        guard let signed = try await perform([request]) as? ASAuthorizationPlatformPublicKeyCredentialAssertion else { return nil }
        return PasskeyAssertion(credentialID: signed.credentialID, clientDataJSON: signed.rawClientDataJSON,
                                authenticatorData: signed.rawAuthenticatorData, signature: signed.signature)
    }

    /// Runs one controller and hands back its credential; nil for a cancel.
    private func perform(_ requests: [ASAuthorizationRequest]) async throws -> ASAuthorizationCredential? {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: requests)
            let delegate = Delegate(continuation)
            controller.delegate = delegate
            controller.presentationContextProvider = Anchor.shared
            Delegate.inFlight = delegate
            DispatchQueue.main.async { controller.performRequests() }
        }
    }

    private final class Delegate: NSObject, ASAuthorizationControllerDelegate {
        nonisolated(unsafe) static var inFlight: Delegate?
        private var continuation: CheckedContinuation<ASAuthorizationCredential?, Error>?
        init(_ c: CheckedContinuation<ASAuthorizationCredential?, Error>) { continuation = c }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            continuation?.resume(returning: authorization.credential); continuation = nil; Delegate.inFlight = nil
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            if let e = error as? ASAuthorizationError, e.code == .canceled { continuation?.resume(returning: nil) } else { continuation?.resume(throwing: error) }
            continuation = nil; Delegate.inFlight = nil
        }
    }

    private final class Anchor: NSObject, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
        static let shared = Anchor()
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { Anchor.window() }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { Anchor.window() }
        static func window() -> ASPresentationAnchor {
            #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            if let any = scenes.flatMap(\.windows).first { return any }
            #endif
            return ASPresentationAnchor()
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif

/// The app's own wiring: configuration from Info.plist, the keychain store, the journal's device id.
public enum ThroServer {
    public static let deviceIdKey = "thro.api.deviceId"

    /// The device id the API knows this phone by. The journal's id is reused when it is a UUID,
    /// so evidence and commands from this phone carry one identity.
    public static func deviceId(journalDeviceId: String?, defaults: UserDefaults = .standard) -> UUID {
        if let j = journalDeviceId, let u = UUID(uuidString: j) { return u }
        if let s = defaults.string(forKey: deviceIdKey), let u = UUID(uuidString: s) { return u }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: deviceIdKey)
        return fresh
    }

    /// Nil when the build names no server, in which case the account screen says so.
    @MainActor public static func account(journalDeviceId: String?) -> AccountStore? {
        guard let configuration = ServerConfiguration.fromInfoPlist() else { return nil }
        let api = ThroAPI(configuration: configuration, deviceId: deviceId(journalDeviceId: journalDeviceId), store: KeychainSessionStore())
        return AccountStore(api: api, configuration: configuration, services: LiveSignInServices())
    }
}
