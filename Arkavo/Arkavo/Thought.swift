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

// MARK: - ThoughtServiceModel

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
        guard model.creatorPublicID.count == 32 else {
            throw NSError(domain: "Thought", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid creator public ID length"])
        }

        let metadata = try Metadata.from(arkavoMetadata)
        let nano = model.content

        return Thought(nano: nano, metadata: metadata)
    }
}

extension Thought.Metadata {
    static func from(_ arkavoMetadata: Arkavo_Metadata) throws -> Thought.Metadata {
        let createdAt = Date(timeIntervalSince1970: TimeInterval(arkavoMetadata.created))

        // Map Arkavo_MediaType to MediaType
        let mediaType: MediaType = if let arkavoMediaType = arkavoMetadata.content?.mediaType {
            switch arkavoMediaType {
            case .video:
                .video
            case .audio:
                .audio
            case .image:
                .image
            default:
                .text
            }
        } else {
            .text // Default to text if no media type is provided
        }

        return Thought.Metadata(
            creatorPublicID: Data(arkavoMetadata.creator),
            streamPublicID: Data(arkavoMetadata.related),
            mediaType: mediaType,
            createdAt: createdAt,
            contributors: []
        )
    }
}
