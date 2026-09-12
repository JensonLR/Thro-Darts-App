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
        /// Signing in, or finding out who a held session is. The text says what, so a slow network
        /// is not a frozen screen. **Never used for a change to an account that is already signed
        /// in** — that is `working` — because every screen about a signed-in person is shown only
        /// while the state says `signedIn`, and a name being saved took the page off the screen.
        case busy(String)
        case signedIn(Profile)
        /// The last attempt failed. `wasSignedIn` is true when this phone still holds a session —
        /// signed in, just not confirmed — and false when nobody is signed in.
        case failed(String, wasSignedIn: Bool)
    }

    /// What asking for an erasure came to.
    public enum Erased: Equatable {
        /// Done, with what the server destroyed — which the screen says back, because a person who
        /// exercised a right is owed an account of what was done with it.
        case erased(ThroAPI.Erasure)
        /// Not done, and why, in words. The account is still there.
        case failed(String)
    }

    @Published public private(set) var state: State = .signedOut
    /// Something is being done to the account that is signed in: a name saving, a way in being
    /// added, an erasure. The state stays `signedIn` while it happens, so the page it was started
    /// from stays where it is and shows this instead of vanishing.
    ///
    /// **This is the bug that made Delete look like it did nothing.** An erasure set the state to
    /// busy, which took the profile page and the delete screen on it off the screen; the failure
    /// that followed was reported to a screen that no longer existed, and the person landed back on
    /// their profile with the account still there and no word about why.
    @Published public private(set) var working: String?
    /// The last thing that went wrong with an account that is still signed in, in words, for the
    /// page it happened on. Cleared by `dismissProblem()` or by the next thing that works.
    @Published public private(set) var problem: String?
    /// Whether this phone holds a session: signed in, whether or not THRØ has confirmed who yet.
    /// The welcome asks this rather than `isSignedIn`, so a phone that is offline at launch does not
    /// ask a signed-in person to sign in.
    @Published public private(set) var holdsSession = false
    /// Whether `start()` has finished looking. Until it has, `signedOut` means *not looked yet*
    /// rather than *not signed in* — and a screen that cannot tell those apart shows the sign-in
    /// board for a moment to somebody who is already signed in.
    @Published public private(set) var settled = false

    public let api: ThroAPI
    public let configuration: ServerConfiguration
    private let services: SignInServices
    private let transport: Transport
    private let cache: ProfileCache

    public init(api: ThroAPI, configuration: ServerConfiguration, services: SignInServices,
                transport: Transport = URLSessionTransport(), cache: ProfileCache = MemoryProfileCache()) {
        self.api = api
        self.configuration = configuration
        self.services = services
        self.transport = transport
        self.cache = cache
    }

    public var profile: Profile? { if case .signedIn(let p) = state { return p } else { return nil } }
    public var isSignedIn: Bool { profile != nil }

    /// On launch: who is signed in on this phone, and — behind it — whether THRØ still agrees.
    ///
    /// **Known at once when it can be.** A held session and the profile this phone was last given
    /// for that account are enough to say who somebody is, offline or while the free server wakes;
    /// the server is asked afterwards and can only correct it. Only a phone holding a session and
    /// no profile for it (the first launch of this build, or after a reinstall) has to wait, and
    /// the opening holds on its last frame while it does.
    public func start() async {
        guard let held = await api.session else {
            cache.clear()
            holdsSession = false
            state = .signedOut
            settled = true
            return
        }
        holdsSession = true
        switch state {
        case .signedIn:
            break  // already known this run; a second caller only refreshes it
        default:
            if let known = cache.load(), known.accountId == held.accountId {
                state = .signedIn(known)
            } else {
                state = .busy("Checking your sign-in")
            }
        }
        if isSignedIn { settled = true }
        await verify()
        settled = true
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
            let why = "Sign in with Google is not set up in this build yet."
            if isSignedIn { problem = why } else { state = .failed(why, wasSignedIn: false) }
            return
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
        await change("Saving your name") { try await self.api.setDisplayName(trimmed) }
    }

    public func declareAdult() async {
        await change("Saving") { try await self.api.declareAge(adult: true) }
    }

    public func signOut() async {
        working = "Signing out"
        await api.signOut()
        working = nil
        forget()
    }

    /// Erase the account (V031, V033).
    ///
    /// **The page that asked stays on screen for the answer.** The state is left `signedIn` while
    /// the server works — `working` says what is happening — so a failure is read on the delete
    /// screen that asked, and a success is too: that screen says what was destroyed, and only then
    /// does the person leave it.
    @discardableResult
    public func eraseAccount() async -> Erased {
        working = "Erasing your account"
        defer { working = nil }
        do {
            let gone = try await api.eraseAccount()
            forget()
            return .erased(gone)
        } catch {
            // A 401 that survived a refresh, or a 409 (already erased): the API has dropped the
            // session, so nobody is signed in any more whatever the page says. Anything else and the
            // account is still there, the person is still signed in, and the page says why.
            let still = await api.isSignedIn
            if !still { forget() }
            return .failed(SignInProblem.words(error))
        }
    }

    // MARK: friends (V028)

    /// Nil until read; empty when read and none.
    @Published public private(set) var friends: [Friend]?
    @Published public private(set) var invite: FriendInvite?
    /// The last thing the server said about friends — a refusal's own sentence, or an error.
    @Published public private(set) var friendsNote: String?

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

    /// Back from a failed sign-in: signed out again, or — when this phone still holds a session —
    /// another go at asking THRØ who it is.
    public func dismissFailure() {
        guard case .failed(_, let held) = state else { return }
        if held {
            state = .busy("Checking your sign-in")
            Task { await verify() }
        } else {
            state = .signedOut
        }
    }

    public func dismissProblem() { problem = nil }

    // MARK: -

    /// Asks THRØ who the held session is, and changes what the phone says only when THRØ answers.
    ///
    /// Offline-first: a network that is not there changes nothing that is already known. Only the
    /// server refusing the session signs the phone out.
    private func verify() async {
        do {
            adopt(try await api.me())
        } catch APIError.signedOut {
            forget()
        } catch {
            if isSignedIn { return }
            state = .failed(SignInProblem.words(error), wasSignedIn: true)
        }
    }

    /// One ceremony.
    ///
    /// **Signed out**, it is the whole screen: busy while it runs, the profile when it ends, the
    /// state it started from when the person cancels, and words when it fails. **Signed in**, it is
    /// a way in being added to the account on screen, so the page stays and `working` says what is
    /// happening. A cancel is not a failure and is not shown as one, either way.
    private func ceremony(_ what: String, _ run: () async throws -> Bool) async {
        if isSignedIn {
            working = what
            defer { working = nil }
            do {
                if try await run() { adopt(try await api.me()); problem = nil }
            } catch APIError.signedOut {
                forget()
            } catch {
                if !Self.cancelled(error) { problem = SignInProblem.words(error) }
            }
            return
        }
        let before = state
        state = .busy(what)
        do {
            guard try await run() else { state = before; return }
        } catch {
            state = Self.cancelled(error) ? before : .failed(SignInProblem.words(error), wasSignedIn: false)
            return
        }
        holdsSession = true
        await verify()
    }

    /// One change to the signed-in account: the page stays, `working` says what, and the new
    /// profile or the reason it failed arrives in place.
    private func change(_ what: String, _ run: () async throws -> Profile) async {
        working = what
        defer { working = nil }
        do {
            adopt(try await run())
            problem = nil
        } catch APIError.signedOut {
            forget()
        } catch {
            problem = SignInProblem.words(error)
        }
    }

    private func adopt(_ profile: Profile) {
        state = .signedIn(profile)
        holdsSession = true
        // A development principal has no account id, and a profile for nobody is not worth keeping.
        if profile.accountId != nil { cache.save(profile) }
    }

    /// Nobody is signed in on this phone any more: the session is gone, so everything that was
    /// about the person who held it goes with it.
    private func forget() {
        cache.clear()
        holdsSession = false
        state = .signedOut
        problem = nil
        friends = nil; invite = nil; friendsNote = nil
    }

    private static func cancelled(_ error: Error) -> Bool {
        if let e = error as? ASAuthorizationError, e.code == .canceled { return true }
        if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return true }
        return false
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
        // **Back to `.fullName`, and PD-063's Apple half is unproven rather than wrong** (PD-073).
        // Asking for a name nothing reads is still worth not doing, and it was changed to `[]` on the
        // same day Sign in with Apple failed on the founder's phone with `AuthorizationError Code=1000`.
        // That error has a documented cause here that is not code — a build signed before the App ID
        // carried its capabilities — and Sign in with Apple cannot be exercised from a simulator, so the
        // change could not be cleared. A working sign-in beats a tidier consent sheet: this goes back to
        // what shipped, and the scope comes off again only once someone has watched it work on a device.
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
        #if DEBUG
        // Screenshots of the signed-in screens, in a simulator that cannot sign in to anything.
        // Debug builds only, and only when launched with the argument; see `ScreenshotAccount`.
        if let staged = ScreenshotAccount.storeIfAsked() { return staged }
        #endif
        guard let configuration = ServerConfiguration.fromInfoPlist() else { return nil }
        let api = ThroAPI(configuration: configuration, deviceId: deviceId(journalDeviceId: journalDeviceId), store: KeychainSessionStore())
        return AccountStore(api: api, configuration: configuration, services: LiveSignInServices(),
                            cache: KeychainProfileCache())
    }
}
