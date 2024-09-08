import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: Int
    var profile: Profile?
    var authenticationToken: String?
    var streams: [Stream] = []
    var streamLimit: Int {
        // TODO: handle feature payment for more
        10
    }

    init(id: Int = 0, profile: Profile? = nil, authenticationToken: String? = nil) {
        self.id = id // There should only ever be one account with id 0
        self.profile = profile
        self.authenticationToken = authenticationToken
    }

    func addStream(_ stream: Stream) throws {
        guard streams.count < streamLimit else {
            throw StreamLimitError.exceededLimit
        }
        stream.account = self
        streams.append(stream)
    }

    enum StreamLimitError: Error {
        case exceededLimit
    }
}

// TODO: add Identity fields and authentication levels
