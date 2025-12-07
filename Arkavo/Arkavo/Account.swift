import ArkavoStore
import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: Int
    @Relationship(deleteRule: .cascade, inverse: \Profile.account)
    var profile: Profile?
    @Relationship(deleteRule: .cascade, inverse: \Stream.account)
    var streams: [Stream] = []
    var _identityAssuranceLevel: String = IdentityAssuranceLevel.ial0.rawValue
    var _ageVerificationStatus: String = AgeVerificationStatus.unverified.rawValue
    var _entitlementTier: String = EntitlementTier.low.rawValue

    init(id: Int = 0,
         profile: Profile? = nil,
         identityAssuranceLevel: IdentityAssuranceLevel = .ial0,
         ageVerificationStatus: AgeVerificationStatus = .unverified,
         entitlementTier: EntitlementTier = .low)
    {
        self.id = id
        self.profile = profile
        _identityAssuranceLevel = identityAssuranceLevel.rawValue
        _ageVerificationStatus = ageVerificationStatus.rawValue
        _entitlementTier = entitlementTier.rawValue
    }

    @Transient
    var identityAssuranceLevel: IdentityAssuranceLevel {
        get {
            IdentityAssuranceLevel(rawValue: _identityAssuranceLevel) ?? .ial0
        }
        set {
            _identityAssuranceLevel = newValue.rawValue
        }
    }

    @Transient
    var ageVerificationStatus: AgeVerificationStatus {
        get {
            AgeVerificationStatus(rawValue: _ageVerificationStatus) ?? .unverified
        }
        set {
            _ageVerificationStatus = newValue.rawValue
        }
    }

    @Transient
    var entitlementTier: EntitlementTier {
        get {
            EntitlementTier(rawValue: _entitlementTier) ?? .low
        }
        set {
            _entitlementTier = newValue.rawValue
        }
    }

    /// Encryption level based on entitlement tier
    @Transient
    var encryptionLevel: ArkavoStore.EncryptionLevel {
        entitlementTier.encryptionLevel
    }

    @Transient
    var streamLimit: Int {
        StreamConfiguration.streamLimit
    }

    /// Check if the account can create more streams
    var canCreateMoreStreams: Bool {
        streams.count < streamLimit
    }

    /// Update the entitlement tier
    func updateEntitlementTier(_ tier: EntitlementTier) {
        _entitlementTier = tier.rawValue
    }

    func addStream(_ stream: Stream) throws {
        guard streams.count < streamLimit else {
            throw StreamLimitError.exceededLimit(currentLimit: streamLimit)
        }
        guard let creatorPublicID = profile?.publicID else {
            throw StreamLimitError.noProfile
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

    enum StreamLimitError: Error, LocalizedError {
        case exceededLimit(currentLimit: Int)
        case noProfile

        var errorDescription: String? {
            switch self {
            case let .exceededLimit(currentLimit):
                "You've reached your limit of \(currentLimit) streams."
            case .noProfile:
                "No profile found. Please complete registration first."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .exceededLimit:
                nil
            case .noProfile:
                "Please restart the app and complete registration."
            }
        }
    }
}
