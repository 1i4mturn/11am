import CryptoKit
import Foundation

/// Your one-off app registration with Microsoft (entra.microsoft.com): its client ID, and which directory to sign in to.
struct MicrosoftApp: Codable, Hashable, Sendable {
    var clientID: String
    /// "common" works for work, school and personal accounts when the registration allows all three;
    /// otherwise the registration's Directory (tenant) ID.
    var tenant = "common"
}

struct MicrosoftTokens: Sendable {
    var accessToken: String
    var refreshToken: String?
    /// A couple of minutes early, so a token never runs out mid-sync.
    var expiresAt: Date
    var idToken: String?
}

/// Microsoft sign-in for mail: OAuth 2.0 with PKCE as a public client (no secret in the app), as Microsoft requires
/// for Outlook.com and Microsoft 365 now that app passwords are switched off.
/// Reading uses IMAP with the token; sending uses Microsoft Graph, which works even where SMTP sign-in is disabled.
enum MicrosoftAuth {
    /// The tests point these at a local fake.
    static var authorityHost = "https://login.microsoftonline.com"
    static let redirectURI = "au.elevenam.sandbox://auth"
    static let callbackScheme = "au.elevenam.sandbox"
    static let imapScope = "https://outlook.office.com/IMAP.AccessAsUser.All"
    static let graphSendScope = "https://graph.microsoft.com/Mail.Send"
    static let calendarScope = "https://graph.microsoft.com/Calendars.ReadWrite"
    /// Consent for reading mail (IMAP), sending (Graph) and Leo's calendar is asked for once, together.
    static let signInScopes = ["openid", "email", "profile", "offline_access", imapScope, graphSendScope, calendarScope]

    struct PKCE: Sendable {
        let verifier: String
        let challenge: String
        let state: String

        static func make() -> PKCE {
            let verifier = base64URL(randomBytes(32))
            let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            return PKCE(verifier: verifier, challenge: challenge, state: base64URL(randomBytes(16)))
        }
    }

    static func authorizeURL(app: MicrosoftApp, pkce: PKCE, loginHint: String? = nil) -> URL? {
        var components = URLComponents(string: "\(authorityHost)/\(app.tenant)/oauth2/v2.0/authorize")
        var items = [
            URLQueryItem(name: "client_id", value: app.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: signInScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        if let loginHint, !loginHint.isEmpty { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components?.queryItems = items
        return components?.url
    }

    /// The authorisation code from the redirect, after checking it answers our request.
    static func code(from callback: URL, state: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw MailError("Microsoft sign-in: \(value("error_description")?.components(separatedBy: "\r\n").first ?? error)")
        }
        guard value("state") == state, let code = value("code"), !code.isEmpty else {
            throw MailError("Microsoft sign-in didn't come back as expected. Try again.")
        }
        return code
    }

    static func redeem(code: String, pkce: PKCE, app: MicrosoftApp) async throws -> MicrosoftTokens {
        try await token(app: app, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
            "scope": "offline_access openid email profile \(imapScope)",
        ])
    }

    /// A fresh access token for one resource (IMAP or Graph) from the long-lived refresh token.
    static func refresh(_ refreshToken: String, app: MicrosoftApp, scope: String) async throws -> MicrosoftTokens {
        try await token(app: app, form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "offline_access \(scope)",
        ])
    }

    private static func token(app: MicrosoftApp, form: [String: String]) async throws -> MicrosoftTokens {
        guard let url = URL(string: "\(authorityHost)/\(app.tenant)/oauth2/v2.0/token") else {
            throw MailError("The Microsoft directory \"\(app.tenant)\" doesn't look right.")
        }
        var fields = form
        fields["client_id"] = app.clientID
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard let access = json["access_token"] as? String else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(status)"
            throw MailError("Microsoft sign-in: \(detail.components(separatedBy: "\r\n").first ?? detail)")
        }
        let lifetime = (json["expires_in"] as? NSNumber)?.doubleValue ?? Double(json["expires_in"] as? String ?? "") ?? 3_600
        return MicrosoftTokens(accessToken: access, refreshToken: json["refresh_token"] as? String,
                               expiresAt: Date().addingTimeInterval(max(60, lifetime - 120)), idToken: json["id_token"] as? String)
    }

    /// Who signed in, from the ID token's claims. It arrived straight from Microsoft over TLS, so it's only read here.
    static func identity(from idToken: String?) -> (name: String, address: String)? {
        guard let parts = idToken?.split(separator: "."), parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let address = ((claims["email"] as? String) ?? (claims["preferred_username"] as? String) ?? "").lowercased()
        guard address.contains("@") else { return nil }
        return ((claims["name"] as? String) ?? address, address)
    }

    static func formEncoded(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Sending for Microsoft accounts: the same MIME message, handed to Graph. Outlook files it in Sent Items.
enum MicrosoftGraph {
    static var baseURL = "https://graph.microsoft.com/v1.0"

    static func send(_ mail: OutgoingMail, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/me/sendMail") else { throw MailError("Couldn't reach Outlook.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(mail.rfc5322().base64EncodedString().utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw MailError("Outlook didn't send it: \(message)")
        }
    }
}
