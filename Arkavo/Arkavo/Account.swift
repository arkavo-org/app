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
    // TODO: add authentication level

    init(signPublicKey: P256.KeyAgreement.PublicKey, derivePublicKey: P256.KeyAgreement.PublicKey) {
        id = UUID()
        dateCreated = Date()
        signPublicKeyData = signPublicKey.rawRepresentation
        derivePublicKeyData = derivePublicKey.rawRepresentation
    }
}
