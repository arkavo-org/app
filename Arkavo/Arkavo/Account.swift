import Foundation
import SwiftData
import CryptoKit

@Model
final class Account {
    var id: UUID
    var dateCreated: Date
    var signPublicKeyData: Data
    var derivePublicKeyData: Data
    var profiles: [Profile] = []
    
    init(signPublicKey: P256.KeyAgreement.PublicKey, derivePublicKey: P256.KeyAgreement.PublicKey) {
        self.id = UUID()
        self.dateCreated = Date()
        self.signPublicKeyData = signPublicKey.rawRepresentation
        self.derivePublicKeyData = derivePublicKey.rawRepresentation
    }
}
