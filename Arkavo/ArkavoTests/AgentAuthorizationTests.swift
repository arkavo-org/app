import XCTest
@testable import Arkavo
import ArkavoAgent
import ArkavoSocial

final class AgentAuthorizationTests: XCTestCase {

    // MARK: - URL Parsing Tests

    func test_parseURL_extractsRPCEndpoint() throws {
        let url = URL(string: "arkavo://agent/authorize?did=did:key:z6Mk123&name=TestAgent&rpc=ws%3A%2F%2F192.168.1.100%3A8342")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        let request = AgentAuthorizationRequest.from(components: components)

        XCTAssertNotNil(request, "Request should be created")
        XCTAssertEqual(request?.rpcEndpoint, "ws://192.168.1.100:8342")
    }

    func test_parseURL_rpcEndpointIsOptional() throws {
        let url = URL(string: "arkavo://agent/authorize?did=did:key:z6Mk123&name=TestAgent")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        let request = AgentAuthorizationRequest.from(components: components)

        XCTAssertNotNil(request, "Request should be created without rpc parameter")
        XCTAssertNil(request?.rpcEndpoint, "RPC endpoint should be nil when not present")
    }

    func test_parseURL_extractsAllFields() throws {
        let url = URL(string: "arkavo://agent/authorize?did=did:key:z6MkTest&name=MyAgent&entitlements=chat,tools&rpc=ws%3A%2F%2Flocalhost%3A8080")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        let request = AgentAuthorizationRequest.from(components: components)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.did, "did:key:z6MkTest")
        XCTAssertEqual(request?.name, "MyAgent")
        XCTAssertEqual(request?.entitlements, ["chat", "tools"])
        XCTAssertEqual(request?.rpcEndpoint, "ws://localhost:8080")
    }

    func test_parseURL_handlesSecureWebSocket() throws {
        let url = URL(string: "arkavo://agent/authorize?did=did:key:z6MkTest&rpc=wss%3A%2F%2Fsecure.example.com%3A443")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!

        let request = AgentAuthorizationRequest.from(components: components)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.rpcEndpoint, "wss://secure.example.com:443")
    }

    // MARK: - RPC Registration Service Tests

    func test_rpcRegistration_buildsCorrectChallengeRequest() async throws {
        let mockTransport = MockAgentWebSocketTransport()
        mockTransport.challengeResponse = [
            "challenge_id": "test-challenge-123",
            "challenge": "dGVzdC1jaGFsbGVuZ2UtZGF0YQ==" // base64 of "test-challenge-data"
        ]
        mockTransport.verifyResponse = ["success": true]

        let service = AgentRPCRegistrationService(transport: mockTransport)

        _ = try await service.register(deviceId: "did:key:z6MkTestDevice")

        XCTAssertEqual(mockTransport.lastChallengeMethod, "registration.challenge")
        XCTAssertEqual(mockTransport.lastChallengeDeviceId, "did:key:z6MkTestDevice")
    }

    func test_rpcRegistration_buildsCorrectVerifyRequest() async throws {
        let mockTransport = MockAgentWebSocketTransport()
        mockTransport.challengeResponse = [
            "challenge_id": "verify-test-123",
            "challenge": "dGVzdA==" // base64 of "test"
        ]
        mockTransport.verifyResponse = ["success": true]

        let service = AgentRPCRegistrationService(transport: mockTransport)

        _ = try await service.register(deviceId: "did:key:z6MkTestDevice")

        XCTAssertEqual(mockTransport.lastVerifyMethod, "registration.verify")
        XCTAssertEqual(mockTransport.lastVerifyChallengeId, "verify-test-123")
        XCTAssertNotNil(mockTransport.lastVerifySignature, "Signature should be provided")
        XCTAssertNotNil(mockTransport.lastVerifyPublicKey, "Public key should be provided")
    }

    func test_rpcRegistration_returnsTrueOnSuccess() async throws {
        let mockTransport = MockAgentWebSocketTransport()
        mockTransport.challengeResponse = [
            "challenge_id": "success-test",
            "challenge": "dGVzdA=="
        ]
        mockTransport.verifyResponse = ["success": true]

        let service = AgentRPCRegistrationService(transport: mockTransport)

        let result = try await service.register(deviceId: "did:key:z6MkTest")

        XCTAssertTrue(result, "Registration should succeed")
    }

    func test_rpcRegistration_returnsFalseOnFailure() async throws {
        let mockTransport = MockAgentWebSocketTransport()
        mockTransport.challengeResponse = [
            "challenge_id": "fail-test",
            "challenge": "dGVzdA=="
        ]
        mockTransport.verifyResponse = ["success": false]

        let service = AgentRPCRegistrationService(transport: mockTransport)

        let result = try await service.register(deviceId: "did:key:z6MkTest")

        XCTAssertFalse(result, "Registration should fail")
    }

    func test_rpcRegistration_throwsOnInvalidChallengeResponse() async throws {
        let mockTransport = MockAgentWebSocketTransport()
        mockTransport.challengeResponse = ["invalid": "response"]

        let service = AgentRPCRegistrationService(transport: mockTransport)

        do {
            _ = try await service.register(deviceId: "did:key:z6MkTest")
            XCTFail("Should throw error on invalid challenge response")
        } catch let error as RegistrationError {
            XCTAssertEqual(error, .invalidChallengeResponse)
        }
    }

    func test_rpcRegistration_throwsOnInvalidBase64Challenge() async throws {
        let mockTransport = MockAgentWebSocketTransport()
        mockTransport.challengeResponse = [
            "challenge_id": "test",
            "challenge": "!!!invalid-base64!!!"
        ]

        let service = AgentRPCRegistrationService(transport: mockTransport)

        do {
            _ = try await service.register(deviceId: "did:key:z6MkTest")
            XCTFail("Should throw error on invalid base64")
        } catch let error as RegistrationError {
            XCTAssertEqual(error, .invalidChallengeFormat)
        }
    }

    // MARK: - Agent Endpoint Storage Tests (TDD: RED Phase)

    /// Tests that when authorizing an agent via QR code, the rpc endpoint is stored in the Profile
    /// so it can be used later for connecting to the agent.
    func test_delegatedAgent_storesEndpointForLaterConnection() async throws {
        // Given: An agent authorization request with an RPC endpoint
        let rpcEndpoint = "ws://192.168.1.100:8342"
        let agentDID = "did:key:z6MkTestAgent123"
        let agentName = "Test Edge Agent"

        // When: Creating a delegated agent profile
        let profile = Profile.createAgentProfile(
            agentID: agentDID,
            name: agentName,
            did: agentDID,
            purpose: "Delegated agent with authorized access",
            model: nil,
            endpoint: rpcEndpoint,  // This should be stored
            contactType: .delegatedAgent,
            channels: [.localNetwork(endpoint: rpcEndpoint, isAvailable: true)],
            entitlements: AgentEntitlements()
        )

        // Then: The endpoint should be stored and retrievable
        XCTAssertEqual(profile.agentEndpoint, rpcEndpoint, "Agent endpoint should be stored in Profile")
        XCTAssertEqual(profile.channels.first?.type, .localNetwork, "Channel should be local network")
        XCTAssertEqual(profile.channels.first?.endpoint, rpcEndpoint, "Channel endpoint should match")
    }

    /// Tests that a Profile can provide an AgentEndpoint for connecting
    func test_profile_canProvideAgentEndpoint() {
        // Given: A profile with stored endpoint
        let profile = Profile.createAgentProfile(
            agentID: "did:key:z6MkTest",
            name: "Test Agent",
            did: "did:key:z6MkTest",
            purpose: "Testing",
            model: "test-model",
            endpoint: "ws://localhost:8080",
            contactType: .delegatedAgent,
            channels: [.localNetwork(endpoint: "ws://localhost:8080", isAvailable: true)]
        )

        // When: Converting to AgentEndpoint for connection
        let agentEndpoint = profile.toAgentEndpoint()

        // Then: AgentEndpoint should be properly constructed
        XCTAssertNotNil(agentEndpoint, "Profile should provide AgentEndpoint when endpoint is stored")
        XCTAssertEqual(agentEndpoint?.id, profile.agentID)
        XCTAssertEqual(agentEndpoint?.url, "ws://localhost:8080")
        XCTAssertEqual(agentEndpoint?.metadata.name, profile.name)
        XCTAssertEqual(agentEndpoint?.metadata.purpose, profile.agentPurpose)
    }

    /// Tests that a Profile without endpoint returns nil AgentEndpoint
    func test_profile_withoutEndpoint_returnsNilAgentEndpoint() {
        // Given: A profile without stored endpoint
        let profile = Profile.createAgentProfile(
            agentID: "did:key:z6MkTest",
            name: "Cloud Agent",
            did: "did:key:z6MkTest",
            purpose: "Cloud-based agent",
            model: nil,
            endpoint: nil,  // No endpoint
            contactType: .delegatedAgent,
            channels: [.arkavoNetwork(isAvailable: true)]
        )

        // When: Converting to AgentEndpoint
        let agentEndpoint = profile.toAgentEndpoint()

        // Then: Should return nil since no local endpoint is stored
        XCTAssertNil(agentEndpoint, "Profile without endpoint should return nil AgentEndpoint")
    }
}

