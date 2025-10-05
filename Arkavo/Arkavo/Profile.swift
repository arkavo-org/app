import CryptoKit
import Foundation
import SwiftData
import SwiftUI

@Model
final class Profile: Identifiable, Codable {
    var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var name: String
    var blurb: String?
    var interests: String = ""
    var location: String = ""
    var hasHighEncryption: Bool
    var hasHighIdentityAssurance: Bool
    // Optional properties for phased workflow
    @Attribute(.unique) var did: String?
    var handle: String?

    /// Stores the serialized public components of the *peer's* KeyStore, received during P2P key exchange.
    /// Used for operations requiring the peer's public keys (e.g., signature verification).
    /// Marked for external storage.
    @Attribute(.externalStorage) var keyStorePublic: Data?

    /// Stores the serialized private components of the *local user's* KeyStore, generated specifically
    /// for the P2P relationship with *this peer*. Used for operations requiring the local user's
    /// private keys in the context of this peer relationship (e.g., decryption, signing).
    /// Marked for external storage. This data is highly sensitive.
    @Attribute(.externalStorage) var keyStorePrivate: Data?

    // Default empty init required by SwiftData
    init() {
        let newID = UUID() // Generate UUID first
        id = newID
        name = "Default"
        // Initialize publicID temporarily, then generate from id
        publicID = Data()
        hasHighEncryption = false
        hasHighIdentityAssurance = false
        // Generate the publicID from the initialized id
        publicID = Profile.generatePublicID(from: newID)
        keyStorePublic = nil // Initialize new property
        keyStorePrivate = nil // Initialize new property
    }

    init(
        id: UUID = UUID(),
        name: String,
        blurb: String? = nil,
        interests: String = "",
        location: String = "",
        hasHighEncryption: Bool = false,
        hasHighIdentityAssurance: Bool = false
    ) {
        self.id = id // Use provided or default UUID
        self.name = name
        self.blurb = blurb
        self.interests = interests
        self.location = location
        self.hasHighEncryption = hasHighEncryption
        self.hasHighIdentityAssurance = hasHighIdentityAssurance
        // Generate publicID from the id
        publicID = Profile.generatePublicID(from: id)
        keyStorePublic = nil // Initialize new property
        keyStorePrivate = nil // Initialize new property
    }

    func finalizeRegistration(did: String, handle: String) {
        guard self.did == nil, self.handle == nil else {
            // Consider logging a warning or throwing an error instead of fatalError
            print("Warning: Profile \(publicID.base58EncodedString) is already finalized.")
            // fatalError("Profile is already finalized.")
            return // Allow idempotent calls
        }
        self.did = did
        self.handle = handle
    }

    // Generate publicID from the unique UUID
    private static func generatePublicID(from id: UUID) -> Data {
        withUnsafeBytes(of: id) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    // MARK: - Codable Conformance for Peer Exchange

    // Define coding keys, excluding relationships or non-essential data for exchange
    enum CodingKeys: String, CodingKey {
        case id
        case publicID
        case name
        case blurb
        case interests
        case location
        case hasHighEncryption
        case hasHighIdentityAssurance
        case did
        case handle
        // Do not include keyStorePublic or keyStorePrivate in peer exchange encoding.
        // These fields store relationship-specific keys managed via P2P KeyStoreShare messages.
    }

    // Encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(publicID, forKey: .publicID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(blurb, forKey: .blurb)
        try container.encode(interests, forKey: .interests)
        try container.encode(location, forKey: .location)
        try container.encode(hasHighEncryption, forKey: .hasHighEncryption)
        try container.encode(hasHighIdentityAssurance, forKey: .hasHighIdentityAssurance)
        try container.encodeIfPresent(did, forKey: .did)
        try container.encodeIfPresent(handle, forKey: .handle)
    }

    // Decoder (Required by Codable, used when creating from received data)
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicID = try container.decode(Data.self, forKey: .publicID)
        name = try container.decode(String.self, forKey: .name)
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
        interests = try container.decode(String.self, forKey: .interests)
        location = try container.decode(String.self, forKey: .location)
        hasHighEncryption = try container.decode(Bool.self, forKey: .hasHighEncryption)
        hasHighIdentityAssurance = try container.decode(Bool.self, forKey: .hasHighIdentityAssurance)
        did = try container.decodeIfPresent(String.self, forKey: .did)
        handle = try container.decodeIfPresent(String.self, forKey: .handle)
        // Initialize non-coded properties
        keyStorePublic = nil // Initialize new property
        keyStorePrivate = nil // Initialize new property
    }

    // MARK: - Serialization Helpers

    /// Serializes the profile to Data using JSONEncoder.
    /// Note: This serialization is intended for peer exchange and excludes sensitive key data.
    func toData() throws -> Data {
        let encoder = JSONEncoder()
        // Optional: Configure date encoding strategy if needed
        // encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Deserializes a Profile from Data using JSONDecoder.
    /// Note: This creates a new Profile instance, it doesn't update an existing one.
    /// It expects data conforming to the peer exchange format (excluding sensitive key data).
    static func fromData(_ data: Data) throws -> Profile {
        let decoder = JSONDecoder()
        // Optional: Configure date decoding strategy if needed
        // decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Profile.self, from: data)
    }
}
