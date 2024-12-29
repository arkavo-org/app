import CryptoKit
import Foundation
import SwiftData
import SwiftUICore

@Model
final class Profile: Identifiable {
    var id: UUID
    // Using SHA256 hash as a public identifier, stored as 32 bytes
    @Attribute(.unique) var publicID: Data
    var name: String
    var blurb: String?
    var interests: String = ""
    var location: String = ""
    var hasHighEncryption: Bool
    var hasHighIdentityAssurance: Bool
    // Optional properties for phased workflow
    @Attribute(.unique) var did: String?
    var handle: String?

    init(
        id: UUID = UUID(),
        name: String,
        blurb: String? = nil,
        interests: String = "",
        location: String = "",
        hasHighEncryption: Bool = false,
        hasHighIdentityAssurance: Bool = false
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.interests = interests
        self.location = location
        self.hasHighEncryption = hasHighEncryption
        self.hasHighIdentityAssurance = hasHighIdentityAssurance
        self.publicID = Profile.generatePublicID(from: id)
    }

    func finalizeRegistration(did: String, handle: String) {
        guard self.did == nil && self.handle == nil else {
            fatalError("Profile is already finalized.")
        }
        self.did = did
        self.handle = handle
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }
}
