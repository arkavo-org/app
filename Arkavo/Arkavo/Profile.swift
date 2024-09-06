import Foundation
import SwiftData

@Model
final class Profile: Identifiable, Codable, @unchecked Sendable {
    var id: UUID
    var name: String
    var blurb: String?
    var dateCreated: Date
    var interests: String
    // add image, thumbnail

    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    init(id: UUID = UUID(), name: String, blurb: String? = nil, dateCreated: Date = Date(), interests: String = "") {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.dateCreated = dateCreated
        self.interests = interests
    }

    enum CodingKeys: String, CodingKey {
        case id, name, blurb, dateCreated, interests, ownerType, ownerId
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        interests = try container.decode(String.self, forKey: .interests)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(blurb, forKey: .blurb)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encodeIfPresent(interests, forKey: .interests)
    }

    func serialize() throws -> Data {
        try Profile.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> Profile {
        try decoder.decode(Profile.self, from: data)
    }
}
