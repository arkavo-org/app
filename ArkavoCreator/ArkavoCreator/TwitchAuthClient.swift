import Foundation
import Combine
import ArkavoSocial
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
    private let redirectURI = "https://webauthn.arkavo.net/oauth/arkavocreator/twitch"
    private let authURL = "https://id.twitch.tv/oauth2/authorize"
    private let tokenURL = "https://id.twitch.tv/oauth2/token"
    private let scopes = [
        "user:read:email",
        "channel:read:stream_key"  // Note: This scope may not actually work - Twitch restricts stream key access
    ]

    // PKCE (Proof Key for Code Exchange) - for public clients
    private var codeVerifier: String = ""
    private var codeChallenge: String = ""

    // MARK: - Initialization

    init(clientId: String) {
        self.clientId = clientId
        loadStoredCredentials()
    }

    // MARK: - Public Methods

    /// Generates the OAuth authorization URL with PKCE
    var authorizationURL: URL {
        // Generate PKCE values
        generatePKCEValues()

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "force_verify", value: "true")
        ]
        return components.url!
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

    // MARK: - PKCE Implementation

    /// Generates PKCE code_verifier and code_challenge for OAuth flow
    private func generatePKCEValues() {
        // Generate code_verifier: random 128-character string
        codeVerifier = generateRandomString(length: 128)

        // Generate code_challenge: BASE64URL(SHA256(code_verifier))
        codeChallenge = sha256(codeVerifier)
    }

    /// Generates a cryptographically secure random string
    private func generateRandomString(length: Int) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        var randomString = ""

        for _ in 0..<length {
            let randomIndex = Int.random(in: 0..<characters.count)
            let character = characters[characters.index(characters.startIndex, offsetBy: randomIndex)]
            randomString.append(character)
        }

        return randomString
    }

    /// Generates SHA256 hash and returns base64url-encoded string
    private func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        // Convert to base64url encoding (RFC 4648)
        let base64 = Data(hash).base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func exchangeCodeForToken(_ code: String) async throws {
        var components = URLComponents(string: tokenURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier), // PKCE verifier instead of client_secret
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
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
