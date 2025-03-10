import AppIntents
import CryptoKit
import Foundation
import SwiftData

@Model
final class Stream: Identifiable, Hashable, @unchecked Sendable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var publicID: Data
    var creatorPublicID: Data
    var profile: Profile
    var policies: Policies
    // Initial thought that determines stream type
    var source: Thought?
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
        lhs.publicID == rhs.publicID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(publicID)
    }
}

extension Stream {
    // Adding a thought should add to thoughts array, not sources
    func addThought(_ thought: Thought) {
        // Never add to sources array when adding a thought
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

extension Stream {
    var isGroupChatStream: Bool {
        // A group chat stream has no initial thought/sources
        source == nil
    }
}
