import AuthenticationServices
import Foundation
import UIKit

enum YahooOAuthError: LocalizedError {
    case invalidConfiguration
    case invalidRedirect
    case invalidResponse
    case cancelled
    case tokenExchangeFailed
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Yahoo OAuth is missing a client ID, client secret, or redirect URI."
        case .invalidRedirect:
            return "Yahoo sign-in returned an invalid redirect."
        case .invalidResponse:
            return "Yahoo sign-in returned an invalid response."
        case .cancelled:
            return "Yahoo sign-in was cancelled."
        case .tokenExchangeFailed:
            return "Yahoo token exchange failed."
        case .missingRefreshToken:
            return "No Yahoo refresh token is available for this session."
        }
    }
}

@MainActor
final class YahooOAuthClient: NSObject {
    private var activeSession: ASWebAuthenticationSession?

    func authorize(using configuration: YahooOAuthConfiguration) async throws -> YahooOAuthSession {
        guard configuration.isConfigured else {
            throw YahooOAuthError.invalidConfiguration
        }

        let state = Self.randomString(length: 32)
        let nonce = Self.randomString(length: 32)

        var components = URLComponents(string: "https://api.login.yahoo.com/oauth2/request_auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile mail-r"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "language", value: "en-us")
        ]

        guard let authorizationURL = components.url,
              let callbackScheme = URL(string: configuration.redirectURI)?.scheme
        else {
            throw YahooOAuthError.invalidConfiguration
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
            throw YahooOAuthError.invalidRedirect
        }

        return try await exchangeCodeForSession(code: code, using: configuration)
    }

    func refresh(session: YahooOAuthSession, using configuration: YahooOAuthConfiguration) async throws -> YahooOAuthSession {
        guard configuration.isConfigured else {
            throw YahooOAuthError.invalidConfiguration
        }

        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            throw YahooOAuthError.missingRefreshToken
        }

        var request = URLRequest(url: URL(string: "https://api.login.yahoo.com/oauth2/get_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "redirect_uri": configuration.redirectURI,
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret
        ]
        request.httpBody = Self.formEncoded(from: body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw YahooOAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Self.session(from: tokenResponse, fallbackRefreshToken: refreshToken)
    }

    private func exchangeCodeForSession(code: String, using configuration: YahooOAuthConfiguration) async throws -> YahooOAuthSession {
        var request = URLRequest(url: URL(string: "https://api.login.yahoo.com/oauth2/get_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret
        ]
        request.httpBody = Self.formEncoded(from: body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw YahooOAuthError.tokenExchangeFailed
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
                    continuation.resume(throwing: YahooOAuthError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: YahooOAuthError.invalidRedirect)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                activeSession = nil
                continuation.resume(throwing: YahooOAuthError.invalidResponse)
            }
        }
    }

    private static func session(from tokenResponse: TokenResponse, fallbackRefreshToken: String?) -> YahooOAuthSession {
        let email = tokenResponse.idToken.flatMap(Self.extractEmail(fromIDToken:))
        return YahooOAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? fallbackRefreshToken,
            idToken: tokenResponse.idToken,
            tokenType: tokenResponse.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            email: email
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

    private static func randomString(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

extension YahooOAuthClient: ASWebAuthenticationPresentationContextProviding {
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
