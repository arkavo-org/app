import CryptoKit
import Foundation
import SwiftData

@Model
final class Thought: Identifiable, Codable {
    // MARK: - Nested Types

    struct Metadata: Codable {
        let creator: UUID
        let streamPublicID: Data
        let mediaType: MediaType
        let createdAt: Date
        let summary: String
        let contributors: [Contributor]

        private static let decoder = PropertyListDecoder()
        private static let encoder: PropertyListEncoder = {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            return encoder
        }()

        func serialize() throws -> Data {
            try Metadata.encoder.encode(self)
        }

        static func deserialize(from data: Data) throws -> Metadata {
            try decoder.decode(Metadata.self, from: data)
        }
    }

    @Attribute(.unique) var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var stream: Stream?
    var metadata: Metadata
    var nano: Data

    init(id: UUID = UUID(), nano: Data, metadata: Metadata) {
        self.id = id
        publicID = Thought.generatePublicID(from: id)
        self.metadata = metadata
        self.nano = nano
    }

    // MARK: - Codable Conformance

    enum CodingKeys: String, CodingKey {
        case id, publicID, metadata, nano
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicID = try container.decode(Data.self, forKey: .publicID)
        metadata = try container.decode(Metadata.self, forKey: .metadata)
        nano = try container.decode(Data.self, forKey: .nano)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(publicID, forKey: .publicID)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(nano, forKey: .nano)
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }
}

extension Thought {
    func assignToStream(_ stream: Stream?) {
        if stream !== self.stream {
            self.stream?.thoughts.removeAll { $0.id == self.id }
            self.stream = stream
            stream?.thoughts.append(self)
        }
    }
}

// MARK: - Serialization

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

// MARK: - Contributor

struct Contributor: Codable, Identifiable {
    let id: String
    let creator: Creator
    let role: String
}

// MARK: - Creator

struct Creator: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: String
    let latestUpdate: String
    let tier: String
    let socialLinks: [SocialLink]
    let notificationCount: Int
    let bio: String
}

// MARK: - SocialLink

struct SocialLink: Codable, Identifiable, Hashable {
    let id: String
    let platform: SocialPlatform
    let username: String
    let url: String
}

// MARK: - SocialPlatform

enum SocialPlatform: String, Codable {
    case twitter = "Twitter"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"
}

// MARK: - MediaType

enum MediaType: String, Codable {
    case text, video, audio, image

    var icon: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        case .image: "photo.fill"
        case .text: "doc.fill"
        }
    }
}
