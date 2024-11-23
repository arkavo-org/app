import Foundation

// MARK: - Core API Client
public actor PatreonClient {
    private let config: PatreonConfig
    private let urlSession: URLSession
    
    public init(config: PatreonConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: configuration)
    }
    
    deinit {
        urlSession.finishTasksAndInvalidate()
    }
}

// MARK: - Configuration
public struct PatreonConfig {
    let clientId: String
    let clientSecret: String
    let creatorAccessToken: String
    let creatorRefreshToken: String
    let redirectURI: String
    let campaignId: String
    
    public init(
        clientId: String,
        clientSecret: String,
        creatorAccessToken: String,
        creatorRefreshToken: String,
        redirectURI: String,
        campaignId: String
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.creatorAccessToken = creatorAccessToken
        self.creatorRefreshToken = creatorRefreshToken
        self.redirectURI = redirectURI
        self.campaignId = campaignId
    }
}

// MARK: - API Endpoints
extension PatreonClient {
    private enum Endpoint {
        case identity
        case campaigns
        case campaign(id: String)
        case campaignMembers(id: String)
        case member(id: String)
        case oauthToken
        
        var path: String {
            switch self {
            case .identity:
                "identity"
            case .campaigns:
                "campaigns"
            case .campaign(let id):
                "campaigns/\(id)"
            case .campaignMembers(let id):
                "campaigns/\(id)/members"
            case .member(let id):
                "members/\(id)"
            case .oauthToken:
                "token"
            }
        }
        
        var url: URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.patreon.com"
            components.path = "/api/oauth2/v2/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)"
            return components.url!
        }
    }
}

// MARK: - API Methods
extension PatreonClient {
    public func getUserIdentity(accessToken: String) async throws -> UserIdentity {
        try await request(
            endpoint: .identity,
            accessToken: accessToken,
            queryItems: [
                URLQueryItem(name: "include", value: "memberships.campaign,memberships.currently_entitled_tiers"),
                URLQueryItem(name: "fields[user]", value: UserFields.allCases.map(\.rawValue).joined(separator: ",")),
                URLQueryItem(name: "fields[member]", value: MemberFields.allCases.map(\.rawValue).joined(separator: ","))
            ]
        )
    }
    
    public func getCampaignDetails() async throws -> Campaign {
        try await request(
            endpoint: .campaign(id: config.campaignId),
            accessToken: config.creatorAccessToken,
            queryItems: [
                URLQueryItem(name: "include", value: "creator,tiers,benefits.tiers,goals"),
                URLQueryItem(name: "fields[campaign]", value: CampaignFields.allCases.map(\.rawValue).joined(separator: ",")),
                URLQueryItem(name: "fields[tier]", value: TierFields.allCases.map(\.rawValue).joined(separator: ","))
            ]
        )
    }
    
    public func getCampaignMembers() async throws -> [Member] {
        try await request(
            endpoint: .campaignMembers(id: config.campaignId),
            accessToken: config.creatorAccessToken,
            queryItems: [
                URLQueryItem(name: "include", value: "user,address,campaign,currently_entitled_tiers"),
                URLQueryItem(name: "fields[member]", value: MemberFields.allCases.map(\.rawValue).joined(separator: ","))
            ]
        )
    }
}

// MARK: - OAuth Methods
extension PatreonClient {
    public func getOAuthURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.patreon.com"
        components.path = "/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI)
        ]
        return components.url!
    }
    
    public func exchangeCode(_ code: String) async throws -> OAuthToken {
        let params = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "redirect_uri": config.redirectURI
        ]
        
        return try await request(
            endpoint: .oauthToken,
            method: "POST",
            body: params
        )
    }
    
    public func refreshToken(_ refreshToken: String) async throws -> OAuthToken {
        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
            "client_secret": config.clientSecret
        ]
        
        return try await request(
            endpoint: .oauthToken,
            method: "POST",
            body: params
        )
    }
}

// MARK: - Networking
extension PatreonClient {
    private func request<T: Decodable>(
        endpoint: Endpoint,
        method: String = "GET",
        accessToken: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: [String: String]? = nil
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method
        
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        if let body {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.map { key, value in
                "\(key)=\(value)"
            }.joined(separator: "&").data(using: .utf8)
        }
        
        if !queryItems.isEmpty {
            var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems.map { URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)) }
            request.url = components.url
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PatreonError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw PatreonError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PatreonError.decodingError(error)
        }
    }
}

// MARK: - Error Handling
public enum PatreonError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
}

// MARK: - Models

// Base Resource Object (follows JSON:API specification)
public struct ResourceObject: Codable {
    public let type: String
    public let id: String
    public let attributes: [String: AnyCodable]
    public let relationships: [String: Relationship]?
    
