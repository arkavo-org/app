import AppIntents
import CryptoKit
import Foundation
import SwiftData

@Model
final class Stream: @unchecked Sendable {
    @Attribute(.unique) private(set) var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var creatorPublicID: Data
    var profile: Profile
    var admissionPolicy: AdmissionPolicy
    var interactionPolicy: InteractionPolicy
    var agePolicy: AgePolicy
    var thoughts: [Thought] = []

    init(id: UUID = UUID(), creatorPublicID: Data, profile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy, agePolicy: AgePolicy, thoughts: [Thought] = [], publicID: Data? = nil) {
        self.id = id
        self.creatorPublicID = creatorPublicID
        self.profile = profile
        self.admissionPolicy = admissionPolicy
        self.interactionPolicy = interactionPolicy
        self.agePolicy = agePolicy
        self.thoughts = thoughts
        if let publicID {
            self.publicID = publicID
        } else {
            self.publicID = Stream.generatePublicID(from: id)
        }
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }
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

extension Stream: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stream"
    static var defaultQuery = StreamQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(profile.name)")
    }

    static var typeDisplayName: String {
        "Stream"
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

struct StreamAppIntent: AppIntent {
    static var title: LocalizedStringResource = "View Secure Stream"

    @Parameter(title: "Stream ID")
    var streamIDString: String

    init() {}

    init(streamID: UUID) {
        streamIDString = streamID.uuidString
    }

    func perform() async throws -> some IntentResult {
        // Implement the actual functionality here
        .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("View the secure stream with ID \(\.$streamIDString)")
    }
}
