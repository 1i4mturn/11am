import AppKit
import AuthenticationServices
import Foundation

/// Opens Microsoft's own sign-in page in a system web sheet. 11am never sees your Microsoft password.
@MainActor
final class MicrosoftSignIn {
    private var session: ASWebAuthenticationSession?
    private var anchor: SignInAnchor?

    struct Result: Sendable {
        var tokens: MicrosoftTokens
        var name: String
        var address: String
    }

    func signIn(app: MicrosoftApp, loginHint: String? = nil) async throws -> Result {
        let pkce = MicrosoftAuth.PKCE.make()
        guard let url = MicrosoftAuth.authorizeURL(app: app, pkce: pkce, loginHint: loginHint) else {
            throw MailError("That client ID or directory doesn't look right.")
        }
        let anchor = SignInAnchor(window: NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow())
        self.anchor = anchor
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: MicrosoftAuth.callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: MailError("Sign-in was cancelled."))
                } else {
                    continuation.resume(throwing: error ?? MailError("Microsoft sign-in didn't finish."))
                }
            }
            session.presentationContextProvider = anchor
            self.session = session
            if !session.start() {
                continuation.resume(throwing: MailError("Couldn't open the Microsoft sign-in window."))
            }
        }
        session = nil
        self.anchor = nil
        let code = try MicrosoftAuth.code(from: callback, state: pkce.state)
        let tokens = try await MicrosoftAuth.redeem(code: code, pkce: pkce, app: app)
        guard let identity = MicrosoftAuth.identity(from: tokens.idToken) else {
            throw MailError("Microsoft didn't say which address you signed in with. Check the registration includes the email permission.")
        }
        return Result(tokens: tokens, name: identity.name, address: identity.address)
    }
}

private final class SignInAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: NSWindow

    init(window: NSWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

/// Each Microsoft account's refresh token lives in the Keychain; short-lived access tokens are kept in memory only.
actor MicrosoftTokenStore {
    static let shared = MicrosoftTokenStore()
    private var cache: [String: MicrosoftTokens] = [:]

    func accessToken(for account: MailAccount, scope: String) async throws -> String {
        let key = account.id + "|" + scope
        if let cached = cache[key], cached.expiresAt > Date() { return cached.accessToken }
        guard let app = account.microsoft, let refresh = Keychain.read(account: account.keychainKey) else {
            throw MailError("\(account.name) needs you to sign in with Microsoft again (Accounts menu).")
        }
        do {
            let tokens = try await MicrosoftAuth.refresh(refresh, app: app, scope: scope)
            if let rotated = tokens.refreshToken { Keychain.save(rotated, account: account.keychainKey) }
            cache[key] = tokens
            return tokens.accessToken
        } catch {
            throw MailError("\(account.name): \(error.localizedDescription) Sign in again from the Accounts menu if this keeps happening.")
        }
    }

    func remember(_ tokens: MicrosoftTokens, for account: MailAccount, scope: String) {
        cache[account.id + "|" + scope] = tokens
    }

    func forget(_ account: MailAccount) {
        cache = cache.filter { !$0.key.hasPrefix(account.id + "|") }
    }
}
