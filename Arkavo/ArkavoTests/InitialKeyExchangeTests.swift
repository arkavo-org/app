@testable import Arkavo
import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import XCTest

// MARK: - Mock P2PGroupViewModel for Initial Key Exchange

@MainActor
class MockP2PGroupViewModelForInitialExchange {
    // Properties to track method calls
    var sendP2PMessageCalled = false
    var lastMessageType: P2PMessageType?
    var lastMessagePayload: Any?
    var lastMessagePeers: [MCPeerID]?

    // P2P Peer key exchange states
    var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:]

    // Indicate whether the P2P methods should throw an error
    var shouldThrowError = false
    var mockError = NSError(domain: "MockP2PError", code: 1, userInfo: nil)

    // Mock implementation of sendP2PMessage
    func sendP2PMessage(type: P2PMessageType, payload: some Codable, toPeers peers: [MCPeerID]) async throws {
        print("MockP2PGroupViewModel: sendP2PMessage called with type \(type)")

        if shouldThrowError {
            throw mockError
        }

        sendP2PMessageCalled = true
        lastMessageType = type
        lastMessagePayload = payload
        lastMessagePeers = peers
    }

    // Mock initiateKeyRegeneration
    func initiateKeyRegeneration(with peer: MCPeerID) async throws {
        print("MockP2PGroupViewModel: initiateKeyRegeneration called with peer \(peer.displayName)")

        if shouldThrowError {
            throw mockError
        }

        // Update the peer exchange state
        let nonce = "initiatorNonce".data(using: .utf8)!
        updatePeerExchangeState(for: peer, newState: .requestSent(nonce: nonce))
    }

    // Mock P2P message handler methods
    // 1. Mock handling KeyRegenerationRequest
    func handleKeyRegenerationRequest(from peer: MCPeerID, data _: Data) {
        print("MockP2PGroupViewModel: handleKeyRegenerationRequest called")

        // Update the peer exchange state
        let nonce = "responderNonce".data(using: .utf8)!
        updatePeerExchangeState(for: peer, newState: .requestReceived(nonce: nonce))

        // After receiving request, responder sends offer
        updatePeerExchangeState(for: peer, newState: .offerSent(nonce: nonce))
    }

    // 2. Mock handling KeyRegenerationOffer
    func handleKeyRegenerationOffer(from peer: MCPeerID, data _: Data) {
        print("MockP2PGroupViewModel: handleKeyRegenerationOffer called")

        // Get the initiator's nonce from previous state
        guard let currentState = peerKeyExchangeStates[peer],
              case let .requestSent(nonce) = currentState.state
        else {
            return
        }

        // Update the peer exchange state
        updatePeerExchangeState(for: peer, newState: .offerReceived(nonce: nonce))
        updatePeerExchangeState(for: peer, newState: .ackSent(nonce: nonce))
    }

    // 3. Mock handling KeyRegenerationAcknowledgement
    func handleKeyRegenerationAcknowledgement(from peer: MCPeerID, data _: Data) {
        print("MockP2PGroupViewModel: handleKeyRegenerationAcknowledgement called")

        // Get the responder's nonce from previous state
        guard let currentState = peerKeyExchangeStates[peer],
              case let .offerSent(nonce) = currentState.state
        else {
            return
        }

        // Update the peer exchange state
        updatePeerExchangeState(for: peer, newState: .ackReceived(nonce: nonce))
        updatePeerExchangeState(for: peer, newState: .commitSent(nonce: nonce))
    }

    // 4. Mock handling KeyRegenerationCommit
    func handleKeyRegenerationCommit(from peer: MCPeerID, data _: Data) {
        print("MockP2PGroupViewModel: handleKeyRegenerationCommit called")

        // Get the initiator's nonce from previous state
        guard let currentState = peerKeyExchangeStates[peer],
              case let .ackSent(nonce) = currentState.state
        else {
            return
        }

        // Update the peer exchange state
        updatePeerExchangeState(for: peer, newState: .commitReceivedWaitingForKeys(nonce: nonce))
    }

    // 5. Mock handling KeyStoreShare
    func handleKeyStoreShare(from peer: MCPeerID, data _: Data) {
        print("MockP2PGroupViewModel: handleKeyStoreShare called")

        // Check if this is from the initiator or responder
        if let currentState = peerKeyExchangeStates[peer] {
            switch currentState.state {
            case let .commitSent(nonce): // Responder was waiting for keys
                updatePeerExchangeState(for: peer, newState: .completed(nonce: nonce))
            case let .commitReceivedWaitingForKeys(nonce): // Initiator was waiting for keys
                updatePeerExchangeState(for: peer, newState: .completed(nonce: nonce))
            default:
                break
            }
        }
    }

    // Helper method to update peer exchange state
    private func updatePeerExchangeState(for peer: MCPeerID, newState: KeyExchangeState) {
        var info = peerKeyExchangeStates[peer] ?? KeyExchangeTrackingInfo()
        info.state = newState
        info.lastActivity = Date()
        peerKeyExchangeStates[peer] = info
    }

    // Mock key generation method
    func performKeyGenerationAndSave(peerProfileIDData _: Data, peer _: MCPeerID) async throws -> Data {
        print("MockP2PGroupViewModel: performKeyGenerationAndSave called")

        if shouldThrowError {
            throw mockError
        }

        // Return mock serialized public key store data
        return "mockPublicKeyStoreData".data(using: .utf8)!
    }
}

