import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: Int
    var profile: Profile?
    var authenticationToken: String?
    var streams: [Stream] = []
    var _identityAssuranceLevel: String = IdentityAssuranceLevel.ial0.rawValue
    var _ageVerificationStatus: String = AgeVerificationStatus.unverified.rawValue

    // Computed properties for type-safe enum access
    var identityAssuranceLevel: IdentityAssuranceLevel {
        get {
            IdentityAssuranceLevel(rawValue: _identityAssuranceLevel) ?? .ial0
        }
        set {
            _identityAssuranceLevel = newValue.rawValue
        }
    }

    var ageVerificationStatus: AgeVerificationStatus {
        get {
            AgeVerificationStatus(rawValue: _ageVerificationStatus) ?? .unverified
        }
        set {
            _ageVerificationStatus = newValue.rawValue
        }
    }

    var streamLimit: Int {
        // TODO: handle feature payment for more
        10
    }

    init(id: Int = 0,
         profile: Profile? = nil,
         authenticationToken: String? = nil,
         identityAssuranceLevel: IdentityAssuranceLevel = .ial0,
         ageVerificationStatus: AgeVerificationStatus = .unverified)
    {
        self.id = id // There should only ever be one account with id 0
        self.profile = profile
        self.authenticationToken = authenticationToken
        _identityAssuranceLevel = identityAssuranceLevel.rawValue
        _ageVerificationStatus = ageVerificationStatus.rawValue
    }

    func addStream(_ stream: Stream) throws {
        guard streams.count < streamLimit,
              let creatorPublicID = profile?.publicID
        else {
            throw StreamLimitError.exceededLimit
        }
        stream.creatorPublicID = creatorPublicID
        streams.append(stream)
    }

    func updateVerificationStatus(_ status: AgeVerificationStatus) {
        ageVerificationStatus = status
        if status == .verified {
            identityAssuranceLevel = .ial2
        }
    }

    enum StreamLimitError: Error {
        case exceededLimit
    }
}

// TODO: add Identity fields and authentication levels
