import AuthenticationServices
import Foundation
import Security

class RedditAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let clientId = "5Yf5m-g6oyKSWjMZO1nCHQ"
    private let redirectUri = "arkavo://oath/callback"
    private let clientSecret = "" // not needed for this flow
    private let tokenKeychainKey = "com.arkavo.redditToken"
    private var authenticationSession: ASWebAuthenticationSession?

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            else {
                fatalError("No window found in the current window scene")
            }
            return window
        #elseif os(macOS)
            guard let window = NSApplication.shared.windows.first
            else {
                fatalError("No window found in the application")
            }
            return window
        #else
            fatalError("Unsupported platform")
        #endif
    }

    func startOAuthFlow() async throws -> Bool {
        let state = UUID().uuidString
        let authURL = URL(string: "https://www.reddit.com/api/v1/authorize.compact")!

        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "duration", value: "permanent"),
            URLQueryItem(name: "scope", value: "read identity"),
        ]

        return try await withCheckedThrowingContinuation { continuation in
            authenticationSession = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "arkavo"
            ) { [weak self] callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                      returnedState == state
                else {
                    continuation.resume(throwing: NSError(domain: "RedditAuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL"]))
                    return
                }

                Task {
                    do {
                        try await self?.exchangeCodeForToken(code: code)
                        continuation.resume(returning: true)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            authenticationSession?.presentationContextProvider = self
            authenticationSession?.prefersEphemeralWebBrowserSession = true
            authenticationSession?.start()
        }
    }

    private func exchangeCodeForToken(code: String) async throws {
        let tokenURL = URL(string: "https://www.reddit.com/api/v1/access_token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"

        let credentials = "\(clientId):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
        ]

        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(RedditToken.self, from: data)
        try saveToken(token)
    }

    private func saveToken(_ token: RedditToken) throws {
        let tokenData = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecValueData as String: tokenData,
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainError", code: Int(status))
        }
    }

    func getToken() throws -> RedditToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let tokenData = result as? Data,
              let token = try? JSONDecoder().decode(RedditToken.self, from: tokenData)
        else {
            return nil
        }

        return token
    }
}

struct RedditToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

class RedditScanner {
    private let authManager: RedditAuthManager
    private let apiBaseURL = "https://oauth.reddit.com"
    private let contentMatcher = ContentMatcher()
    private var knownSignatures: [ContentSignature] = []

    init(authManager: RedditAuthManager) {
        self.authManager = authManager
    }

    func addSignature(_ signature: ContentSignature) {
        knownSignatures.append(signature)
    }

    func scanContent() async throws {
        guard let token = try await authManager.getToken() else {
            throw NSError(domain: "RedditScannerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid token"])
        }

        var request = URLRequest(url: URL(string: "\(apiBaseURL)/hot")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Arkavo/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        // Decode Reddit response
        let decoder = JSONDecoder()
        let listing: RedditListing = try decoder.decode(RedditListing.self, from: data)

        // Process each post
        let preprocessor = try ContentPreprocessor()

        for post in listing.data.children.map(\.data) {
            // Combine title and content for processing
            let content = [post.title, post.selftext].compactMap { $0 }.joined(separator: " ")

            // Generate signature for the content
            let signature = try preprocessor.generateSignature(for: content)

            // Find potential matches against known signatures
            let matches = contentMatcher.findMatches(signature: signature, against: knownSignatures)

            // Process matches based on similarity threshold
            for match in matches {
                switch match.matchType {
                case .exact:
                    handleExactMatch(post: post, match: match)
                case .similar:
                    handleSimilarMatch(post: post, match: match)
                case .partial:
                    handlePartialMatch(post: post, match: match)
                case .weak:
                    // Log weak matches but don't take action
                    print("Weak match found: \(match.similarity) for post: \(post.id)")
                }
            }
        }
    }

    private func handleExactMatch(post: RedditPost, match: Match) {
        print("Exact match found!")
        print("Post ID: \(post.id)")
        print("Similarity: \(match.similarity)")
        print("Match details: \(match.matchDetails)")

        // Notify observers about the exact match
        NotificationCenter.default.post(
            name: .redditContentMatch,
            object: nil,
            userInfo: [
                "matchType": "exact",
                "postId": post.id,
                "similarity": match.similarity,
                "permalink": post.permalink,
                "matchDetails": match.matchDetails,
            ]
        )
    }

    private func handleSimilarMatch(post: RedditPost, match: Match) {
        print("Similar match detected!")
        print("Post ID: \(post.id)")
        print("Similarity: \(match.similarity)")

        NotificationCenter.default.post(
            name: .redditContentMatch,
            object: nil,
            userInfo: [
                "matchType": "similar",
                "postId": post.id,
                "similarity": match.similarity,
                "permalink": post.permalink,
                "matchDetails": match.matchDetails,
            ]
        )
    }

