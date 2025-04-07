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

    // Default empty init required by SwiftData
    init() {
        let newID = UUID() // Generate UUID first
        self.id = newID
        self.name = "Default"
        // Initialize publicID temporarily, then generate from id
        self.publicID = Data()
        self.hasHighEncryption = false
        self.hasHighIdentityAssurance = false
        // Generate the publicID from the initialized id
        self.publicID = Profile.generatePublicID(from: newID)
    }

    init(
        id: UUID = UUID(),
        name: String,
        blurb: String? = nil,
        interests: String = "",
        location: String = "",
        hasHighEncryption: Bool = false,
        hasHighIdentityAssurance: Bool = false
    ) {
        self.id = id // Use provided or default UUID
        self.name = name
        self.blurb = blurb
        self.interests = interests
        self.location = location
        self.hasHighEncryption = hasHighEncryption
        self.hasHighIdentityAssurance = hasHighIdentityAssurance
        // Generate publicID from the id
        self.publicID = Profile.generatePublicID(from: id)
    }

    func finalizeRegistration(did: String, handle: String) {
        guard self.did == nil, self.handle == nil else {
            fatalError("Profile is already finalized.")
        }
        self.did = did
        self.handle = handle
    }

    // Generate publicID from the unique UUID
    private static func generatePublicID(from id: UUID) -> Data {
        withUnsafeBytes(of: id) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }
}
