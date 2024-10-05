import CryptoKit
import Foundation
import SwiftData
import SwiftUICore

@Model
final class Profile: Identifiable, Codable, @unchecked Sendable {
    var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var name: String
    var blurb: String?
    var interests: String
    var location: String
    var hasHighEncryption: Bool
    var hasHighIdentityAssurance: Bool

    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    init(id: UUID = UUID(), name: String, blurb: String? = nil, interests: String = "", location: String = "", hasHighEncryption: Bool = false, hasHighIdentityAssurance: Bool = false) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.interests = interests
        self.location = location
        self.hasHighEncryption = hasHighEncryption
        self.hasHighIdentityAssurance = hasHighIdentityAssurance
        publicID = Profile.generatePublicID(from: id)
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, publicID, name, blurb, interests, location, hasHighEncryption, hasHighIdentityAssurance, activityService
    }

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
    }

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
    }

    func serialize() throws -> Data {
        try Profile.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> Profile {
        try decoder.decode(Profile.self, from: data)
    }
}
