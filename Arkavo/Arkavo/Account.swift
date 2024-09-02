import CryptoKit
import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var dateCreated: Date
    var profile: Profile?
    var streams: [Stream] = []
    var attestationEnvelope: Data?

    init() {
        id = UUID()
        dateCreated = Date()
    }
}
