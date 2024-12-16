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

    init(id: UUID = UUID(), nano: Data) {
        self.id = id
        publicID = Thought.generatePublicID(from: id)
        metadata = Thought.extractMetadata(from: nano)
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

    private static func extractMetadata(from _: Data) -> ThoughtMetadata {
        // TODO: Parse the data to extract metadata from the NanoTDF Policy
        ThoughtMetadata(creator: UUID(), mediaType: .text)
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
    let creator: UUID
    let mediaType: MediaType
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