// MARK: - Mock Transport

final class MockAgentWebSocketTransport: AgentTransportProtocol, @unchecked Sendable {
    var challengeResponse: [String: Any] = [:]
    var verifyResponse: [String: Any] = [:]

    var lastChallengeMethod: String?
    var lastChallengeDeviceId: String?

    var lastVerifyMethod: String?
    var lastVerifyChallengeId: String?
    var lastVerifySignature: String?
    var lastVerifyPublicKey: String?
    var lastVerifyDeviceId: String?

    func sendRequest(_ request: AgentRequest) async throws -> AgentResponse {
        if request.method == "registration.challenge" {
            lastChallengeMethod = request.method
            if let params = request.params.value as? [String: Any] {
                lastChallengeDeviceId = params["device_id"] as? String
            }
            return .success(id: request.id, result: AnyCodable(challengeResponse))
        } else if request.method == "registration.verify" {
            lastVerifyMethod = request.method
            if let params = request.params.value as? [String: Any] {
                lastVerifyChallengeId = params["challenge_id"] as? String
                lastVerifySignature = params["signature"] as? String
                lastVerifyPublicKey = params["public_key"] as? String
                lastVerifyDeviceId = params["device_id"] as? String
            }
            return .success(id: request.id, result: AnyCodable(verifyResponse))
        }
        throw AgentError.webSocketError("Unexpected method: \(request.method)")
    }
}
