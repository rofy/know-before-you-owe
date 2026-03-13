import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum GoogleOAuthError: LocalizedError {
    case invalidConfiguration
    case invalidRedirect
    case invalidResponse
    case cancelled
    case tokenExchangeFailed
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Google sign-in is missing a client ID or redirect URI."
        case .invalidRedirect:
            return "Google sign-in returned an invalid redirect."
        case .invalidResponse:
            return "Google sign-in returned an invalid response."
        case .cancelled:
            return "Google sign-in was cancelled."
        case .tokenExchangeFailed:
            return "Google token exchange failed."
        case .missingRefreshToken:
            return "No Google refresh token is available for this session."
        }
    }
}

@MainActor
final class GoogleOAuthClient: NSObject {
    private var activeSession: ASWebAuthenticationSession?

    func authorize(using configuration: GoogleOAuthConfiguration) async throws -> GoogleOAuthSession {
        guard configuration.isConfigured else {
            throw GoogleOAuthError.invalidConfiguration
        }

        let state = Self.randomString(length: 32)
        let nonce = Self.randomString(length: 32)
        let codeVerifier = Self.randomString(length: 96)
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        let queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://mail.google.com/"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]

        components.queryItems = queryItems

        guard let authorizationURL = components.url,
              let callbackScheme = URL(string: configuration.redirectURI)?.scheme
        else {
            throw GoogleOAuthError.invalidConfiguration
        }

        let callbackURL = try await performWebAuthentication(
            authorizationURL: authorizationURL,
            callbackScheme: callbackScheme
        )

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleOAuthError.invalidRedirect
        }

        return try await exchangeCodeForSession(
            code: code,
            codeVerifier: codeVerifier,
            using: configuration
        )
    }

    func refresh(session: GoogleOAuthSession, using configuration: GoogleOAuthConfiguration) async throws -> GoogleOAuthSession {
        guard configuration.isConfigured else {
            throw GoogleOAuthError.invalidConfiguration
        }

        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            throw GoogleOAuthError.missingRefreshToken
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(
            from: [
                "client_id": configuration.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        ).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleOAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Self.session(from: tokenResponse, fallbackRefreshToken: refreshToken)
    }

    private func exchangeCodeForSession(
        code: String,
        codeVerifier: String,
        using configuration: GoogleOAuthConfiguration
    ) async throws -> GoogleOAuthSession {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(
            from: [
                "client_id": configuration.clientID,
                "code": code,
                "code_verifier": codeVerifier,
                "grant_type": "authorization_code",
                "redirect_uri": configuration.redirectURI
            ]
        ).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleOAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Self.session(from: tokenResponse, fallbackRefreshToken: nil)
    }

    private func performWebAuthentication(authorizationURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.activeSession = nil

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleOAuthError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: GoogleOAuthError.invalidRedirect)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            // Force a fresh chooser so personal Gmail sign-in is not hijacked by a work SSO browser session.
            session.prefersEphemeralWebBrowserSession = true
            activeSession = session

            if !session.start() {
                activeSession = nil
                continuation.resume(throwing: GoogleOAuthError.invalidResponse)
            }
        }
    }

    private static func session(from tokenResponse: TokenResponse, fallbackRefreshToken: String?) -> GoogleOAuthSession {
        GoogleOAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? fallbackRefreshToken,
            idToken: tokenResponse.idToken,
            tokenType: tokenResponse.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            email: tokenResponse.idToken.flatMap(extractEmail(fromIDToken:))
        )
    }

    private static func extractEmail(fromIDToken token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var payload = String(segments[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
        payload = payload.replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["email"] as? String
    }

    private static func formEncoded(from values: [String: String]) -> String {
        values
            .map { key, value in
                let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(escapedKey)=\(escapedValue)"
            }
            .joined(separator: "&")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomString(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

extension GoogleOAuthClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case idToken = "id_token"
    }
}
