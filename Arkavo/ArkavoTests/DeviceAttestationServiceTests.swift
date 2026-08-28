import ArkavoSocial
import CryptoKit
import XCTest
@testable import Arkavo

@MainActor
final class DeviceAttestationServiceTests: XCTestCase {
    /// Snapshot of the real, shared-keychain slots this suite touches so
    /// `test_refreshAssertion_storesDeviceTokenNotHumanToken` can restore
    /// whatever a real signed-in device already had there.
    private var savedAuthToken: String?
    private var savedDeviceToken: (token: String, expiresAt: Date)?

    override func setUp() async throws {
        try await super.setUp()
        savedAuthToken = KeychainManager.getAuthenticationToken()
        savedDeviceToken = KeychainManager.getDeviceAttestationToken()
    }

    override func tearDown() async throws {
        if let savedAuthToken {
            try? KeychainManager.saveAuthenticationToken(savedAuthToken)
        } else {
            KeychainManager.deleteAuthenticationToken()
        }
        if let savedDeviceToken {
            try? KeychainManager.saveDeviceAttestationToken(savedDeviceToken.token, expiresAt: savedDeviceToken.expiresAt)
        } else {
            KeychainManager.deleteDeviceAttestationToken()
        }
        try await super.tearDown()
    }

    private func hash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    // MARK: - ensureAttested

    func test_ensureAttested_generatesKeyOnceAndPostsAttestation() async throws {
        let attest = MockAppAttest()
        let identity = MockDeviceCheckIdentity()
        identity.challenge = "attest-challenge"
        let box = InMemoryKeyIdBox()
        let store = DeviceKeyIdStore(get: { box.value }, save: { box.value = $0 }, delete: { box.value = nil })

        let service = DeviceAttestationService(
            attest: attest,
            identity: identity,
            username: { "alice" },
            keychain: store
        )

        try await service.ensureAttested()
        try await service.ensureAttested() // second call must be a no-op: key id already persisted

        XCTAssertEqual(attest.generateKeyCallCount, 1)
        XCTAssertEqual(identity.attestCalls.count, 1)
        XCTAssertEqual(identity.attestCalls.first?.keyId, attest.generatedKeyId)
        XCTAssertEqual(identity.attestCalls.first?.attestationObject, attest.attestationObject)
        XCTAssertEqual(identity.attestCalls.first?.clientDataHash, hash("attest-challenge"))
        XCTAssertEqual(box.value, attest.generatedKeyId)
    }

    // MARK: - refreshAssertion

    func test_refreshAssertion_storesDeviceTokenNotHumanToken() async throws {
        try KeychainManager.saveAuthenticationToken("human-fixture-token")
        KeychainManager.deleteDeviceAttestationToken()

        let attest = MockAppAttest()
        let identity = MockDeviceCheckIdentity()
        identity.assertChallenge = "assert-challenge"
        identity.assertToken = "device-cwt-fixture"
        let box = InMemoryKeyIdBox()
        box.value = "existing-key-id"
        let store = DeviceKeyIdStore(get: { box.value }, save: { box.value = $0 }, delete: { box.value = nil })

        let service = DeviceAttestationService(
            attest: attest,
            identity: identity,
            username: { "alice" },
            keychain: store
        )

        try await service.refreshAssertion()

        XCTAssertEqual(identity.assertCalls.count, 1)
        XCTAssertEqual(identity.assertCalls.first?.keyId, "existing-key-id")
        XCTAssertEqual(identity.assertCalls.first?.assertion, attest.assertionObject)
        XCTAssertEqual(identity.assertCalls.first?.clientDataHash, hash("assert-challenge"))

        XCTAssertEqual(KeychainManager.getAuthenticationToken(), "human-fixture-token", "Human CWT must be untouched")
        let deviceToken = KeychainManager.getDeviceAttestationToken()
        XCTAssertEqual(deviceToken?.token, "device-cwt-fixture")
        XCTAssertNotNil(deviceToken?.expiresAt)
    }

