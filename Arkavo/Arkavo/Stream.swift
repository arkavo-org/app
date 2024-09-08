import AppIntents
import Foundation
import SwiftData

@Model
final class Stream: @unchecked Sendable {
    @Attribute(.unique) private(set) var id: UUID
    var account: Account
    var profile: Profile
    var admissionPolicy: AdmissionPolicy
    var interactionPolicy: InteractionPolicy

    init(id: UUID = UUID(), account: Account, profile: Profile, admissionPolicy: AdmissionPolicy, interactionPolicy: InteractionPolicy) {
        self.id = id
        self.account = account
        self.profile = profile
        self.admissionPolicy = admissionPolicy
        self.interactionPolicy = interactionPolicy
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
