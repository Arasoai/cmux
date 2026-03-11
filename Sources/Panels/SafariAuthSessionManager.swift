import AuthenticationServices
import WebKit

/// Manages ASWebAuthenticationSession for "Sign in with Safari" flows.
/// Opens the current page's URL in a Safari-backed auth sheet so the user
/// gets full password autofill, Touch ID, and passkey support.
final class SafariAuthSessionManager: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var session: ASWebAuthenticationSession?
    private weak var window: NSWindow?

    /// Start a Safari authentication session for the given URL.
    /// - Parameters:
    ///   - url: The page URL to authenticate against.
    ///   - window: The presenting window for the auth sheet.
    ///   - completion: Called with the callback URL on success, nil on cancellation, or an error.
    func start(url: URL, window: NSWindow, completion: @escaping (URL?, Error?) -> Void) {
        self.window = window

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "cmux-auth"
        ) { callbackURL, error in
            completion(callbackURL, error)
        }

        // Use non-ephemeral so the user's existing Safari session, Keychain passwords,
        // and passkeys are all available in the auth sheet.
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self

        self.session = session
        session.start()
    }

    func cancel() {
        session?.cancel()
        session = nil
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? NSApp.keyWindow ?? ASPresentationAnchor()
    }
}
