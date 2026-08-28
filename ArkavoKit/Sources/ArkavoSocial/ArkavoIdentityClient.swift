import Foundation

/// A delegation the identity server has granted to an agent (`GET /agents/delegations`).
public struct DelegationInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String { agentDid }
    public let agentDid: String
    public let name: String
    public let entitlements: [String]
    public let depth: Int
    public let createdAt: Int64
    public let expiresAt: Int64?
    public let revoked: Bool

    enum CodingKeys: String, CodingKey {
        case agentDid = "agent_did"
        case name
        case entitlements
        case depth
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case revoked
    }
}

/// Errors surfaced by `ArkavoIdentityClient`. Server error bodies are plain text
/// (not JSON), so `.forbidden` and `.server` carry the raw response body string.
public enum ArkavoIdentityError: LocalizedError, Equatable, Sendable {
    case notAuthenticated
    case invalidResponse
    case unauthorized
    case forbidden(String)
    case notFound
    case server(Int, String)
    /// The server responded 2xx but logically rejected the device attestation
    /// (`{"success": false, "message": ...}`). Kept distinct from `.server`,
    /// which is reserved for genuine non-2xx responses.
    case attestationRejected(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated: no auth token available."
        case .invalidResponse: return "The identity server returned an invalid response."
        case .unauthorized: return "Unauthorized."
        case .forbidden(let body): return "Forbidden: \(body)"
        case .notFound: return "Not found."
        case .server(let code, let body): return "Identity server error \(code): \(body)"
        case .attestationRejected(let message): return "Device attestation rejected: \(message)"
        }
    }
}

