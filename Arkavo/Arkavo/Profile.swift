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
        self.id = UUID()
        self.name = "Default"
        self.publicID = Data()  // Initialize with empty data first
        self.hasHighEncryption = false
        self.hasHighIdentityAssurance = false
        // Update publicID after all properties are initialized
        let nameData = self.name.data(using: .utf8) ?? Data()
        self.publicID = Data(SHA256.hash(data: nameData))
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
        self.id = id
        self.name = name
        self.blurb = blurb
        self.interests = interests
        self.location = location
        self.hasHighEncryption = hasHighEncryption
        self.hasHighIdentityAssurance = hasHighIdentityAssurance
        publicID = Profile.generatePublicID(from: name)
    }

    func finalizeRegistration(did: String, handle: String) {
        guard self.did == nil, self.handle == nil else {
            fatalError("Profile is already finalized.")
        }
        self.did = did
        self.handle = handle
    }

    // FIXME: should really be handle
    private static func generatePublicID(from name: String) -> Data {
        // Ensure consistent string encoding
        guard let nameData = name.data(using: .utf8) else {
            fatalError("Failed to encode name as UTF-8")
        }
        return Data(SHA256.hash(data: nameData))
    }
}
