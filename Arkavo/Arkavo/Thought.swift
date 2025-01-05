import CryptoKit
import Foundation
import SwiftData

@Model
final class Thought: Identifiable, Codable {
    // MARK: - Nested Types

    struct Metadata: Codable {
        var creatorPublicID: Data
        let streamPublicID: Data
        let mediaType: MediaType
        let createdAt: Date
        @available(*, deprecated, message: "The summary field will be removed in a future version")
        var summary: String?
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
    var sourceStream: Stream?
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
    let profilePublicID: Data
    let role: String

    var id: String {
        "\(profilePublicID.base58EncodedString)-\(role)"
    }
}

// MARK: - Creator

@available(*, deprecated, message: "The `Creator` struct is deprecated. Use `Profile` instead")
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

// for transmission, serializes to payload
struct ThoughtServiceModel: Codable {
    var publicID: Data
    var creatorPublicID: Data
    var streamPublicID: Data
    var mediaType: MediaType
    var content: Data

    init(creatorPublicID: Data, streamPublicID: Data, mediaType: MediaType, content: Data) {
        self.creatorPublicID = creatorPublicID
        self.streamPublicID = streamPublicID
        self.mediaType = mediaType
        self.content = content
        let hashData = creatorPublicID + streamPublicID + content
        publicID = SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }
    }
}

extension ThoughtServiceModel {
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
        try ThoughtServiceModel.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> ThoughtServiceModel {
        try decoder.decode(ThoughtServiceModel.self, from: data)
    }
}

extension Thought {
    static func from(_ model: ThoughtServiceModel, arkavoMetadata: Arkavo_Metadata) throws -> Thought {
        // Get creator UUID from model's creatorPublicID
        // This assumes the creatorPublicID is a SHA256 hash of the UUID
        guard model.creatorPublicID.count == 32 else {
            throw NSError(domain: "Thought", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid creator public ID length"])
        }

        // Create metadata using Arkavo metadata and model data
        let metadata = try Metadata.from(
            arkavoMetadata,
            model: model
        )

        // Create nano TDF data from content
        let nano = model.content

        // Create the thought
        return Thought(nano: nano, metadata: metadata)
    }
}

extension Thought.Metadata {
    // Create Thought.Metadata from Arkavo_Metadata
    static func from(_ arkavoMetadata: Arkavo_Metadata, model: ThoughtServiceModel) throws -> Thought.Metadata {
        // Extract creation date
        let createdAt = Date(timeIntervalSince1970: TimeInterval(arkavoMetadata.created))

        // Determine media type from content format
        let mediaType: MediaType = if let content = arkavoMetadata.content {
            switch content.mediaType {
            case .video: .video
            case .audio: .audio
            case .image: .image
            default: .text
            }
        } else {
            .text // Default to text if no content format
        }

        // Create summary from purpose if available
        let summary: String
        if let purpose = arkavoMetadata.purpose {
            let purposes = [
                (purpose.educational, "Educational"),
                (purpose.entertainment, "Entertainment"),
                (purpose.news, "News"),
                (purpose.promotional, "Promotional"),
                (purpose.personal, "Personal"),
                (purpose.opinion, "Opinion"),
            ]
            let mainPurpose = purposes.max(by: { $0.0 < $1.0 })?.1 ?? "General"
            summary = "\(mainPurpose) content"
        } else {
            summary = "Content"
        }

        // For now, using empty contributors array
        let contributors: [Contributor] = []

        return Thought.Metadata(
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: mediaType,
            createdAt: createdAt,
            summary: summary,
            contributors: contributors
        )
    }
}
