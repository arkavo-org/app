import CryptoKit
import Foundation
import SwiftData

@Model
final class Thought: Identifiable, Codable, @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicId: Data
    var stream: Stream?
    var metadata: ThoughtMetadata
    var nano: Data

    init(id: UUID = UUID(), nano: Data) {
        self.id = id
        publicId = Thought.generatePublicIdentifier(from: id)
        metadata = Thought.extractMetadata(from: nano)
        self.nano = nano
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicId = try container.decode(Data.self, forKey: .publicId)
        metadata = try container.decode(ThoughtMetadata.self, forKey: .metadata)
        nano = try container.decode(Data.self, forKey: .nano)
    }

    enum CodingKeys: String, CodingKey {
        case id, publicId, metadata, nano
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(publicId, forKey: .publicId)
        try container.encode(metadata, forKey: .metadata)
    }

    private static func extractMetadata(from _: Data) -> ThoughtMetadata {
        // TODO: Parse the data to extract metadata from the NanoTDF Policy
        ThoughtMetadata(creator: UUID(), mediaType: .text)
    }

    private static func generatePublicIdentifier(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    /// decode from hex back to 32 bytes Data
    public static func decodePublicIdentifier(from string: String) throws -> Data {
        if string.count != 64 {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Hex string should be 64 characters long."
                )
            )
        }
        var data = Data()
        var hexString = string
        while hexString.count > 0 {
            let subIndex = hexString.index(hexString.startIndex, offsetBy: 2)
            let byteString = String(hexString[..<subIndex])
            hexString = String(hexString[subIndex...])

            if let num = UInt8(byteString, radix: 16) {
                data.append(num)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Invalid hex byte: \(byteString)"
                    )
                )
            }
        }
        return data
    }
}

extension Thought {
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    var publicIdString: String {
        publicId.map { String(format: "%02x", $0) }.joined()
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

enum MediaType: String, Codable {
    case text
    case image
    case audio
    case video
}