// MARK: - Initial Key Exchange Tests

final class InitialKeyExchangeTests: XCTestCase {
    // Test variables
    var initiatorViewModel: MockP2PGroupViewModelForInitialExchange!
    var responderViewModel: MockP2PGroupViewModelForInitialExchange!
    var initiatorPeerID: MCPeerID!
    var responderPeerID: MCPeerID!
    var initiatorProfile: Profile!
    var responderProfile: Profile!

    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()

        // Create peer IDs
        initiatorPeerID = MCPeerID(displayName: "InitiatorDevice")
        responderPeerID = MCPeerID(displayName: "ResponderDevice")

        // Create profiles
        initiatorProfile = Profile(name: "Initiator")
        responderProfile = Profile(name: "Responder")

        // Create view models
        initiatorViewModel = MockP2PGroupViewModelForInitialExchange()
        responderViewModel = MockP2PGroupViewModelForInitialExchange()
    }

    override func tearDownWithError() throws {
        initiatorViewModel = nil
        responderViewModel = nil
        initiatorPeerID = nil
        responderPeerID = nil
        initiatorProfile = nil
        responderProfile = nil
        try super.tearDownWithError()
    }

    // MARK: - Test Cases

    @MainActor func testInitialKeyExchangeFlow() async throws {
        // Step 1: Initiator starts the key exchange
        try await initiatorViewModel.initiateKeyRegeneration(with: responderPeerID)

        // Verify initiator state
        guard let initiatorState = initiatorViewModel.peerKeyExchangeStates[responderPeerID] else {
            XCTFail("Initiator state not found")
            return
        }
        guard case .requestSent = initiatorState.state else {
            XCTFail("Expected initiator state to be requestSent, but was \(initiatorState.state)")
            return
        }
        XCTAssertNotNil(initiatorState.state.nonce)

        // Simulate request data and message handling
        let requestData = Data("mockRequestData".utf8)

        // Step 2: Responder receives request and sends offer
        responderViewModel.handleKeyRegenerationRequest(from: initiatorPeerID, data: requestData)

        // Verify responder state
        guard let responderState = responderViewModel.peerKeyExchangeStates[initiatorPeerID] else {
            XCTFail("Responder state not found")
            return
        }
        guard case .offerSent = responderState.state else {
            XCTFail("Expected responder state to be offerSent, but was \(responderState.state)")
            return
        }
        XCTAssertNotNil(responderState.state.nonce)

        // Simulate offer data and message handling
        let offerData = Data("mockOfferData".utf8)

        // Step 3: Initiator receives offer and sends acknowledgement
        initiatorViewModel.handleKeyRegenerationOffer(from: responderPeerID, data: offerData)

        // Verify initiator state
        guard let updatedInitiatorState = initiatorViewModel.peerKeyExchangeStates[responderPeerID] else {
            XCTFail("Updated initiator state not found")
            return
        }
        guard case .ackSent = updatedInitiatorState.state else {
            XCTFail("Expected initiator state to be ackSent, but was \(updatedInitiatorState.state)")
            return
        }

        // Simulate acknowledgement data and message handling
        let ackData = Data("mockAckData".utf8)

        // Step 4: Responder receives acknowledgement and sends commit
        responderViewModel.handleKeyRegenerationAcknowledgement(from: initiatorPeerID, data: ackData)

        // Verify responder state
        guard let updatedResponderState = responderViewModel.peerKeyExchangeStates[initiatorPeerID] else {
            XCTFail("Updated responder state not found")
            return
        }
        guard case .commitSent = updatedResponderState.state else {
            XCTFail("Expected responder state to be commitSent, but was \(updatedResponderState.state)")
            return
        }

        // Simulate commit data and message handling
        let commitData = Data("mockCommitData".utf8)

        // Step 5: Initiator receives commit
        initiatorViewModel.handleKeyRegenerationCommit(from: responderPeerID, data: commitData)

        // Verify initiator state
        guard let initiatorCommitState = initiatorViewModel.peerKeyExchangeStates[responderPeerID] else {
            XCTFail("Initiator commit state not found")
            return
        }
        guard case .commitReceivedWaitingForKeys = initiatorCommitState.state else {
            XCTFail("Expected initiator state to be commitReceivedWaitingForKeys, but was \(initiatorCommitState.state)")
            return
        }

        // Simulate keyStore data exchange
        let keyStoreData = Data("mockKeyStoreData".utf8)

        // Step 6: Initiator and responder exchange key store data
        initiatorViewModel.handleKeyStoreShare(from: responderPeerID, data: keyStoreData)
        responderViewModel.handleKeyStoreShare(from: initiatorPeerID, data: keyStoreData)

        // Verify final states
        guard let finalInitiatorState = initiatorViewModel.peerKeyExchangeStates[responderPeerID] else {
            XCTFail("Final initiator state not found")
            return
        }
        guard case .completed = finalInitiatorState.state else {
            XCTFail("Expected initiator state to be completed, but was \(finalInitiatorState.state)")
            return
        }

        guard let finalResponderState = responderViewModel.peerKeyExchangeStates[initiatorPeerID] else {
            XCTFail("Final responder state not found")
            return
        }
        guard case .completed = finalResponderState.state else {
            XCTFail("Expected responder state to be completed, but was \(finalResponderState.state)")
            return
        }
    }

    @MainActor func testInitiateKeyRegenerationError() async {
        // Set up error condition
        initiatorViewModel.shouldThrowError = true

        // Act & Assert
        do {
            try await initiatorViewModel.initiateKeyRegeneration(with: responderPeerID)
            XCTFail("Expected error but none was thrown")
        } catch {
            // Verify the correct error was thrown
            XCTAssertEqual(error as NSError, initiatorViewModel.mockError)
        }
    }

    @MainActor func testKeyExchangeTimeout() {
        // Create state with activity timestamp in the past
        var oldStateInfo = KeyExchangeTrackingInfo()
        oldStateInfo.state = .requestSent(nonce: "oldNonce".data(using: .utf8)!)
        oldStateInfo.lastActivity = Date().addingTimeInterval(-300) // 5 minutes ago

        // Add to initiator state
        initiatorViewModel.peerKeyExchangeStates[responderPeerID] = oldStateInfo

        // Verify the state is old
        XCTAssertLessThan(
            initiatorViewModel.peerKeyExchangeStates[responderPeerID]!.lastActivity,
            Date().addingTimeInterval(-60) // At least 1 minute old
        )

        // For a timeout handler, you would typically verify it gets transitioned to .failed
        // This would be in the real implementation that checks for timeouts
    }
}
