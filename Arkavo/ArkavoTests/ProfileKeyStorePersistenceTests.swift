@testable import Arkavo
import SwiftData
import XCTest

// MARK: - Mock PersistenceController

class MockPersistenceControllerForKeyStore: @unchecked Sendable {
    // Make savePeerProfile always succeed without context handling
    var savePeerProfileCalled = false
    var lastSavedProfile: Profile?
    var lastSavedPublicKeyStoreData: Data?
    var lastSavedPrivateKeyStoreData: Data?
    var shouldThrowError = false
    var mockError = NSError(domain: "MockPersistenceError", code: 1, userInfo: nil)

    // Dictionary to store profiles for testing
    var profileStore: [String: Profile] = [:]

    init() { /* Mock uses default property values */ }

    func savePeerProfile(_ peerProfile: Profile, keyStorePublicData: Data? = nil, keyStorePrivateData: Data? = nil) async throws {
        print("MockPersistenceController: savePeerProfile called for \(peerProfile.name)")

        if shouldThrowError {
            throw mockError
        }

        savePeerProfileCalled = true
        lastSavedProfile = peerProfile
        lastSavedPublicKeyStoreData = keyStorePublicData
        lastSavedPrivateKeyStoreData = keyStorePrivateData

        // Updated stored profile with new data
        let publicIDString = peerProfile.publicID.base58EncodedString
        profileStore[publicIDString] = peerProfile

        // Apply keyStore data to stored profile
        if let publicData = keyStorePublicData {
            profileStore[publicIDString]?.keyStorePublic = publicData
        }

        if let privateData = keyStorePrivateData {
            profileStore[publicIDString]?.keyStorePrivate = privateData
        }
    }

    func fetchProfile(withPublicID publicID: Data) async throws -> Profile? {
        let publicIDString = publicID.base58EncodedString
        return profileStore[publicIDString]
    }

    func deleteKeyStoreDataFor(profile: Profile) async throws {
        if shouldThrowError {
            throw mockError
        }

        let publicIDString = profile.publicID.base58EncodedString
        if var storedProfile = profileStore[publicIDString] {
            storedProfile.keyStorePublic = nil
            storedProfile.keyStorePrivate = nil
            profileStore[publicIDString] = storedProfile
        }
    }
}

// MARK: - Profile Key Store Persistence Tests

final class ProfileKeyStorePersistenceTests: XCTestCase {
    var mockPersistenceController: MockPersistenceControllerForKeyStore!
    var testProfile: Profile!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockPersistenceController = MockPersistenceControllerForKeyStore()
        testProfile = Profile(name: "Test Peer")

        // Add profile to store
        let publicIDString = testProfile.publicID.base58EncodedString
        mockPersistenceController.profileStore[publicIDString] = testProfile
    }

    override func tearDownWithError() throws {
        mockPersistenceController = nil
        testProfile = nil
        try super.tearDownWithError()
    }

    // MARK: - Test Cases

    @MainActor func testSavePeerProfileWithPublicKeyStore() async throws {
        // Arrange - Create test data
        let publicKeyData = "testPublicKeyStoreData".data(using: .utf8)!

        // Act - Save profile with public key store
        try await mockPersistenceController.savePeerProfile(testProfile, keyStorePublicData: publicKeyData)

        // Assert - Verify method was called correctly
        XCTAssertTrue(mockPersistenceController.savePeerProfileCalled)
        XCTAssertEqual(mockPersistenceController.lastSavedProfile?.publicID, testProfile.publicID)
        XCTAssertEqual(mockPersistenceController.lastSavedPublicKeyStoreData, publicKeyData)

        // Verify key data was stored on profile
        let publicIDString = testProfile.publicID.base58EncodedString
        let savedProfile = mockPersistenceController.profileStore[publicIDString]
        XCTAssertEqual(savedProfile?.keyStorePublic, publicKeyData)
    }

    @MainActor func testSavePeerProfileWithPrivateKeyStore() async throws {
        // Arrange - Create test data
        let privateKeyData = "testPrivateKeyStoreData".data(using: .utf8)!

        // Act - Save profile with private key store
        try await mockPersistenceController.savePeerProfile(testProfile, keyStorePrivateData: privateKeyData)

        // Assert - Verify method was called correctly
        XCTAssertTrue(mockPersistenceController.savePeerProfileCalled)
        XCTAssertEqual(mockPersistenceController.lastSavedProfile?.publicID, testProfile.publicID)
        XCTAssertEqual(mockPersistenceController.lastSavedPrivateKeyStoreData, privateKeyData)

        // Verify key data was stored on profile
        let publicIDString = testProfile.publicID.base58EncodedString
        let savedProfile = mockPersistenceController.profileStore[publicIDString]
        XCTAssertEqual(savedProfile?.keyStorePrivate, privateKeyData)
    }

    @MainActor func testSavePeerProfileWithBothKeyStores() async throws {
        // Arrange - Create test data
        let publicKeyData = "testPublicKeyStoreData".data(using: .utf8)!
        let privateKeyData = "testPrivateKeyStoreData".data(using: .utf8)!

        // Act - Save profile with both key stores
        try await mockPersistenceController.savePeerProfile(
            testProfile,
            keyStorePublicData: publicKeyData,
            keyStorePrivateData: privateKeyData,
        )

        // Assert - Verify method was called correctly
        XCTAssertTrue(mockPersistenceController.savePeerProfileCalled)
        XCTAssertEqual(mockPersistenceController.lastSavedProfile?.publicID, testProfile.publicID)
        XCTAssertEqual(mockPersistenceController.lastSavedPublicKeyStoreData, publicKeyData)
        XCTAssertEqual(mockPersistenceController.lastSavedPrivateKeyStoreData, privateKeyData)

        // Verify key data was stored on profile
        let publicIDString = testProfile.publicID.base58EncodedString
        let savedProfile = mockPersistenceController.profileStore[publicIDString]
        XCTAssertEqual(savedProfile?.keyStorePublic, publicKeyData)
        XCTAssertEqual(savedProfile?.keyStorePrivate, privateKeyData)
    }

    @MainActor func testDeleteKeyStoreData() async throws {
        // Arrange - Profile with key store data
        let publicKeyData = "testPublicKeyStoreData".data(using: .utf8)!
        let privateKeyData = "testPrivateKeyStoreData".data(using: .utf8)!

        try await mockPersistenceController.savePeerProfile(
            testProfile,
            keyStorePublicData: publicKeyData,
            keyStorePrivateData: privateKeyData,
        )

        let publicIDString = testProfile.publicID.base58EncodedString
        let profileBeforeDelete = mockPersistenceController.profileStore[publicIDString]
        XCTAssertNotNil(profileBeforeDelete?.keyStorePublic)
        XCTAssertNotNil(profileBeforeDelete?.keyStorePrivate)

        // Act - Delete key store data
        try await mockPersistenceController.deleteKeyStoreDataFor(profile: testProfile)

        // Assert - Verify key data was deleted
        let profileAfterDelete = mockPersistenceController.profileStore[publicIDString]
        XCTAssertNil(profileAfterDelete?.keyStorePublic)
        XCTAssertNil(profileAfterDelete?.keyStorePrivate)
    }

    @MainActor func testSavePeerProfileError() async {
        // Arrange - Set up error
        mockPersistenceController.shouldThrowError = true

        // Act & Assert - Verify error is thrown
        do {
            try await mockPersistenceController.savePeerProfile(
                testProfile,
                keyStorePublicData: "data".data(using: .utf8),
            )
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual(error as NSError, mockPersistenceController.mockError)
        }
    }
}
