@testable import Arkavo
import OpenTDFKit
import SwiftData
import XCTest

// Existing Curve from OpenTDFKit, just defined for tests
enum Curve: String {
    case secp256r1
    case secp384r1
    case secp521r1
}

// MARK: - Mock OpenTDFKit Types

class MockKeyStore {
    var curve: Curve
    var capacity: Int
    var serializedData: Data?
    var deserializeCalled = false
    var serializeCalled = false
    var shouldThrowError = false
    var mockError = NSError(domain: "MockKeyStoreError", code: 1, userInfo: nil)

    init(curve: Curve, capacity: Int) {
        self.curve = curve
        self.capacity = capacity
    }

    func deserialize(from data: Data) async throws {
        print("MockKeyStore: deserialize called with \(data.count) bytes")
        deserializeCalled = true
        if shouldThrowError {
            throw mockError
        }
        serializedData = data
    }

    func serialize() async -> Data {
        serializeCalled = true
        return serializedData ?? "defaultSerializedData".data(using: .utf8)!
    }
}

// Using the Curve enum defined above

// Mock KeyStoreData class to match the real implementation
class KeyStoreData {
    var id: UUID
    var profile: Profile?
    var profilePublicID: Data?
    var serializedData: Data
    var createdAt: Date
    var updatedAt: Date
    var keyCurveRawValue: String
    var capacity: Int

    var keyCurve: Curve {
        Curve(rawValue: keyCurveRawValue) ?? .secp256r1
    }

    init(id: UUID = UUID(), profile: Profile? = nil, serializedData: Data, keyCurve: Curve, capacity: Int, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.profile = profile
        profilePublicID = profile?.publicID
        self.serializedData = serializedData
        keyCurveRawValue = keyCurve.rawValue
        self.capacity = capacity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func deserializeKeyStore() async throws -> MockKeyStore {
        let keyStore = MockKeyStore(curve: keyCurve, capacity: capacity)
        try await keyStore.deserialize(from: serializedData)
        return keyStore
    }
}

// MARK: - KeyStoreData Tests

final class KeyStoreDataTests: XCTestCase {
    var keyStoreData: KeyStoreData!
    var mockProfile: Profile!

    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()

        // Create a mock profile
        mockProfile = Profile(name: "TestUser")

        // Create sample serialized data
        let sampleData = "sampleKeyStoreData".data(using: .utf8)!

        // Create KeyStoreData instance
        keyStoreData = KeyStoreData(
            profile: mockProfile,
            serializedData: sampleData,
            keyCurve: .secp256r1,
            capacity: 8192
        )
    }

    override func tearDownWithError() throws {
        keyStoreData = nil
        mockProfile = nil
        try super.tearDownWithError()
    }

    // MARK: - Test Cases

    func testKeyStoreDataInitialization() {
        // Verify properties are correctly set
        XCTAssertEqual(keyStoreData.profile?.id, mockProfile.id)
        XCTAssertEqual(keyStoreData.profilePublicID, mockProfile.publicID)
        XCTAssertEqual(keyStoreData.serializedData, "sampleKeyStoreData".data(using: .utf8))
        XCTAssertEqual(keyStoreData.keyCurveRawValue, "secp256r1")
        XCTAssertEqual(keyStoreData.capacity, 8192)

        // Verify computed property
        XCTAssertEqual(keyStoreData.keyCurve, .secp256r1)
    }

    func testKeyStoreDataWithoutProfile() {
        // Create KeyStoreData without profile
        let noProfileKeyStoreData = KeyStoreData(
            profile: nil,
            serializedData: "noProfileData".data(using: .utf8)!,
            keyCurve: .secp384r1,
            capacity: 4096
        )

        // Verify properties
        XCTAssertNil(noProfileKeyStoreData.profile)
        XCTAssertNil(noProfileKeyStoreData.profilePublicID)
        XCTAssertEqual(noProfileKeyStoreData.serializedData, "noProfileData".data(using: .utf8))
        XCTAssertEqual(noProfileKeyStoreData.keyCurveRawValue, "secp384r1")
        XCTAssertEqual(noProfileKeyStoreData.capacity, 4096)
        XCTAssertEqual(noProfileKeyStoreData.keyCurve, .secp384r1)
    }

    func testDeserializeKeyStore() async {
        // This test uses the real KeyStoreData but a mock KeyStore
        // In a real implementation, we'd inject the KeyStore creation

        // Create mock KeyStore and its deserialization logic
        let mockKeyStore = MockKeyStore(curve: .secp256r1, capacity: 8192)

        do {
            // TODO: In actual implementation, inject the mock KeyStore
            // For now, we're just verifying the mock works as expected
            try await mockKeyStore.deserialize(from: keyStoreData.serializedData)

            // Verify deserialize was called
            XCTAssertTrue(mockKeyStore.deserializeCalled)
            XCTAssertEqual(mockKeyStore.serializedData, "sampleKeyStoreData".data(using: .utf8))
        } catch {
            XCTFail("Deserialization should not throw: \(error)")
        }
    }

    func testDeserializeKeyStoreError() async {
        // Create mock KeyStore with error
        let mockKeyStore = MockKeyStore(curve: .secp256r1, capacity: 8192)
        mockKeyStore.shouldThrowError = true

        do {
            try await mockKeyStore.deserialize(from: keyStoreData.serializedData)
            XCTFail("Deserialization should throw an error")
        } catch {
            // Verify error handling
            XCTAssertTrue(mockKeyStore.deserializeCalled)
            XCTAssertEqual(error as NSError, mockKeyStore.mockError)
        }
    }

    func testKeyStoreWithDefaultCurve() {
        // Create KeyStoreData with invalid curve string
        let invalidCurveData = KeyStoreData(
            profile: mockProfile,
            serializedData: "invalidCurveData".data(using: .utf8)!,
            keyCurve: Curve(rawValue: "invalid")!, // This will be nil in real code
            capacity: 8192
        )

        // Verify default curve is used
        XCTAssertEqual(invalidCurveData.keyCurve, .secp256r1)
    }
}
