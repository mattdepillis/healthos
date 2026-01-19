//
//  SpotifyAuthManager.swift
//  HealthOS
//
//  Created by Codex on 1/21/26.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit

final class SpotifyAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let clientId = "f3491fcb1399469099003057e480800f"
    static let redirectUri = "healthos://spotify-login-callback"
    static let scopes = ["user-read-recently-played"]

    @Published var isAuthorizing: Bool = false
    @Published var lastError: String? = nil

    private var authSession: ASWebAuthenticationSession?

    func authorize() async -> Result<SpotifyTokens, Error> {
        await withCheckedContinuation { cont in
            startAuthorization { result in
                cont.resume(returning: result)
            }
        }
    }

    private func startAuthorization(completion: @escaping (Result<SpotifyTokens, Error>) -> Void) {
        isAuthorizing = true
        lastError = nil

        let state = randomURLSafeString(length: 16)
        let verifier = randomURLSafeString(length: 64)
        let challenge = pkceChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            completion(.failure(SpotifyAuthError.invalidAuthURL))
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "healthos"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            self.isAuthorizing = false

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let callbackURL = callbackURL,
                  let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
                completion(.failure(SpotifyAuthError.invalidCallback))
                return
            }

            let params = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
            if params["state"] != state {
                completion(.failure(SpotifyAuthError.invalidState))
                return
            }
            if let errorDescription = params["error"] {
                completion(.failure(SpotifyAuthError.authorizationFailed(errorDescription)))
                return
            }
            guard let code = params["code"] else {
                completion(.failure(SpotifyAuthError.missingCode))
                return
            }

            Task {
                do {
                    let tokens = try await self.exchangeCodeForTokens(code: code, verifier: verifier)
                    completion(.success(tokens))
                } catch {
                    completion(.failure(error))
                }
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        authSession = session
        session.start()
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": Self.clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectUri,
            "code_verifier": verifier
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAuthError.tokenExchangeFailed
        }

        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        return SpotifyTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresIn: decoded.expiresIn
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return window
        }
        if let window = scenes.flatMap({ $0.windows }).first {
            return window
        }
        if let scene = scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        preconditionFailure("No active UIWindowScene for Spotify auth.")
    }

    private func pkceChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return base64URL(hash)
    }

    private func base64URL(_ digest: SHA256.Digest) -> String {
        let data = Data(digest)
        return base64URL(data)
    }

    private func base64URL(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return base64URL(Data(bytes)).prefix(length).description
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

struct SpotifyTokens {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

enum SpotifyAuthError: LocalizedError {
    case invalidAuthURL
    case invalidCallback
    case invalidState
    case missingCode
    case authorizationFailed(String)
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .invalidAuthURL:
            return "Failed to build Spotify auth URL."
        case .invalidCallback:
            return "Spotify callback was invalid."
        case .invalidState:
            return "State mismatch during Spotify auth."
        case .missingCode:
            return "Spotify did not return an auth code."
        case .authorizationFailed(let message):
            return "Spotify authorization failed: \(message)"
        case .tokenExchangeFailed:
            return "Spotify token exchange failed."
        }
    }
}
