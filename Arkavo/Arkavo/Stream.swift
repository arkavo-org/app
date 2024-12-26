import AppIntents
import CryptoKit
import Foundation
import SwiftData

@Model
final class Stream: Identifiable, Hashable {
    @Attribute(.unique) private(set) var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var creatorPublicID: Data
    var profile: Profile
    var policies: Policies
    // sources[0] determines the type of Stream
    @Relationship(deleteRule: .cascade, inverse: \Thought.stream)
    var sources: [Thought] = []
    @Relationship(deleteRule: .cascade, inverse: \Thought.stream)
    var thoughts: [Thought] = []

    init(
        id: UUID = UUID(),
        publicID: Data? = nil,
        creatorPublicID: Data,
        profile: Profile,
        policies: Policies
    ) {
        self.id = id
        // Use provided publicID or generate new one
        self.publicID = publicID ?? Stream.generatePublicID(from: id)
        self.creatorPublicID = creatorPublicID
        self.profile = profile
        self.policies = policies
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    static func == (lhs: Stream, rhs: Stream) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(publicID)
    }
}

extension Stream {
    func addThought(_ thought: Thought) {
        if !thoughts.contains(where: { $0.id == thought.id }) {
            thoughts.append(thought)
            thought.stream = self
        }
    }

    func removeThought(_ thought: Thought) {
        thoughts.removeAll { $0.id == thought.id }
        if thought.stream === self {
            thought.stream = nil
        }
    }
}

struct Policies: Codable {
    var admission: AdmissionPolicy
    var interaction: InteractionPolicy
    var age: AgePolicy
}

enum AdmissionPolicy: String, Codable, CaseIterable {
    case open = "Open"
    case openInvitation = "Invitation"
    case openApplication = "Application"
    case closed = "Closed"
}

enum InteractionPolicy: String, Codable, CaseIterable {
    case open = "Open"
    case moderated = "Moderated"
    case closed = "Closed"
}

enum AgePolicy: String, Codable, CaseIterable {
    case onlyAdults = "Only Adults"
    case onlyKids = "Only Kids"
    case forAll = "For All"
    case onlyTeens = "Only Teens"
}

// MARK: - AppEntity Conformance

extension Stream: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stream"
    static var defaultQuery = StreamQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(profile.name)")
    }
}

struct StreamQuery: EntityQuery {
    typealias Entity = Stream

    func entities(for _: [Stream.ID]) async throws -> [Stream] {
        // Implement this method to fetch streams from your SwiftData store
        []
    }

    func suggestedEntities() async throws -> [Stream] {
        // Implement this method to fetch suggested streams from your SwiftData store
        []
    }
}
