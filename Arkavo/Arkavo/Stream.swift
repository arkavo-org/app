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
    // Make this optional to handle deserialization of existing store data
    var policies: Policies? = Policies(
        admission: .closed,
        interaction: .closed,
        age: .forAll
    )
    // InnerCircle profiles - direct profiles for members
    var innerCircleProfiles: [Profile] = []
    // Initial thought that determines stream type
    var source: Thought?
    @Relationship(deleteRule: .cascade, inverse: \Thought.stream)
    var thoughts: [Thought] = []

    // Default empty init required by SwiftData
    init() {
        id = UUID()
        publicID = Data()
        creatorPublicID = Data()
        profile = Profile(name: "Default")
        policies = Policies(
            admission: .closed,
            interaction: .closed,
            age: .forAll
        )
    }

    init(
        id: UUID = UUID(),
        publicID: Data? = nil,
        creatorPublicID: Data,
        profile: Profile,
        policies: Policies? = nil
    ) {
        self.id = id
        self.publicID = publicID ?? Stream.generatePublicID(from: id)
        self.creatorPublicID = creatorPublicID
        self.profile = profile
        if let policies {
            self.policies = policies
        }
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

    // InnerCircle management methods

    // Add a profile to the InnerCircle
    func addToInnerCircle(_ profile: Profile) {
        if !innerCircleProfiles.contains(where: { $0.id == profile.id }) {
            innerCircleProfiles.append(profile)
            // Update the last seen time
            profile.lastSeen = Date()
        }
    }

    // Remove a profile from the InnerCircle
    func removeFromInnerCircle(_ profile: Profile) {
        innerCircleProfiles.removeAll { $0.id == profile.id }
    }

    // Check if a profile is part of the InnerCircle
    func isInInnerCircle(_ profile: Profile) -> Bool {
        innerCircleProfiles.contains { $0.id == profile.id }
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

    var isInnerCircleStream: Bool {
        isGroupChatStream && profile.name == "InnerCircle"
    }

    var hasInnerCircleMembers: Bool {
        !innerCircleProfiles.isEmpty
    }

    // Safely access policies with a default if nil
    var policiesSafe: Policies {
        policies ?? Policies(
            admission: .closed,
            interaction: .closed,
            age: .forAll
        )
    }
}