    private func handlePartialMatch(post: RedditPost, match: Match) {
        print("Partial match identified")
        print("Post ID: \(post.id)")
        print("Similarity: \(match.similarity)")

        NotificationCenter.default.post(
            name: .redditContentMatch,
            object: nil,
            userInfo: [
                "matchType": "partial",
                "postId": post.id,
                "similarity": match.similarity,
                "permalink": post.permalink,
                "matchDetails": match.matchDetails,
            ]
        )
    }
}

// Notification extension for content matches
extension Notification.Name {
    static let redditContentMatch = Notification.Name("RedditContentMatch")
}

actor RedditRateLimiter {
    // Token bucket configuration
    private let maxTokens: Double = 60 // Maximum number of tokens (requests)
    private let refillRate: Double = 1 // Tokens added per second
    private var currentTokens: Double // Current available tokens
    private var lastRefillTime: Date

    // Queue for tracking requests
    private var requestQueue: [(Date, Double)] = []
    private let queueWindow: TimeInterval = 60 // 1 minute window

    init() {
        currentTokens = 60
        lastRefillTime = Date()
    }

    private func refillTokens() {
        let now = Date()
        let timePassed = now.timeIntervalSince(lastRefillTime)
        let tokensToAdd = timePassed * refillRate

        currentTokens = min(maxTokens, currentTokens + tokensToAdd)
        lastRefillTime = now

        // Clean up old requests from queue
        let cutoff = now.addingTimeInterval(-queueWindow)
        requestQueue.removeAll { $0.0 < cutoff }
    }

    func acquireToken() async throws -> Date {
        refillTokens()

        // Calculate current request rate
        let now = Date()
        let recentRequests = requestQueue.filter { $0.0 > now.addingTimeInterval(-queueWindow) }
        let currentRate = recentRequests.count

        if currentRate >= Int(maxTokens) {
            // Calculate wait time based on oldest request
            if let oldestRequest = recentRequests.first {
                let waitTime = oldestRequest.0.addingTimeInterval(queueWindow).timeIntervalSince(now)
                if waitTime > 0 {
                    try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
            }
        }

        if currentTokens < 1 {
            let waitTime = (1 - currentTokens) / refillRate
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            refillTokens()
        }

        currentTokens -= 1
        requestQueue.append((now, 1))
        return now
    }

    func remainingTokens() -> Double {
        refillTokens()
        return currentTokens
    }
}

class RedditAPIClient {
    private let rateLimiter = RedditRateLimiter()
    let authManager: RedditAuthManager
    private let retryLimit = 3

    init(authManager: RedditAuthManager) {
        self.authManager = authManager
    }

    enum APIError: Error, Equatable {
        case rateLimitExceeded
        case invalidResponse
        case unauthorized
        case networkError(Error)
        case maxRetriesExceeded
        case decodingError(Error)

        static func == (lhs: APIError, rhs: APIError) -> Bool {
            switch (lhs, rhs) {
            case (.rateLimitExceeded, .rateLimitExceeded),
                 (.invalidResponse, .invalidResponse),
                 (.unauthorized, .unauthorized),
                 (.maxRetriesExceeded, .maxRetriesExceeded):
                true
            case let (.networkError(lhsError), .networkError(rhsError)):
                lhsError.localizedDescription == rhsError.localizedDescription
            default:
                false
            }
        }
    }

    func makeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < retryLimit {
            do {
                // Wait for rate limit token
                _ = try await rateLimiter.acquireToken()

                // Make the request
                let (data, response) = try await URLSession.shared.data(for: request)

                // Debug: Print response for troubleshooting
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("API Response: \(jsonString)")
                }

                // Handle rate limit headers if present
                if let httpResponse = response as? HTTPURLResponse {
                    handleRateLimitHeaders(httpResponse)

                    switch httpResponse.statusCode {
                    case 200 ... 299:
                        do {
                            return try JSONDecoder().decode(T.self, from: data)
                        } catch {
                            print("Decoding error: \(error)")
                            throw APIError.decodingError(error)
                        }
                    case 429:
                        throw APIError.rateLimitExceeded
                    case 401:
                        // Token might be expired, try to refresh
                        try await refreshTokenAndRetry()
                        attempt += 1
                        continue
                    default:
                        throw APIError.invalidResponse
                    }
                }

                throw APIError.invalidResponse
            } catch let error as APIError where error == .rateLimitExceeded {
                // Wait longer for rate limit errors
                try await Task.sleep(nanoseconds: UInt64(5 * 1_000_000_000)) // 5 seconds
                attempt += 1
                lastError = error
            } catch {
                lastError = error
                attempt += 1
            }
        }
        print("lastError: \(lastError?.localizedDescription ?? "none")")
        throw APIError.maxRetriesExceeded
    }

    // Scan subreddit returning proper Reddit listing format
    func scanSubreddit(_ subreddit: String, limit: Int = 25) async throws -> [RedditPost] {
        guard let token = try await authManager.getToken() else {
            throw APIError.unauthorized
        }

        var urlComponents = URLComponents(string: "https://oauth.reddit.com/r/\(subreddit)/new")!
        urlComponents.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "raw_json", value: "1"),
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Arkavo/1.0", forHTTPHeaderField: "User-Agent")

        // Use the correct response type (RedditListing)
        let listing: RedditListing = try await makeRequest(request)
        // Extract posts from the listing
        return listing.data.children.map(\.data)
    }

    private func handleRateLimitHeaders(_ response: HTTPURLResponse) {
        // Parse Reddit's rate limit headers
        let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining")
        let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset")
        let used = response.value(forHTTPHeaderField: "x-ratelimit-used")

        print("Rate Limit - Remaining: \(remaining ?? "unknown"), Reset: \(reset ?? "unknown"), Used: \(used ?? "unknown")")
    }

    private func refreshTokenAndRetry() async throws {
        // Implement token refresh logic
        // For now, just throw unauthorized to trigger a new login
        throw APIError.unauthorized
    }
}

