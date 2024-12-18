import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: Int
    var profile: Profile?
    var streams: [Stream] = []
    var _identityAssuranceLevel: String = IdentityAssuranceLevel.ial0.rawValue
    var _ageVerificationStatus: String = AgeVerificationStatus.unverified.rawValue

    init(id: Int = 0,
         profile: Profile? = nil,
         identityAssuranceLevel: IdentityAssuranceLevel = .ial0,
         ageVerificationStatus: AgeVerificationStatus = .unverified)
    {
        self.id = id
        self.profile = profile
        _identityAssuranceLevel = identityAssuranceLevel.rawValue
        _ageVerificationStatus = ageVerificationStatus.rawValue
    }

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
        100
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
        _ageVerificationStatus = status.rawValue
        if status == .verified {
            _identityAssuranceLevel = IdentityAssuranceLevel.ial1.rawValue
        }
    }

    enum StreamLimitError: Error {
        case exceededLimit
    }
}

// TODO: add Identity fields and authentication levels
