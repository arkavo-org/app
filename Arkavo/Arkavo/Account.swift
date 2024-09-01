import CryptoKit
import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID
    var dateCreated: Date
    var signPublicKeyData: Data
    var derivePublicKeyData: Data
    var profile: Profile?
    var streams: [Stream] = []
    @Relationship(deleteRule: .cascade) var attestationEnvelope: AttestationEnvelope?
    // TODO: add authentication level

    init(signPublicKey: P256.KeyAgreement.PublicKey, derivePublicKey: P256.KeyAgreement.PublicKey) {
        id = UUID()
        dateCreated = Date()
        signPublicKeyData = signPublicKey.rawRepresentation
        derivePublicKeyData = derivePublicKey.rawRepresentation
    }
}

@Model
final class AttestationEnvelope {
    @Attribute(.unique) var id: UUID
    var signature: String
    @Relationship(deleteRule: .cascade) var payload: AttestationEntity

    init(payload: AttestationEntity, signature: String) {
        self.id = UUID()
        self.payload = payload
        self.signature = signature
    }
}

@Model
final class AttestationEntity {
    @Attribute(.unique) var id: UUID
    var credentialId: String
    var userUniqueId: String

    init(credentialId: String, userUniqueId: String) {
        self.id = UUID()
        self.credentialId = credentialId
        self.userUniqueId = userUniqueId
    }
}
