import CryptoKit
import Foundation
import SwiftData

@Model
final class Thought: Identifiable, Codable, @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var stream: Stream?
    var metadata: ThoughtMetadata
    var nano: Data

    init(id: UUID = UUID(), nano: Data, metadata: ThoughtMetadata) {
        self.id = id
        publicID = Thought.generatePublicID(from: id)
        self.metadata = metadata
        self.nano = nano
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicID = try container.decode(Data.self, forKey: .publicID)
        metadata = try container.decode(ThoughtMetadata.self, forKey: .metadata)
        nano = try container.decode(Data.self, forKey: .nano)
    }

    enum CodingKeys: String, CodingKey {
        case id, publicID, metadata, nano
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(publicID, forKey: .publicID)
        try container.encode(metadata, forKey: .metadata)
    }

    static func extractMetadata(from _: Data) -> ThoughtMetadata {
        // TODO: Parse the data to extract metadata from the NanoTDF Policy, and fix Date()
        ThoughtMetadata(
            creator: UUID(),
            mediaType: .text,
            createdAt: Date(),
            summary: "New thought",
            contributors: []
        )
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }
}

extension Thought {
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    var publicIDString: String {
        publicID.base58EncodedString
    }

    func serialize() throws -> Data {
        try Thought.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> Thought {
        try decoder.decode(Thought.self, from: data)
    }
}

struct ThoughtMetadata: Codable {
    // FIXME: publicID
    let creator: UUID
    let mediaType: MediaType
    let createdAt: Date
    // FIXME: remove summary
    let summary: String
    let contributors: [Contributor]

    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    func serialize() throws -> Data {
        try ThoughtMetadata.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> ThoughtMetadata {
        try decoder.decode(ThoughtMetadata.self, from: data)
    }
}

struct Contributor: Codable, Identifiable {
    let id: String
    let creator: Creator
    let role: String
}

struct Creator: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: String
    let latestUpdate: String
    let tier: String
    let socialLinks: [SocialLink]
    let notificationCount: Int
    let bio: String

    init(id: String, name: String, imageURL: String, latestUpdate: String, tier: String, socialLinks: [SocialLink], notificationCount: Int, bio: String) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.latestUpdate = latestUpdate
        self.tier = tier
        self.socialLinks = socialLinks
        self.notificationCount = notificationCount
        self.bio = bio
    }

    enum CodingKeys: String, CodingKey {
        case id, name, imageURL, latestUpdate, tier, socialLinks, notificationCount, bio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        imageURL = try container.decode(String.self, forKey: .imageURL)
        latestUpdate = try container.decode(String.self, forKey: .latestUpdate)
        tier = try container.decode(String.self, forKey: .tier)
        socialLinks = try container.decode([SocialLink].self, forKey: .socialLinks)
        notificationCount = try container.decode(Int.self, forKey: .notificationCount)
        bio = try container.decode(String.self, forKey: .bio)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(imageURL, forKey: .imageURL)
        try container.encode(latestUpdate, forKey: .latestUpdate)
        try container.encode(tier, forKey: .tier)
        try container.encode(socialLinks, forKey: .socialLinks)
        try container.encode(notificationCount, forKey: .notificationCount)
        try container.encode(bio, forKey: .bio)
    }
}

struct SocialLink: Codable, Identifiable, Hashable {
    let id: String
    let platform: SocialPlatform
    let username: String
    let url: String

    // Add standard initializer
    init(id: String, platform: SocialPlatform, username: String, url: String) {
        self.id = id
        self.platform = platform
        self.username = username
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case id, platform, username, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        platform = try container.decode(SocialPlatform.self, forKey: .platform)
        username = try container.decode(String.self, forKey: .username)
        url = try container.decode(String.self, forKey: .url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(platform, forKey: .platform)
        try container.encode(username, forKey: .username)
        try container.encode(url, forKey: .url)
    }
}

enum SocialPlatform: String, Codable {
    case twitter = "Twitter"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"

    var icon: String {
        switch self {
        case .twitter: "bubble.left.and.bubble.right"
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .tiktok: "music.note"
        }
    }
}
