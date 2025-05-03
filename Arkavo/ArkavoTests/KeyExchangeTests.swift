import Combine
import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import XCTest
@testable import Arkavo

// MARK: - Mock ArkavoClient

@MainActor
class MockArkavoClient {
    var encryptAndSendPayloadCalled = false
    var lastEncryptedPayload: Data?
    var lastEncryptedPolicyData: Data?
    var shouldThrowError = false
    var mockError = NSError(domain: "MockArkavoClientError", code: 1, userInfo: nil)
    
    func encryptAndSendPayload(payload: Data, policyData: Data) async throws -> Void {
        print("MockArkavoClient: encryptAndSendPayload called")
        if shouldThrowError {
            throw mockError
        }
        encryptAndSendPayloadCalled = true
        lastEncryptedPayload = payload
        lastEncryptedPolicyData = policyData
    }
}

// MARK: - Mock KeyStore for OpenTDFKit

class MockKeyStoreForExchange {
    var generateAndStoreKeyPairsCalled = false
    var lastKeyCount: Int?
    var shouldThrowError = false
    var mockError = NSError(domain: "MockKeyStoreError", code: 1, userInfo: nil)
    
    func generateAndStoreKeyPairs(count: Int) async throws {
        print("MockKeyStoreForExchange: generateAndStoreKeyPairs called with count \(count)")
        if shouldThrowError {
            throw mockError
        }
        generateAndStoreKeyPairsCalled = true
        lastKeyCount = count
    }
    
    func serialize() async -> Data {
        return "serializedKeyStoreData".data(using: .utf8)!
    }
    
    func exportPublicKeyStore() async -> MockPublicKeyStoreForExchange {
        return MockPublicKeyStoreForExchange()
    }
}

class MockPublicKeyStoreForExchange {
    let publicKeys = [1, 2, 3, 4, 5] // Simulates having 5 keys
    
    func serialize() async -> Data {
        return "serializedPublicKeyStoreData".data(using: .utf8)!
    }
}

// MARK: - Key Exchange State Tests

final class KeyExchangeTests: XCTestCase {
    // Test variables
    var initiatorPeerID: MCPeerID!
    var responderPeerID: MCPeerID!
    var initiatorProfile: Profile!
    var responderProfile: Profile!
    var mockPersistenceController: MockPersistenceController!
    var mockArkavoClient: MockArkavoClient!
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create peer IDs
        initiatorPeerID = MCPeerID(displayName: "InitiatorDevice")
        responderPeerID = MCPeerID(displayName: "ResponderDevice")
        
        // Create profiles
        initiatorProfile = Profile(name: "Initiator")
        responderProfile = Profile(name: "Responder")
        
        // Create persistence controller
        mockPersistenceController = MockPersistenceController()
        mockPersistenceController.addMockProfile(initiatorProfile)
        mockPersistenceController.addMockProfile(responderProfile)
        
        // Create ArkavoClient
        mockArkavoClient = MockArkavoClient()
    }
    
    override func tearDownWithError() throws {
        initiatorPeerID = nil
        responderPeerID = nil
        initiatorProfile = nil
        responderProfile = nil
        mockPersistenceController = nil
        mockArkavoClient = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Test Cases
    
    @MainActor func testKeyExchangeStateTransitions() async throws {
        // Create tracking info for initiator and responder
        var initiatorStateInfo = KeyExchangeTrackingInfo()
        var responderStateInfo = KeyExchangeTrackingInfo()
        
        // Step 1: Initiator sends request
        let requestID = UUID()
        let initiatorNonce = "initiatorNonce".data(using: .utf8)!
        initiatorStateInfo.state = .requestSent(nonce: initiatorNonce)
        XCTAssertEqual(initiatorStateInfo.state, .requestSent(nonce: initiatorNonce))
        
        // Step 2: Responder receives request and sends offer
        let responderNonce = "responderNonce".data(using: .utf8)!
        responderStateInfo.state = .requestReceived(nonce: responderNonce)
        XCTAssertEqual(responderStateInfo.state, .requestReceived(nonce: responderNonce))
        responderStateInfo.state = .offerSent(nonce: responderNonce)
        XCTAssertEqual(responderStateInfo.state, .offerSent(nonce: responderNonce))
        
        // Step 3: Initiator receives offer and sends acknowledgement
        initiatorStateInfo.state = .offerReceived(nonce: initiatorNonce)
        XCTAssertEqual(initiatorStateInfo.state, .offerReceived(nonce: initiatorNonce))
        initiatorStateInfo.state = .ackSent(nonce: initiatorNonce)
        XCTAssertEqual(initiatorStateInfo.state, .ackSent(nonce: initiatorNonce))
        
        // Step 4: Responder receives acknowledgement and sends commit
        responderStateInfo.state = .ackReceived(nonce: responderNonce)
        XCTAssertEqual(responderStateInfo.state, .ackReceived(nonce: responderNonce))
        responderStateInfo.state = .commitSent(nonce: responderNonce)
        XCTAssertEqual(responderStateInfo.state, .commitSent(nonce: responderNonce))
        
        // Step 5: Initiator receives commit and waits for keys
        initiatorStateInfo.state = .commitReceivedWaitingForKeys(nonce: initiatorNonce)
        XCTAssertEqual(initiatorStateInfo.state, .commitReceivedWaitingForKeys(nonce: initiatorNonce))
        
        // Step 6: Both sides complete after receiving KeyStoreShare
        initiatorStateInfo.state = .completed(nonce: initiatorNonce)
        responderStateInfo.state = .completed(nonce: responderNonce)
        XCTAssertEqual(initiatorStateInfo.state, .completed(nonce: initiatorNonce))
        XCTAssertEqual(responderStateInfo.state, .completed(nonce: responderNonce))
    }
    
    @MainActor func testFailureStateTransition() {
        var stateInfo = KeyExchangeTrackingInfo()
        
        // Test transition to failure state
        stateInfo.state = .failed("Connection lost")
        XCTAssertEqual(stateInfo.state, .failed("Connection lost"))
        
        // Verify nonce is nil in failure state
        XCTAssertNil(stateInfo.state.nonce)
    }
    
    @MainActor func testKeyExchangeStatePersistence() {
        // Mock P2PGroupViewModel peerKeyExchangeStates implementation
        var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:]
        
        // Create a test exchange state
        let nonce = "testNonce".data(using: .utf8)!
        let stateInfo = KeyExchangeTrackingInfo(state: .offerSent(nonce: nonce), lastActivity: Date())
        
        // Store state for peer
        peerKeyExchangeStates[initiatorPeerID] = stateInfo
        
        // Verify storage and retrieval
        XCTAssertNotNil(peerKeyExchangeStates[initiatorPeerID])
        XCTAssertEqual(peerKeyExchangeStates[initiatorPeerID]?.state, .offerSent(nonce: nonce))
        
        // Update state
        var updatedInfo = peerKeyExchangeStates[initiatorPeerID]!
        updatedInfo.state = .ackReceived(nonce: nonce)
        peerKeyExchangeStates[initiatorPeerID] = updatedInfo
        
        // Verify update
        XCTAssertEqual(peerKeyExchangeStates[initiatorPeerID]?.state, .ackReceived(nonce: nonce))
    }
}