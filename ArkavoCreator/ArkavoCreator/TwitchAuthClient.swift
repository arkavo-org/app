import Foundation
import Combine
import ArkavoKit
import CommonCrypto

@MainActor
class TwitchAuthClient: ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: Error?
    @Published var username: String?
    @Published var userId: String?

    // MARK: - Private Properties

    private var accessToken: String?
    private var cancellables = Set<AnyCancellable>()

    // OAuth Configuration
    private let clientId: String
    private let clientSecret: String
    private let redirectURI = "https://webauthn.arkavo.net/oauth/arkavocreator/twitch"  // Server-based redirect
    private let authURL = "https://id.twitch.tv/oauth2/authorize"
    private let tokenURL = "https://id.twitch.tv/oauth2/token"
    private let scopes = [
        "user:read:email",
        "channel:read:stream_key"  // Note: This scope may not actually work - Twitch restricts stream key access
    ]

    // MARK: - Initialization

    init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        loadStoredCredentials()
    }

    // MARK: - Public Methods

    /// Generates the OAuth authorization URL
    /// Uses standard Authorization Code Grant Flow (no PKCE)
    func generateAuthorizationURL() -> URL {
        print("🔍 Generating authorization URL (Authorization Code Grant Flow)")

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "force_verify", value: "true")
        ]

        let url = components.url!
        print("🔍 Authorization URL: \(url.absoluteString)")
        return url
    }

    /// Convenience property that generates a new authorization URL
    var authorizationURL: URL {
        generateAuthorizationURL()
    }

    /// Handles the OAuth callback
    /// - Parameter url: The callback URL (arkavocreator://oauth/twitch?code=...)
    func handleCallback(_ url: URL) async throws {
        isLoading = true
        error = nil

        // Parse the callback URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TwitchError.invalidCallback
        }

        // Check for error parameter
        if let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw TwitchError.authorizationFailed(errorParam)
        }

        // Extract authorization code
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw TwitchError.noAuthCode
        }

        // Exchange code for access token
        try await exchangeCodeForToken(code)

        isLoading = false
    }

    /// Logs out the user
    func logout() {
        isAuthenticated = false
        accessToken = nil
        username = nil
        userId = nil
        KeychainManager.deleteStreamKey(for: "twitch")
        clearStoredCredentials()
    }

    /// Fetches user information
    func fetchUserInfo() async throws {
        guard let token = accessToken else {
            throw TwitchError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/users")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TwitchError.apiFailed
        }

        let userResponse = try JSONDecoder().decode(TwitchUserResponse.self, from: data)
        if let user = userResponse.data.first {
            self.username = user.display_name
            self.userId = user.id
        }
    }

    // MARK: - Private Methods

    private func exchangeCodeForToken(_ code: String) async throws {
        print("🔍 Exchanging code for token (Authorization Code Grant Flow)...")
        print("🔍 Client ID: \(clientId)")
        print("🔍 Redirect URI: \(redirectURI)")
        print("🔍 Code: \(code)")

        // Build the request body as form data
        // Use client_secret for Authorization Code Grant Flow (not PKCE)
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]

        print("🔍 Token request parameters: client_id, client_secret, code, grant_type, redirect_uri")

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Set the body with the form data (remove the leading '?')
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Token exchange: Invalid HTTP response")
            throw TwitchError.tokenExchangeFailed
        }

        // Log the response for debugging
        print("🔍 Token exchange response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔍 Token exchange response body: \(responseString)")
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ Token exchange failed with status: \(httpResponse.statusCode)")
            throw TwitchError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TwitchTokenResponse.self, from: data)
        self.accessToken = tokenResponse.access_token

        // Save token
        saveStoredCredentials(token: tokenResponse.access_token)

        // Fetch user info
        try await fetchUserInfo()

        isAuthenticated = true
    }

    // MARK: - Keychain Storage

    private func saveStoredCredentials(token: String) {
        UserDefaults.standard.set(token, forKey: "twitch_access_token")
    }

    private func loadStoredCredentials() {
        if let token = UserDefaults.standard.string(forKey: "twitch_access_token") {
            self.accessToken = token
            Task {
                do {
                    try await fetchUserInfo()
                    isAuthenticated = true
                } catch {
                    // Token might be expired
                    clearStoredCredentials()
                }
            }
        }
    }

    private func clearStoredCredentials() {
        UserDefaults.standard.removeObject(forKey: "twitch_access_token")
    }
}

// MARK: - Response Models

private struct TwitchTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let scope: [String]?
    let token_type: String
}

private struct TwitchUserResponse: Codable {
    let data: [TwitchUser]
}

private struct TwitchUser: Codable {
    let id: String
    let login: String
    let display_name: String
    let email: String?
}

// MARK: - Errors

enum TwitchError: LocalizedError {
    case invalidCallback
    case noAuthCode
    case authorizationFailed(String)
    case tokenExchangeFailed
    case notAuthenticated
    case apiFailed

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid callback URL"
        case .noAuthCode:
            return "No authorization code received"
        case .authorizationFailed(let reason):
            return "Authorization failed: \(reason)"
        case .tokenExchangeFailed:
            return "Failed to exchange code for token"
        case .notAuthenticated:
            return "Not authenticated"
        case .apiFailed:
            return "Twitch API request failed"
        }
    }
}
