import Foundation

// MARK: - IrohProfileError

public enum IrohProfileError: Error, LocalizedError {
    case invalidURL
    case notAuthenticated
    case networkError(String)
    case profileNotFound
    case invalidResponse
    case serverError(Int, String)
    case encodingError(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .notAuthenticated:
            "Not authenticated. Please log in first."
        case let .networkError(message):
            "Network error: \(message)"
        case .profileNotFound:
            "Profile not found"
        case .invalidResponse:
            "Invalid response from server"
        case let .serverError(code, message):
            "Server error (\(code)): \(message)"
        case let .encodingError(message):
            "Encoding error: \(message)"
        case let .decodingError(message):
            "Decoding error: \(message)"
        }
    }
}

// MARK: - IrohProfileClient

/// HTTP client for creator profile operations via iroh.arkavo.net
public actor IrohProfileClient {
    // MARK: - Configuration

    private let baseURL: URL
    private let session: URLSession

    // MARK: - Initialization

    public init(
        baseURL: URL = URL(string: "https://iroh.arkavo.net")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Public API

    /// Publish a creator profile to the iroh network
    /// - Parameters:
    ///   - profile: The creator profile to publish
    ///   - token: NTDF authentication token
    /// - Returns: The iroh ticket for the published profile
    public func publishProfile(_ profile: CreatorProfile, token: String) async throws -> PublishProfileResponse {
        let url = baseURL.appendingPathComponent("v1/profiles")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("NTDF \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try profile.toData()
        } catch {
            throw IrohProfileError.encodingError(error.localizedDescription)
        }

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IrohProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(PublishProfileResponse.self, from: data)
            } catch {
                throw IrohProfileError.decodingError(error.localizedDescription)
            }
        case 401:
            throw IrohProfileError.notAuthenticated
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IrohProfileError.serverError(httpResponse.statusCode, message)
        }
    }

    /// Update an existing creator profile
    /// - Parameters:
    ///   - profile: The updated creator profile
    ///   - token: NTDF authentication token
    /// - Returns: The updated profile response
    public func updateProfile(_ profile: CreatorProfile, token: String) async throws -> PublishProfileResponse {
        let publicIDHex = profile.publicID.map { String(format: "%02x", $0) }.joined()
        let url = baseURL.appendingPathComponent("v1/profiles/\(publicIDHex)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("NTDF \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            var updatedProfile = profile
            updatedProfile.updatedAt = Date()
            updatedProfile.version += 1
            request.httpBody = try updatedProfile.toData()
        } catch {
            throw IrohProfileError.encodingError(error.localizedDescription)
        }

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IrohProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(PublishProfileResponse.self, from: data)
            } catch {
                throw IrohProfileError.decodingError(error.localizedDescription)
            }
        case 401:
            throw IrohProfileError.notAuthenticated
        case 404:
            throw IrohProfileError.profileNotFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IrohProfileError.serverError(httpResponse.statusCode, message)
        }
    }

    /// Fetch a creator profile by public ID
    /// - Parameter publicID: 32-byte public ID
    /// - Returns: The creator profile if found
    public func fetchProfile(publicID: Data) async throws -> CreatorProfile {
        let publicIDHex = publicID.map { String(format: "%02x", $0) }.joined()
        let url = baseURL.appendingPathComponent("v1/profiles/\(publicIDHex)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IrohProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let profileResponse = try decoder.decode(FetchProfileResponse.self, from: data)
                return profileResponse.profile
            } catch {
                throw IrohProfileError.decodingError(error.localizedDescription)
            }
        case 404:
            throw IrohProfileError.profileNotFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IrohProfileError.serverError(httpResponse.statusCode, message)
        }
    }

    /// Fetch a creator profile by iroh ticket
    /// - Parameter ticket: Iroh blob ticket string
    /// - Returns: The creator profile
    public func fetchProfile(ticket: String) async throws -> CreatorProfile {
        guard let encodedTicket = ticket.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw IrohProfileError.invalidURL
        }

        let url = baseURL.appendingPathComponent("v1/profiles/ticket/\(encodedTicket)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IrohProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let profileResponse = try decoder.decode(FetchProfileResponse.self, from: data)
                return profileResponse.profile
            } catch {
                throw IrohProfileError.decodingError(error.localizedDescription)
            }
        case 404:
            throw IrohProfileError.profileNotFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IrohProfileError.serverError(httpResponse.statusCode, message)
        }
    }

    /// Search for creator profiles
    /// - Parameters:
    ///   - query: Search query (matches displayName, handle, bio)
    ///   - categories: Optional filter by content categories
    ///   - limit: Maximum number of results (default 20)
    /// - Returns: Array of matching creator profiles
    public func searchProfiles(
        query: String? = nil,
        categories: [ContentCategory]? = nil,
        limit: Int = 20
    ) async throws -> [CreatorProfile] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/profiles/search"), resolvingAgainstBaseURL: false)

        var queryItems: [URLQueryItem] = []
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let categories, !categories.isEmpty {
            let categoryString = categories.map(\.rawValue).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "categories", value: categoryString))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw IrohProfileError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IrohProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let searchResponse = try decoder.decode(SearchProfilesResponse.self, from: data)
                return searchResponse.profiles
            } catch {
                throw IrohProfileError.decodingError(error.localizedDescription)
            }
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IrohProfileError.serverError(httpResponse.statusCode, message)
        }
    }

    /// Get featured creator profiles
    /// - Parameter limit: Maximum number of results (default 10)
    /// - Returns: Array of featured creator profiles
    public func getFeaturedProfiles(limit: Int = 10) async throws -> [CreatorProfile] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/profiles/featured"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = components?.url else {
            throw IrohProfileError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IrohProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let featuredResponse = try decoder.decode(SearchProfilesResponse.self, from: data)
                return featuredResponse.profiles
            } catch {
                throw IrohProfileError.decodingError(error.localizedDescription)
            }
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IrohProfileError.serverError(httpResponse.statusCode, message)
        }
    }

    /// Check if the iroh service is healthy
    /// - Returns: True if service is healthy
    public func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Private Methods

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw IrohProfileError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - Response Types

public struct PublishProfileResponse: Codable, Sendable {
    public let success: Bool
    public let publicID: String
    public let ticket: String
    public let version: Int
}

public struct FetchProfileResponse: Codable, Sendable {
    public let profile: CreatorProfile
    public let ticket: String?
}

public struct SearchProfilesResponse: Codable, Sendable {
    public let profiles: [CreatorProfile]
    public let total: Int
    public let hasMore: Bool
}