    func test_refreshAssertion_unknownKeyId_reattestsOnceThenSucceeds() async throws {
        let attest = MockAppAttest()
        attest.generatedKeyId = "brand-new-key-id"
        let identity = MockDeviceCheckIdentity()
        identity.assertErrorOnce = ArkavoIdentityError.notFound
        let box = InMemoryKeyIdBox()
        box.value = "stale-key-id"
        let store = DeviceKeyIdStore(get: { box.value }, save: { box.value = $0 }, delete: { box.value = nil })

        let service = DeviceAttestationService(
            attest: attest,
            identity: identity,
            username: { "alice" },
            keychain: store
        )

        try await service.refreshAssertion()

        // First assert attempt used the stale key id and failed with .notFound;
        // the service must clear it, re-attest to mint a fresh key id, and
        // retry the assertion exactly once more -- not loop indefinitely.
        XCTAssertEqual(identity.attestCalls.count, 1, "Should re-attest exactly once after an unknown key id")
        XCTAssertEqual(identity.assertCalls.count, 2, "First assert fails, second (post-reattest) succeeds")
        XCTAssertEqual(identity.assertCalls.last?.keyId, "brand-new-key-id")
        XCTAssertEqual(box.value, "brand-new-key-id")
    }

    // MARK: - unsupported device

    func test_unsupported_isNoOp() async throws {
        let attest = MockAppAttest()
        attest.isSupported = false
        let identity = MockDeviceCheckIdentity()
        let box = InMemoryKeyIdBox()
        let store = DeviceKeyIdStore(get: { box.value }, save: { box.value = $0 }, delete: { box.value = nil })

        let service = DeviceAttestationService(
            attest: attest,
            identity: identity,
            username: { "alice" },
            keychain: store
        )

        try await service.ensureAttested()
        try await service.refreshAssertion()

        XCTAssertEqual(attest.generateKeyCallCount, 0)
        XCTAssertEqual(identity.attestCalls.count, 0)
        XCTAssertEqual(identity.assertCalls.count, 0)
        XCTAssertNil(box.value)
    }
}

// MARK: - Test doubles

private final class InMemoryKeyIdBox: @unchecked Sendable {
    var value: String?
}

private final class MockAppAttest: AppAttestProviding, @unchecked Sendable {
    var isSupported = true
    var generatedKeyId = "mock-key-id"
    var attestationObject = Data("mock-attestation-object".utf8)
    var assertionObject = Data("mock-assertion-object".utf8)
    var generateKeyCallCount = 0
    var attestKeyCalls: [(keyId: String, clientDataHash: Data)] = []
    var generateAssertionCalls: [(keyId: String, clientDataHash: Data)] = []

    func generateKey() async throws -> String {
        generateKeyCallCount += 1
        return generatedKeyId
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestKeyCalls.append((keyId, clientDataHash))
        return attestationObject
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        generateAssertionCalls.append((keyId, clientDataHash))
        return assertionObject
    }
}

private final class MockDeviceCheckIdentity: DeviceCheckIdentity, @unchecked Sendable {
    var challenge = "challenge-uuid"
    var assertChallenge = "assert-challenge-uuid"
    var assertToken = "device-cwt-token"
    /// When set, the NEXT `deviceCheckAssert` call throws this once, then clears itself.
    var assertErrorOnce: Error?

    var attestCalls: [(keyId: String, attestationObject: Data, clientDataHash: Data)] = []
    var assertCalls: [(keyId: String, assertion: Data, clientDataHash: Data)] = []

    func deviceCheckChallenge(username: String) async throws -> String {
        challenge
    }

    func deviceCheckAttest(keyId: String, attestationObject: Data, clientDataHash: Data) async throws {
        attestCalls.append((keyId, attestationObject, clientDataHash))
    }

    func deviceCheckAssertChallenge(username: String) async throws -> String {
        assertChallenge
    }

    func deviceCheckAssert(keyId: String, assertion: Data, clientDataHash: Data) async throws -> String {
        assertCalls.append((keyId, assertion, clientDataHash))
        if let error = assertErrorOnce {
            assertErrorOnce = nil
            throw error
        }
        return assertToken
    }
}