struct RedditListing: Codable {
    let kind: String
    let data: ListingData
}

struct ListingData: Codable {
    let children: [RedditChild]
    let after: String?
    let before: String?
}

struct RedditChild: Codable {
    let kind: String
    let data: RedditPost
}

struct RedditPost: Codable {
    let id: String
    let title: String
    let url: String?
    let author: String
    let created_utc: Double
    let subreddit: String
    let selftext: String?
    let thumbnail: String?
    let permalink: String

    // Add any additional fields you need
    enum CodingKeys: String, CodingKey {
        case id, title, url, author, created_utc, subreddit, selftext, thumbnail, permalink
    }
}

class RedditScannerService {
    private let apiClient: RedditAPIClient
    private var scanTask: Task<Void, Error>?
    private let contentQueue = DispatchQueue(label: "com.arkavo.redditscanner", qos: .utility)
    private var lastScannedPostIDs: Set<String> = []

    // Expose the scanner instance
    let scanner: RedditScanner

    init(apiClient: RedditAPIClient) {
        self.apiClient = apiClient
        scanner = RedditScanner(authManager: apiClient.authManager)
    }

    func startScanning(subreddits: [String]) {
        scanTask = Task {
            var currentProgress = 0.0
            let progressIncrement = 1.0 / Double(subreddits.count)

            while !Task.isCancelled {
                for subreddit in subreddits {
                    do {
                        updateProgress(progress: currentProgress, status: "Scanning r/\(subreddit)")

                        // Use the scanner instance
                        try await scanner.scanContent()

                        currentProgress += progressIncrement
                        updateProgress(progress: min(currentProgress, 1.0),
                                       status: "Completed r/\(subreddit)")

                        // Add delay between subreddits to help with rate limiting
                        try await Task.sleep(nanoseconds: UInt64(2 * 1_000_000_000))
                    } catch {
                        handleScanError(error, subreddit: subreddit)
                        // Continue with next subreddit despite error
                        currentProgress += progressIncrement
                    }
                }

                // Reset progress for next cycle
                currentProgress = 0.0
                // Wait before starting next scan cycle
                try await Task.sleep(nanoseconds: UInt64(30 * 1_000_000_000))
            }
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func processContent(_ posts: [RedditPost]) {
        contentQueue.async {
            let newPosts = posts.filter { !self.lastScannedPostIDs.contains($0.id) }

            for post in newPosts {
                // Add to scanned set
                self.lastScannedPostIDs.insert(post.id)

                // Process post content
                // Example: Check for copyrighted content
                if let url = post.url {
                    // Process media URL
                    print("Processing media: \(url)")
                }

                if let text = post.selftext {
                    // Process text content
                    print("Processing text content length: \(text.count)")
                }
            }

            // Limit size of tracked post IDs
            if self.lastScannedPostIDs.count > 10000 {
                self.lastScannedPostIDs = Set(self.lastScannedPostIDs.suffix(5000))
            }
        }
    }

    private func updateProgress(progress: Double, status: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .redditScanningProgress,
                object: nil,
                userInfo: [
                    "progress": progress,
                    "status": status,
                ]
            )
        }
    }

    private func handleScanError(_ error: Error, subreddit: String) {
        let errorMessage = "Error scanning r/\(subreddit): \(error.localizedDescription)"
        print(errorMessage)

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .redditScanningProgress,
                object: nil,
                userInfo: [
                    "error": errorMessage,
                ]
            )
        }
    }
}
