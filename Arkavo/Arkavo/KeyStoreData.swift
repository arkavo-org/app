import Foundation
import OpenTDFKit // Import if KeyStore type is used directly, otherwise not needed
import SwiftData

// Forward declaration to break circular reference
// This is a simplified version without full details
protocol ProfileReference: AnyObject {
    var id: UUID { get }
    var publicID: Data { get }
}

@Model
final class KeyStoreData: Identifiable {
    @Attribute(.unique) var id: UUID // Unique ID for this data entry
    var serializedData: Data // The actual serialized KeyStore bytes
    var createdAt: Date
    var updatedAt: Date

    // Store the profile's public ID instead of direct relationship
    var profilePublicID: Data?

    // Relationship back to the Profile (assuming one-to-one)
    // Implemented through profile lookup by ID
    @Relationship(deleteRule: .nullify, inverse: \Profile.keyStoreData)
    var profile: Profile?

    // Curve used for the keys in this KeyStore (important for deserialization)
    // Store the raw value of the curve enum
    var keyCurveRawValue: String

    // Capacity of the KeyStore when it was created/serialized
    var capacity: Int

    // Computed property to get the curve value as found in OpenTDFKit
    // We will use enum from the Curve type as found in OpenTDFKit
    var keyCurve: Curve {
        Curve(rawValue: keyCurveRawValue) ?? .secp256r1 // Default to secp256r1
    }

    init(
        id: UUID = UUID(),
        profile: Profile? = nil,
        serializedData: Data,
        keyCurve: Curve,
        capacity: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profile = profile
        profilePublicID = profile?.publicID
        self.serializedData = serializedData
        keyCurveRawValue = keyCurve.rawValue
        self.capacity = capacity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Convenience method to deserialize the KeyStore
    // Note: This performs potentially heavy work, use appropriately.
    func deserializeKeyStore() async throws -> KeyStore {
        let keyStore = KeyStore(curve: keyCurve, capacity: capacity)
        try await keyStore.deserialize(from: serializedData)
        return keyStore
    }
}