    public struct Relationship: Codable {
        public let data: RelationshipData
        public let links: Links?
        
        public struct Links: Codable {
            public let related: String?
            public let `self`: String?
        }
    }
    
    public struct RelationshipData: Codable {
        public let type: String
        public let id: String
    }
}

// User Data Models
public struct UserData: Codable {
    public let type: String
    public let id: String
    public let attributes: UserAttributes
    public let relationships: UserRelationships
    
    public struct UserAttributes: Codable {
        public let email: String?
        public let fullName: String
        public let isEmailVerified: Bool?
        public let imageUrl: String?
        public let thumbUrl: String?
        public let socialConnections: SocialConnections?
        
        private enum CodingKeys: String, CodingKey {
            case email
            case fullName = "full_name"
            case isEmailVerified = "is_email_verified"
            case imageUrl = "image_url"
            case thumbUrl = "thumb_url"
            case socialConnections = "social_connections"
        }
    }
    
    public struct UserRelationships: Codable {
        public let memberships: Memberships
        
        public struct Memberships: Codable {
            public let data: [ResourceObject.RelationshipData]
        }
    }
}

// Social Connections Model
public struct SocialConnections: Codable {
    public let discord: Platform?
    public let twitter: Platform?
    public let youtube: Platform?
    public let twitch: Platform?
    
    public struct Platform: Codable {
        public let userId: String
        public let url: String?
        public let scopes: [String]?
        
        private enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case url
            case scopes
        }
    }
}

// Campaign Data Models
public struct CampaignData: Codable {
    public let type: String
    public let id: String
    public let attributes: CampaignAttributes
    public let relationships: CampaignRelationships
    
    public struct CampaignAttributes: Codable {
        public let createdAt: String
        public let creationName: String?
        public let isMonthly: Bool
        public let isNSFW: Bool
        public let patronCount: Int
        public let pledgeUrl: String
        public let publishedAt: String?
        public let summary: String?
        public let url: String
        
        private enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
            case creationName = "creation_name"
            case isMonthly = "is_monthly"
            case isNSFW = "is_nsfw"
            case patronCount = "patron_count"
            case pledgeUrl = "pledge_url"
            case publishedAt = "published_at"
            case summary
            case url
        }
    }
    
    public struct CampaignRelationships: Codable {
        public let creator: ResourceObject.Relationship
        public let tiers: ResourceObject.Relationship?
        public let benefits: ResourceObject.Relationship?
        public let goals: ResourceObject.Relationship?
    }
}

// Member Models
public struct MemberAttributes: Codable {
    public let campaignLifetimeSupportCents: Int
    public let currentlyEntitledAmountCents: Int
    public let email: String?
    public let fullName: String
    public let isFollower: Bool
    public let lastChargeDate: String?
    public let lastChargeStatus: String?
    public let lifetimeSupportCents: Int
    public let patronStatus: String?
    public let pledgeCadence: Int?
    public let willPayAmountCents: Int
    
    private enum CodingKeys: String, CodingKey {
        case campaignLifetimeSupportCents = "campaign_lifetime_support_cents"
        case currentlyEntitledAmountCents = "currently_entitled_amount_cents"
        case email
        case fullName = "full_name"
        case isFollower = "is_follower"
        case lastChargeDate = "last_charge_date"
        case lastChargeStatus = "last_charge_status"
        case lifetimeSupportCents = "lifetime_support_cents"
        case patronStatus = "patron_status"
        case pledgeCadence = "pledge_cadence"
        case willPayAmountCents = "will_pay_amount_cents"
    }
}

// AnyCodable wrapper for handling dynamic JSON values
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable cannot encode value"
                )
            )
        }
    }
    
    public init(_ value: Any) {
        self.value = value
    }
}


public struct UserIdentity: Codable {
    public let data: UserData
    public let included: [ResourceObject]
}

public struct Campaign: Codable {
    public let data: CampaignData
    public let included: [ResourceObject]
}

public struct Member: Codable {
    public let attributes: MemberAttributes
    public let id: String
    public let type: String
}

public struct OAuthToken: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let scope: String
    public let tokenType: String
    
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

// MARK: - Field Enums
private enum UserFields: String, CaseIterable {
    case about, email, fullName = "full_name", imageUrl = "image_url"
}

private enum CampaignFields: String, CaseIterable {
    case createdAt = "created_at", patronCount = "patron_count", url
}

private enum TierFields: String, CaseIterable {
    case amountCents = "amount_cents", description, title
}

private enum MemberFields: String, CaseIterable {
    case email, fullName = "full_name", patronStatus = "patron_status"
}
