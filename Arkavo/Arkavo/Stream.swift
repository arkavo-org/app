import AppIntents
import Foundation
import SwiftData

final class Stream: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let ownerID: UUID
    let profile: Profile
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, ownerID, profile
    }

    init(id: UUID = UUID(), name: String, ownerID: UUID, profile: Profile) {
        self.id = id
        self.name = name
        createdAt = Date()
        updatedAt = Date()
        self.ownerID = ownerID
        self.profile = profile
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        ownerID = try container.decode(UUID.self, forKey: .ownerID)
        profile = try container.decode(Profile.self, forKey: .profile)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(profile, forKey: .profile)
    }

    func serialize() throws -> Data {
        try Stream.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> Stream {
        try decoder.decode(Stream.self, from: data)
    }
}

extension Stream: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stream"
    static var defaultQuery = StreamQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayName: String {
        "Stream"
    }
}

struct StreamQuery: EntityQuery {
    typealias Entity = Stream

    func entities(for _: [Stream.ID]) async throws -> [Stream] {
        // This is just a placeholder implementation
        []
    }

    func suggestedEntities() async throws -> [Stream] {
        // This is just a placeholder implementation
        []
    }
}

struct StreamAppIntent: AppIntent {
    static var title: LocalizedStringResource = "View Secure Stream"

    @Parameter(title: "Stream ID")
    var streamIDString: String

    init() {
        // AppIntent
    }

    init(streamID: UUID) {
        streamIDString = streamID.uuidString
    }

    func perform() async throws -> some IntentResult {
        // For now, we'll just return a success result
        .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("View the secure stream with ID \(\.$streamIDString)")
    }
}
