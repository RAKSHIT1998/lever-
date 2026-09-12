import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Gmail via Google's OAuth 2.0 (PKCE, iOS client — no client secret) and the Gmail REST API, read-only scope.
/// Requires the developer's own OAuth client ID; stored in the Keychain alongside tokens.
final class GmailImportSource: NSObject, EmailImportSource, ASWebAuthenticationPresentationContextProviding {
    let providerName = "Gmail"
    private let keychain = KeychainStore(service: "com.rakshit1998.lever.gmail")
    private let scope = "https://www.googleapis.com/auth/gmail.readonly"

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
        var email: String?
    }

    // MARK: Configuration

    var clientID: String? {
        get { keychain.get("clientID").flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let newValue, !newValue.isEmpty { keychain.set(Data(newValue.utf8), for: "clientID") } else { keychain.remove("clientID") }
        }
    }

    var isConfigured: Bool { !(clientID ?? "").isEmpty }
    var isConnected: Bool { tokens != nil }
    var accountLabel: String? { tokens?.email }

    private var tokens: Tokens? {
        get { keychain.get("tokens").flatMap { try? JSONDecoder.lever.decode(Tokens.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder.lever.encode(newValue) { keychain.set(data, for: "tokens") } else { keychain.remove("tokens") }
        }
    }

    /// Google's iOS redirect scheme is the client ID reversed: "com.googleusercontent.apps.<id>".
    private var redirectScheme: String? {
        guard let clientID, let idPart = clientID.split(separator: ".").first else { return nil }
        return "com.googleusercontent.apps.\(idPart)"
    }

    // MARK: Connect

    @MainActor
    func connect() async throws {
        guard let clientID, let scheme = redirectScheme else { throw EmailImportError.notConfigured }
        let verifier = Self.randomString(64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirect = "\(scheme):/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "\(scope) email"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        guard let authURL = components.url else { throw EmailImportError.authFailed("Bad auth URL") }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: EmailImportError.cancelled)
                } else {
                    continuation.resume(throwing: EmailImportError.authFailed(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw EmailImportError.authFailed("No authorization code returned")
        }
        try await exchange(code: code, verifier: verifier, redirect: redirect, clientID: clientID)
    }

    func disconnect() { tokens = nil }

    private func exchange(code: String, verifier: String, redirect: String, clientID: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": clientID, "code": code, "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect])
        let (data, _) = try await URLSession.shared.data(for: request)
        try store(tokenResponse: data, existingRefresh: nil)
    }

    private func refreshIfNeeded() async throws -> String {
        guard var current = tokens else { throw EmailImportError.tokenExpired }
        if current.expiresAt > Date().addingTimeInterval(60) { return current.accessToken }
        guard let refresh = current.refreshToken, let clientID else { tokens = nil; throw EmailImportError.tokenExpired }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        let (data, _) = try await URLSession.shared.data(for: request)
        try store(tokenResponse: data, existingRefresh: refresh)
        current = tokens ?? current
        return current.accessToken
    }

    private func store(tokenResponse data: Data, existingRefresh: String?) throws {
        struct Response: Decodable { let access_token: String; let expires_in: Double; let refresh_token: String?; let id_token: String? }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EmailImportError.authFailed(String(data: data, encoding: .utf8) ?? "Token exchange failed")
        }
        let email = response.id_token.flatMap(Self.emailClaim) ?? tokens?.email
        tokens = Tokens(accessToken: response.access_token, refreshToken: response.refresh_token ?? existingRefresh, expiresAt: Date().addingTimeInterval(response.expires_in), email: email)
    }

    // MARK: Fetch

    func fetchCandidateMessages(days: Int) async throws -> [EmailMessage] {
        let token = try await refreshIfNeeded()
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [.init(name: "q", value: EmailQuery.gmail(days: days)), .init(name: "maxResults", value: "60")]
        struct ListResponse: Decodable { struct Ref: Decodable { let id: String }; let messages: [Ref]? }
        let list: ListResponse = try await get(components.url!, token: token)
        var results: [EmailMessage] = []
        for ref in list.messages ?? [] {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(ref.id)?format=full")!
            guard let message: GmailMessage = try? await get(url, token: token) else { continue }
            if let parsed = message.asEmailMessage() { results.append(parsed) }
        }
        return results.sorted { $0.date > $1.date }
    }

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 { tokens = nil; throw EmailImportError.tokenExpired }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EmailImportError.network("HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    // MARK: Helpers

    static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement() ?? "a" })
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
    }

    static func emailClaim(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }
}

/// Gmail's message shape, reduced. Bodies are base64url; multipart messages nest parts.
struct GmailMessage: Decodable {
    struct Header: Decodable { let name: String; let value: String }
    struct Body: Decodable { let data: String? }
    final class Part: Decodable {
        let mimeType: String?
        let body: Body?
        let parts: [Part]?
    }
    struct Payload: Decodable { let headers: [Header]?; let mimeType: String?; let body: Body?; let parts: [Part]? }
    let id: String
    let internalDate: String?
    let payload: Payload?

    func asEmailMessage() -> EmailMessage? {
        guard let payload else { return nil }
        let headers = Dictionary(uniqueKeysWithValues: (payload.headers ?? []).map { ($0.name.lowercased(), $0.value) })
        let date = internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        var plain: String?
        var html: String?
        func walk(mime: String?, body: Body?, parts: [Part]?) {
            if let data = body?.data, let text = Self.decode(data) {
                if mime?.hasPrefix("text/plain") == true, plain == nil { plain = text }
                if mime?.hasPrefix("text/html") == true, html == nil { html = text }
            }
            parts?.forEach { walk(mime: $0.mimeType, body: $0.body, parts: $0.parts) }
        }
        walk(mime: payload.mimeType, body: payload.body, parts: payload.parts)
        let text = plain ?? html.map(HTMLText.strip) ?? ""
        guard !text.isEmpty else { return nil }
        let subject = headers["subject"] ?? "(no subject)"
        return EmailMessage(id: id, subject: subject, from: headers["from"] ?? "", date: date, bodyText: "\(subject)\nFrom: \(headers["from"] ?? "")\n\(text)")
    }

    static func decode(_ base64url: String) -> String? {
        var s = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
