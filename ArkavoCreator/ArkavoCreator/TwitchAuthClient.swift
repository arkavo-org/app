import ArkavoKit
import ArkavoSocial
import Combine
import CommonCrypto
import Foundation

@MainActor
class TwitchAuthClient: ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: Error?
    @Published var username: String?
    @Published var userId: String?
    @Published var followerCount: Int?
    @Published var channelDescription: String?
    @Published var profileImageURL: String?
    @Published var isLive = false
    @Published var viewerCount: Int?
    @Published var streamTitle: String?
    @Published var gameName: String?
    @Published var streamStartedAt: Date?
    @Published var broadcasterType: String?
    @Published var channelTags: [String] = []
    @Published var broadcasterLanguage: String?
    @Published var contentClassificationLabels: [String] = []
    @Published var recentVideos: [TwitchVideo] = []
    @Published var schedule: [TwitchScheduleSegment] = []

    // MARK: - Private Properties

    private(set) var accessToken: String?
    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?

    // OAuth Configuration
    private let clientId: String
    private let clientSecret: String
    private var redirectURI: String { ArkavoConfiguration.shared.oauthRedirectURL(for: "twitch") }
    private let authURL = "https://id.twitch.tv/oauth2/authorize"
    private let tokenURL = "https://id.twitch.tv/oauth2/token"
    private let scopes = [
        "user:read:email",
        "channel:read:stream_key",  // Note: This scope may not actually work - Twitch restricts stream key access
        "chat:read"  // Read chat messages for Muse avatar reactions
    ]

    // MARK: - Initialization

    init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret

        // Set up notification observer for OAuth callback
        notificationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("TwitchOAuthCallback"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            Task { @MainActor [weak self] in
                do {
                    try await self?.handleCallback(url)
                } catch {
                    self?.error = error
                }
            }
        }

        loadStoredCredentials()
    }

    nonisolated deinit {
        // Note: Cannot safely remove observer from deinit in actor-isolated class
        // The observer will be cleaned up when the notification center deallocates
    }

    // MARK: - Public Methods

    /// Generates the OAuth authorization URL
    /// Uses standard Authorization Code Grant Flow (no PKCE)
    func generateAuthorizationURL() -> URL {
        debugLog("🔍 Generating authorization URL (Authorization Code Grant Flow)")

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "force_verify", value: "true")
        ]

        let url = components.url!
        debugLog("🔍 Authorization URL: \(url.absoluteString)")
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
        followerCount = nil
        channelDescription = nil
        profileImageURL = nil
        isLive = false
        viewerCount = nil
        streamTitle = nil
        gameName = nil
        streamStartedAt = nil
        broadcasterType = nil
        channelTags = []
        broadcasterLanguage = nil
        contentClassificationLabels = []
        recentVideos = []
        schedule = []
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
            self.profileImageURL = user.profile_image_url
            self.channelDescription = user.description
            self.broadcasterType = user.broadcaster_type

            // Fetch additional info
            Task {
                try? await fetchChannelInfo()
                try? await fetchStreamStatus()
                try? await fetchChannelDetails()
                try? await fetchRecentVideos()
                try? await fetchSchedule()
            }
        }
    }

    /// Fetches channel information (follower count)
    func fetchChannelInfo() async throws {
        guard let token = accessToken, let userId = userId else {
            throw TwitchError.notAuthenticated
        }

        // Fetch follower count
        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/channels/followers?broadcaster_id=\(userId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TwitchError.apiFailed
        }

        let followerResponse = try JSONDecoder().decode(TwitchFollowerResponse.self, from: data)
        self.followerCount = followerResponse.total
    }

    /// Fetches current stream status
    func fetchStreamStatus() async throws {
        guard let token = accessToken, let userId = userId else {
            throw TwitchError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/streams?user_id=\(userId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TwitchError.apiFailed
        }

        let streamResponse = try JSONDecoder().decode(TwitchStreamResponse.self, from: data)
        if let stream = streamResponse.data.first {
            self.isLive = true
            self.viewerCount = stream.viewer_count
            self.streamTitle = stream.title
            self.gameName = stream.game_name
            let formatter = ISO8601DateFormatter()
            self.streamStartedAt = formatter.date(from: stream.started_at)
        } else {
            self.isLive = false
            self.viewerCount = nil
        }
    }

    /// Fetches channel details (tags, language, content classification)
    func fetchChannelDetails() async throws {
        guard let token = accessToken, let userId = userId else {
            throw TwitchError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/channels?broadcaster_id=\(userId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TwitchError.apiFailed
        }

        let channelResponse = try JSONDecoder().decode(TwitchChannelResponse.self, from: data)
        if let channel = channelResponse.data.first {
            self.channelTags = channel.tags ?? []
            self.broadcasterLanguage = channel.broadcaster_language
            self.contentClassificationLabels = channel.content_classification_labels ?? []
        }
    }

    /// Fetches recent VODs
    func fetchRecentVideos() async throws {
        guard let token = accessToken, let userId = userId else {
            throw TwitchError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/videos?user_id=\(userId)&type=archive&first=5")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TwitchError.apiFailed
        }

        let videoResponse = try JSONDecoder().decode(TwitchVideoResponse.self, from: data)
        self.recentVideos = videoResponse.data
    }

    /// Fetches stream schedule
    func fetchSchedule() async throws {
        guard let token = accessToken, let userId = userId else {
            throw TwitchError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/schedule?broadcaster_id=\(userId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchError.apiFailed
        }

        // 404 means no schedule configured — not an error
        if httpResponse.statusCode == 404 {
            self.schedule = []
            return
        }

        guard httpResponse.statusCode == 200 else {
            throw TwitchError.apiFailed
        }

        let scheduleResponse = try JSONDecoder().decode(TwitchScheduleResponse.self, from: data)
        self.schedule = scheduleResponse.data?.segments ?? []
    }

    /// Fetches the stream key for the authenticated broadcaster
    func fetchStreamKey() async throws -> String? {
        guard let token = accessToken, let userId = userId else {
            throw TwitchError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/streams/key?broadcaster_id=\(userId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        struct StreamKeyResponse: Decodable {
            struct StreamKeyData: Decodable {
                let stream_key: String
            }
            let data: [StreamKeyData]
        }

        let decoded = try JSONDecoder().decode(StreamKeyResponse.self, from: data)
        return decoded.data.first?.stream_key
    }

    /// Refreshes all channel data
    func refreshChannelData() async {
        do {
            try await fetchUserInfo()
        } catch {
            self.error = error
        }
    }

    // MARK: - Private Methods

    private func exchangeCodeForToken(_ code: String) async throws {
        debugLog("🔍 Exchanging code for token (Authorization Code Grant Flow)...")
        debugLog("🔍 Client ID: \(clientId)")
        debugLog("🔍 Redirect URI: \(redirectURI)")
        debugLog("🔍 Code: \(code)")

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

        debugLog("🔍 Token request parameters: client_id, client_secret, code, grant_type, redirect_uri")

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Set the body with the form data (remove the leading '?')
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("❌ Token exchange: Invalid HTTP response")
            throw TwitchError.tokenExchangeFailed
        }

        // Log the response for debugging
        debugLog("🔍 Token exchange response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            debugLog("🔍 Token exchange response body: \(responseString)")
        }

        guard httpResponse.statusCode == 200 else {
            debugLog("❌ Token exchange failed with status: \(httpResponse.statusCode)")
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
        // Migrate from UserDefaults to Keychain for better security
        KeychainManager.save(value: token, service: "com.arkavo.twitch", account: "access_token")

        // Clean up old UserDefaults storage if it exists
        UserDefaults.standard.removeObject(forKey: "twitch_access_token")
    }

    private func loadStoredCredentials() {
        // Try Keychain first (new method)
        if let tokenData = try? KeychainManager.load(service: "com.arkavo.twitch", account: "access_token"),
           let token = String(data: tokenData, encoding: .utf8) {
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
        // Fallback to UserDefaults for existing users (migration path)
        else if let token = UserDefaults.standard.string(forKey: "twitch_access_token") {
            self.accessToken = token
            // Migrate to Keychain
            saveStoredCredentials(token: token)
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
        try? KeychainManager.delete(service: "com.arkavo.twitch", account: "access_token")
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
    let profile_image_url: String?
    let description: String?
    let broadcaster_type: String?
}

private struct TwitchFollowerResponse: Codable {
    let total: Int
    let data: [TwitchFollower]
}

private struct TwitchFollower: Codable {
    let user_id: String
    let user_name: String
    let followed_at: String
}

private struct TwitchStreamResponse: Codable {
    let data: [TwitchStream]
}

private struct TwitchStream: Codable {
    let id: String
    let user_id: String
    let user_name: String
    let game_name: String
    let type: String
    let title: String
    let viewer_count: Int
    let started_at: String
}

private struct TwitchChannelResponse: Codable {
    let data: [TwitchChannel]
}

private struct TwitchChannel: Codable {
    let broadcaster_language: String?
    let game_name: String?
    let game_id: String?
    let title: String?
    let delay: Int?
    let tags: [String]?
    let content_classification_labels: [String]?
    let is_branded_content: Bool?
}

private struct TwitchVideoResponse: Codable {
    let data: [TwitchVideo]
}

private struct TwitchScheduleResponse: Codable {
    let data: TwitchScheduleData?
}

private struct TwitchScheduleData: Codable {
    let segments: [TwitchScheduleSegment]?
    let broadcaster_id: String?
    let broadcaster_name: String?
}

// MARK: - Public Models

struct TwitchVideo: Identifiable, Codable {
    let id: String
    let title: String
    let url: String
    let duration: String
    let view_count: Int
    let created_at: String
    let thumbnail_url: String
}

struct TwitchScheduleSegment: Identifiable, Codable {
    let id: String
    let start_time: String
    let end_time: String
    let title: String
    let canceled_until: String?
    let category: TwitchScheduleCategory?
}

struct TwitchScheduleCategory: Codable {
    let id: String
    let name: String
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