/// Owns every HTTP call to `identityURL`: the `/agents/*` delegation endpoints
/// and the `/device-check/*` App Attest endpoints.
public actor ArkavoIdentityClient {
    private let baseURL: URL

    /// A single, long-lived `URLSession`. The device-check challenge/POST pairs
    /// rely on a server-side session (tower-sessions) keyed by cookie: the GET
    /// challenge stores server state that the paired POST reads back and then
    /// deletes. Do NOT replace this with a fresh session per request -- that
    /// drops the cookie and the paired POST fails with a corrupt/missing session.
    private let session: URLSession

    private let tokenProvider: @Sendable () -> String?

    public init(
        baseURL: URL = ArkavoConfiguration.shared.identityURL,
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String? = { KeychainManager.getAuthenticationToken() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - /agents/*

    public func authorizeAgent(did: String, name: String, entitlements: [String]) async throws {
        struct Body: Encodable {
            let agentDid: String
            let name: String
            let entitlements: [String]
            enum CodingKeys: String, CodingKey {
                case agentDid = "agent_did"
                case name
                case entitlements
            }
        }
        let body = try JSONEncoder().encode(Body(agentDid: did, name: name, entitlements: entitlements))
        // 409 means "already delegated" -- treated as success, not an error.
        _ = try await send(method: "POST", path: "/agents/authorize", body: body, requiresAuth: true, extraSuccessCodes: [409])
    }

    public func listDelegations() async throws -> [DelegationInfo] {
        struct Response: Decodable {
            let delegations: [DelegationInfo]
        }
        let (data, _) = try await send(method: "GET", path: "/agents/delegations", requiresAuth: true)
        return try JSONDecoder().decode(Response.self, from: data).delegations
    }

    public func revokeDelegation(did: String) async throws {
        let path = "/agents/delegations/" + encodedPathSegment(did)
        _ = try await send(method: "DELETE", path: path, requiresAuth: true)
    }

    // MARK: - /device-check/*

    public func deviceCheckChallenge(username: String) async throws -> String {
        struct Response: Decodable { let challenge: String }
        let path = "/device-check/challenge/" + encodedPathSegment(username)
        // Not required by the server, but sending it if present is harmless and
        // keeps `send` uniform.
        let (data, _) = try await send(method: "GET", path: path, requiresAuth: false)
        return try JSONDecoder().decode(Response.self, from: data).challenge
    }

    public func deviceCheckAttest(keyId: String, attestationObject: Data, clientDataHash: Data) async throws {
        struct Body: Encodable {
            let keyId: String
            let attestationObject: String
            let clientDataHash: String
            enum CodingKeys: String, CodingKey {
                case keyId = "key_id"
                case attestationObject = "attestation_object"
                case clientDataHash = "client_data_hash"
            }
        }
        struct Response: Decodable { let success: Bool; let message: String }
        let body = try JSONEncoder().encode(Body(
            keyId: keyId,
            attestationObject: attestationObject.base64EncodedString(),
            clientDataHash: clientDataHash.base64EncodedString()
        ))
        let (data, _) = try await send(method: "POST", path: "/device-check/attest", body: body, requiresAuth: false)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.success else {
            throw ArkavoIdentityError.attestationRejected(response.message)
        }
    }

    public func deviceCheckAssertChallenge(username: String) async throws -> String {
        struct Response: Decodable { let challenge: String }
        let path = "/device-check/assert-challenge/" + encodedPathSegment(username)
        // The server requires X-Auth-Token here, so fail fast rather than
        // sending a request we know will be rejected.
        let (data, _) = try await send(method: "GET", path: path, requiresAuth: true)
        return try JSONDecoder().decode(Response.self, from: data).challenge
    }

    public func deviceCheckAssert(keyId: String, assertion: Data, clientDataHash: Data) async throws -> String {
        struct Body: Encodable {
            let keyId: String
            let assertion: String
            let clientDataHash: String
            enum CodingKeys: String, CodingKey {
                case keyId = "key_id"
                case assertion
                case clientDataHash = "client_data_hash"
            }
        }
        struct Response: Decodable { let token: String }
        let body = try JSONEncoder().encode(Body(
            keyId: keyId,
            assertion: assertion.base64EncodedString(),
            clientDataHash: clientDataHash.base64EncodedString()
        ))
        // The device CWT arrives in the JSON body's "token" field, NOT an
        // X-Auth-Token response header.
        let (data, _) = try await send(method: "POST", path: "/device-check/assert", body: body, requiresAuth: false)
        return try JSONDecoder().decode(Response.self, from: data).token
    }

    // MARK: - Single choke point: auth, headers, status mapping

    /// Sends one request and maps the response status to `ArkavoIdentityError`.
    /// - Parameters:
    ///   - requiresAuth: when true, fails fast with `.notAuthenticated` (no
    ///     request sent) if `tokenProvider()` returns nil. When false, the
    ///     request is still sent with `X-Auth-Token` attached if a token
    ///     happens to be available -- harmless, and keeps this the single
    ///     header-setting choke point for every endpoint.
    ///   - extraSuccessCodes: status codes to treat as success in addition to 2xx
    ///     (e.g. 409 for `authorizeAgent`).
    /// - Returns: the response body and HTTP status code.
    private func send(
        method: String,
        path: String,
        body: Data? = nil,
        requiresAuth: Bool,
        extraSuccessCodes: Set<Int> = []
    ) async throws -> (Data, Int) {
        let token = tokenProvider()
        if requiresAuth && token == nil {
            throw ArkavoIdentityError.notAuthenticated
        }

        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ArkavoIdentityError.invalidResponse
        }

        if (200...299).contains(http.statusCode) || extraSuccessCodes.contains(http.statusCode) {
            return (data, http.statusCode)
        }

        let bodyString = String(data: data, encoding: .utf8) ?? ""
        switch http.statusCode {
        case 401: throw ArkavoIdentityError.unauthorized
        case 403: throw ArkavoIdentityError.forbidden(bodyString)
        case 404: throw ArkavoIdentityError.notFound
        default: throw ArkavoIdentityError.server(http.statusCode, bodyString)
        }
    }

    /// Percent-encodes a single path segment using the RFC 3986 "unreserved"
    /// character set, so characters that are otherwise valid in a URL path
    /// (notably `:`, which `did:key:...` identifiers contain) are still encoded.
    private func encodedPathSegment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters) ?? raw
    }

    private static let unreservedCharacters: CharacterSet = {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    }()

    private func makeURL(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path
        return components.url!
    }
}
