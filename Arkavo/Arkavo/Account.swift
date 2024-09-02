import SwiftData
import Foundation

@Model
final class Account {
    @Attribute(.unique) let id: Int
    var dateCreated: Date
    var profile: Profile?
    var streams: [Stream] = []
    var attestationEnvelope: Data?

    init() {
        id = 0  // There should only ever be one account with id 0
        dateCreated = Date()
    }
}
