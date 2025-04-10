import CryptoKit
import Foundation
import SwiftData

@Model
final class Thought: Identifiable { // Removed Codable conformance
    // MARK: - Nested Types

    struct Metadata: Codable { // Still Codable for SwiftData storage
        var creatorPublicID: Data
        let streamPublicID: Data
        let mediaType: MediaType // Kind
        let createdAt: Date
        let contributors: [Contributor]

        // Removed serialize/deserialize and encoder/decoder from Metadata
    }

    @Attribute(.unique) var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var stream: Stream?
    var metadata: Metadata
    var nano: Data // Represents the content payload (e.g., for NanoTDF)

    // Default empty init required by SwiftData
    init() {
        id = UUID()
        publicID = Data() // Initialize with empty data first
        nano = Data()
        metadata = Metadata(
            creatorPublicID: Data(),
            streamPublicID: Data(),
            mediaType: .text,
            createdAt: Date(),
            contributors: []
        )
        // Update publicID after all properties are initialized
        publicID = withUnsafeBytes(of: id) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    init(id: UUID = UUID(), nano: Data, metadata: Metadata) {
        self.id = id
        publicID = Thought.generatePublicID(from: id)
        self.metadata = metadata
        self.nano = nano
    }

    // Removed explicit Codable conformance (CodingKeys, init(from:), encode(to:))

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

    // Added convenience accessor for publicID string representation
    var publicIDString: String {
        publicID.base58EncodedString
    }
}

// Removed the separate Serialization extension for Thought

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
    case text, video, audio, image, post, say

    var icon: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        case .image: "photo.fill"
        case .text: "doc.fill"
        case .post: "post.fill"
        case .say: "speaker.fill"
        }
    }
}

// MARK: - ThoughtServiceModel (DTO for Network/Serialization)

struct ThoughtServiceModel: Codable {
    var publicID: Data
    var creatorPublicID: Data
    var streamPublicID: Data
    var mediaType: MediaType
    var content: Data // This is the payload for NanoTDF

    // Original initializer (if needed for creating directly)
    init(creatorPublicID: Data, streamPublicID: Data, mediaType: MediaType, content: Data) {
        self.creatorPublicID = creatorPublicID
        self.streamPublicID = streamPublicID
        self.mediaType = mediaType
        self.content = content
        // Calculate publicID based on content hash if required by service definition
        let hashData = creatorPublicID + streamPublicID + content
        publicID = SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }
    }

    // Note: The publicID calculation above might differ from the Thought's publicID (which is based on UUID).
    // Decide if the service model should use the Thought's publicID or generate its own.
    // The new init(from thought: Thought) below uses the Thought's publicID.
}

extension ThoughtServiceModel {
    // Keep encoder/decoder and serialize/deserialize specific to the service model
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

    // NEW Initializer to convert from Thought model to Service model
    init(from thought: Thought) {
        // Use the Thought's existing publicID for the service model
        publicID = thought.publicID
        creatorPublicID = thought.metadata.creatorPublicID
        streamPublicID = thought.metadata.streamPublicID
        mediaType = thought.metadata.mediaType
        content = thought.nano // Map 'nano' to 'content' for the service model
    }
}

// Keep the conversion from Service Model back to Thought Model
extension Thought {
    // This function likely needs adjustment based on how Arkavo_Metadata relates
    // to ThoughtServiceModel now. Assuming ThoughtServiceModel is the primary input.
    static func from(_ model: ThoughtServiceModel) throws -> Thought {
        // We need to reconstruct the Metadata struct from the service model fields
        // This might require fetching contributor info or making assumptions.
        // Example reconstruction (adjust based on actual requirements):
        let contributor = Contributor(profilePublicID: model.creatorPublicID, role: "creator")
        let metadata = Metadata(
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: model.mediaType,
            createdAt: Date(), // Might need timestamp from service model if available
            contributors: [contributor]
        )

        let nano = model.content

        // Create the Thought instance. The publicID will be regenerated based on UUID.
        // If you need the publicID to match the service model exactly,
        // you might need a different init or assignment strategy.
        return Thought(nano: nano, metadata: metadata)
    }

    // Original 'from' method might be deprecated or adapted if Arkavo_Metadata is still used elsewhere
    // static func from(_ model: ThoughtServiceModel, arkavoMetadata: Arkavo_Metadata) throws -> Thought { ... }
}

// Keep Metadata conversion if needed elsewhere, but it's not used by Thought directly for Codable now
// If Arkavo_Metadata is defined elsewhere (e.g., EntityServiceModel.swift), this extension might need to be moved or adapted.
/*
 extension Thought.Metadata {
     // Assuming Arkavo_Metadata is a separate Protobuf or similar structure
     static func from(_ arkavoMetadata: Arkavo_Metadata) throws -> Thought.Metadata {
         let createdAt = Date(timeIntervalSince1970: TimeInterval(arkavoMetadata.created))

         // Map Arkavo_MediaType to MediaType
         let mediaType: MediaType = if let arkavoMediaType = arkavoMetadata.content?.mediaType {
             switch arkavoMediaType {
             case .video: .video
             case .audio: .audio
             case .image: .image
             default: .text
             }
         } else {
             .text // Default to text if no media type is provided
         }

         let contributor = Contributor(profilePublicID: Data(arkavoMetadata.creator), role: "creator")

         return Thought.Metadata(
             creatorPublicID: Data(arkavoMetadata.creator),
             streamPublicID: Data(arkavoMetadata.related),
             mediaType: mediaType,
             createdAt: createdAt,
             contributors: [contributor]
         )
     }
 }
 */

// Removed placeholder definitions for Arkavo_Metadata, Arkavo_ContentMetadata, Arkavo_MediaType
