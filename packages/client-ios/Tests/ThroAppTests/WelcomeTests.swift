import AuthenticationServices
import XCTest
@testable import ThroApp
import ThroNet

/// The welcome after the opening: asked once, never a gate, and never claiming more than THRØ does.
final class WelcomeTests: XCTestCase {

    func testBeingSignedOutIsWhatMakesItAsk() {
        // The rule that was wrong: it used to remember the answer for ever, so somebody who tapped
        // "Not now" never saw the sign-in board again and the app looked like it had lost it.
        XCTAssertTrue(Welcome.shows(configured: true, settled: true, signedIn: false, answeredThisLaunch: false))
        // Signed in: nothing to ask.
        XCTAssertFalse(Welcome.shows(configured: true, settled: true, signedIn: true, answeredThisLaunch: false))
        // Answered this run, either way: not again until the app is started fresh.
        XCTAssertFalse(Welcome.shows(configured: true, settled: true, signedIn: false, answeredThisLaunch: true))
        // A build with no server has nothing to sign in to.
        XCTAssertFalse(Welcome.shows(configured: false, settled: true, signedIn: false, answeredThisLaunch: false))
    }

    func testItWaitsUntilTheAppHasLookedForAStoredSignIn() {
        // Before `AccountStore.start()` finishes, "signed out" means *not looked yet*. Asking then
        // would flash the sign-in board at somebody who is already signed in, every single launch.
        XCTAssertFalse(Welcome.shows(configured: true, settled: false, signedIn: false, answeredThisLaunch: false))
        XCTAssertFalse(Welcome.shows(configured: true, settled: false, signedIn: true, answeredThisLaunch: false))
    }

    func testTheDoorOutIsPlainAndSaysWhatItCosts() {
        // PD-012 is local-first: two people score a match on one phone with no account. A welcome
        // that hid the way past it would be a lie about what the product is, so the skip is worded
        // as an action a person can want, not as a refusal.
        XCTAssertEqual(Welcome.skip(.atLaunch), "Not now, just score")
        XCTAssertFalse(Welcome.skip(.atLaunch).lowercased().contains("skip"), "not a dismissal, a choice")
        // Asked for from the You tab it is not an offer to go and score, it is a way back.
        XCTAssertEqual(Welcome.skip(.fromYou), "Back")
    }

    func testThePromiseIsTheOneThisBuildCanKeep() {
        // This sentence is on the screen because it is TRUE of this build: nothing scored here is
        // uploaded, signed in or not. The day match upload ships, this assertion fails and the
        // sentence has to change with the behaviour — which is the point of testing copy at all.
        XCTAssertEqual(Welcome.promise,
                       "Matches scored on this phone stay on this phone, signed in or not.")
    }

    func testTheCopySellsWhatAnAccountActuallyDoes() {
        // Every claim maps to something shipped: a lineup (V029 team membership), a league
        // registration (V014), a friend by code (PD-035). No rating is promised, because OD-001
        // says there is none.
        for claim in ["lineup", "league", "friend"] {
            XCTAssertTrue(Welcome.body.lowercased().contains(claim), "the body drops \(claim)")
        }
        XCTAssertFalse(Welcome.body.lowercased().contains("rating"), "OD-001: THRØ has no rating")
        XCTAssertFalse(Welcome.headline.isEmpty)
        XCTAssertLessThan(Welcome.headline.count, 30, "a headline, not a paragraph")
    }
}

/// What a person is told when a way in does not work. The founder's phone showed
/// "The operation couldn't be completed. (com.apple.AuthenticationServices.AuthorizationError
/// error 1000.)" — a sentence with no cause and no action in it.
final class SignInProblemTests: XCTestCase {

    func testNoDomainAndNoCodeEverReachesTheScreen() {
        let raw = NSError(domain: "com.apple.AuthenticationServices.AuthorizationError", code: 1000)
        let words = SignInProblem.words(raw)
        XCTAssertFalse(words.contains("com.apple"), words)
        XCTAssertFalse(words.contains("1000"), words)
        XCTAssertTrue(words.contains("Apple Account"), "it says the thing to go and check: \(words)")
    }

    func testTheDeveloperHalfNeverBecomesThePlayerHalf() {
        // PD-074. The diagnosis carries a domain, a code and a signing fact, and it exists because
        // `ASAuthorizationError.unknown` is one code for three faults. It must stay beside the sentence
        // and never inside it: the rule above is the reason this app does not show people error numbers.
        let apple = ASAuthorizationError(ASAuthorizationError.Code.unknown)
        let words = SignInProblem.words(apple)
        XCTAssertFalse(words.contains("1000"), words)
        if let diagnosis = SignInProblem.diagnosis(apple) {
            XCTAssertFalse(words.contains(diagnosis), "the annotation is not folded into the sentence")
            XCTAssertTrue(diagnosis.contains("1000"), "and it does carry the code: \(diagnosis)")
        }
    }

    func testAServerRefusalGetsNoDiagnosisBecauseItAlreadySaysWhy() {
        // The server's sentence knows exactly what it refused. A domain and a zero on top of it is noise.
        XCTAssertNil(SignInProblem.diagnosis(APIError.status(409, "already claimed")))
    }

    func testAPasskeyOnAnUnprovenDomainSaysWhatStillWorks() {
        let raw = NSError(domain: "WebAuthn", code: 1000, userInfo: [
            NSLocalizedDescriptionKey:
                "Application with identifier 2XM324WPD5.app.thro.darts is not associated with domain thro-api-staging.onrender.com",
        ])
        let words = SignInProblem.words(raw)
        // A dead end is the one thing an error must never be: Apple and Google need no domain.
        XCTAssertTrue(words.contains("Apple or Google"), words)
        XCTAssertFalse(words.contains("2XM324WPD5"), "no identifiers on a player's screen: \(words)")
    }

    func testAPhoneWithNoNetworkIsToldItCanStillScore() {
        let words = SignInProblem.words(URLError(.notConnectedToInternet))
        XCTAssertTrue(words.contains("without signing in"), words)
    }

    func testTheServersOwnSentenceIsKeptWordForWord() {
        // The server knows exactly what it refused and writes for a person; nothing here improves it.
        let said = "the ID token was not accepted: the token carries a nonce and the request did not say which"
        XCTAssertEqual(SignInProblem.words(APIError.status(401, #"{"error":"\#(said)"}"#)), said)
    }
}
