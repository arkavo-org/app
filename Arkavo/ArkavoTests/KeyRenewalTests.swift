import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import XCTest
@testable import Arkavo

// MARK: - Mock PeerDiscoveryManager for Key Renewal

@MainActor
class MockPeerDiscoveryManagerForRenewal: ObservableObject {
    // Published properties
    @Published var localKeyStoreInfo: LocalKeyStoreInfo?
    @Published var isKeyStoreLow: Bool = false
    @Published var connectedPeers: [MCPeerID] = []
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]
    @Published var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:]
    
    // Mock methods
    var initiateKeyRegenerationCalled = false
    var lastPeerForKeyRegeneration: MCPeerID?
    var shouldThrowError = false
    var mockError = NSError(domain: "MockPeerManagerError", code: 1, userInfo: nil)
    
    func initiateKeyRegeneration(with peer: MCPeerID) async throws {
        print("MockPeerDiscoveryManagerForRenewal: initiateKeyRegeneration called with peer \(peer.displayName)")
        
        if shouldThrowError {
            throw mockError
        }
        
        initiateKeyRegenerationCalled = true
        lastPeerForKeyRegeneration = peer
        
        // Update the key exchange state to simulate the process starting
        updateKeyExchangeState(for: peer, state: .requestSent(nonce: "initiatorNonce".data(using: .utf8)!))
    }
    
    // Helper methods
    func setupConnectedPeers(_ peers: [MCPeerID]) {
        connectedPeers = peers
    }
    
    func setupConnectedPeerProfiles(_ profiles: [MCPeerID: Profile]) {
        connectedPeerProfiles = profiles
    }
    
    func setKeyStoreInfo(keyCount: Int, expired: Int, capacity: Int) {
        localKeyStoreInfo = LocalKeyStoreInfo(validKeyCount: keyCount, expiredKeyCount: expired, capacity: capacity)
        
        // Calculate if key store is low based on threshold
        let lowKeyThreshold = 0.1 // 10%
        let remainingPercent = Double(keyCount) / Double(capacity)
        isKeyStoreLow = remainingPercent <= lowKeyThreshold
    }
    
    private func updateKeyExchangeState(for peer: MCPeerID, state: KeyExchangeState) {
        var info = peerKeyExchangeStates[peer] ?? KeyExchangeTrackingInfo()
        info.state = state
        info.lastActivity = Date()
        peerKeyExchangeStates[peer] = info
    }
    
    // Mock the full key exchange cycle
    func simulateSuccessfulKeyExchange(with peer: MCPeerID) {
        updateKeyExchangeState(for: peer, state: .requestSent(nonce: "initiatorNonce".data(using: .utf8)!))
        updateKeyExchangeState(for: peer, state: .offerReceived(nonce: "initiatorNonce".data(using: .utf8)!))
        updateKeyExchangeState(for: peer, state: .ackSent(nonce: "initiatorNonce".data(using: .utf8)!))
        updateKeyExchangeState(for: peer, state: .commitReceivedWaitingForKeys(nonce: "initiatorNonce".data(using: .utf8)!))
        updateKeyExchangeState(for: peer, state: .completed(nonce: "initiatorNonce".data(using: .utf8)!))
        
        // After successful exchange, update key count
        if let info = localKeyStoreInfo {
            setKeyStoreInfo(keyCount: info.capacity, expired: info.expiredKeyCount, capacity: info.capacity)
        }
    }
}

// MARK: - Key Renewal Tests

final class KeyRenewalTests: XCTestCase {
    var peerManager: MockPeerDiscoveryManagerForRenewal!
    var testPeer: MCPeerID!
    var testProfile: Profile!
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create test peer and profile
        testPeer = MCPeerID(displayName: "TestPeer")
        testProfile = Profile(name: "Test Peer")
        
        // Create peer manager
        peerManager = MockPeerDiscoveryManagerForRenewal()
        
        // Setup test peer
        peerManager.setupConnectedPeers([testPeer])
        peerManager.setupConnectedPeerProfiles([testPeer: testProfile])
    }
    
    override func tearDownWithError() throws {
        peerManager = nil
        testPeer = nil
        testProfile = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Test Cases
    
    @MainActor func testKeyStoreLowDetection() {
        // Set up key counts for low detection
        // 10% threshold: 819 out of 8192 is exactly 10%
        peerManager.setKeyStoreInfo(keyCount: 819, expired: 0, capacity: 8192)
        
        // Verify key store is detected as low
        XCTAssertTrue(peerManager.isKeyStoreLow)
        
        // Set up key counts above threshold
        peerManager.setKeyStoreInfo(keyCount: 820, expired: 0, capacity: 8192)
        
        // Verify key store is not detected as low
        XCTAssertFalse(peerManager.isKeyStoreLow)
        
        // Test very low key count
        peerManager.setKeyStoreInfo(keyCount: 10, expired: 0, capacity: 8192)
        
        // Verify key store is detected as low
        XCTAssertTrue(peerManager.isKeyStoreLow)
    }
    
    @MainActor func testInitiateKeyRenewalWhenLow() async throws {
        // Set up key counts for low detection
        peerManager.setKeyStoreInfo(keyCount: 100, expired: 0, capacity: 8192)
        
        // Verify key store is detected as low
        XCTAssertTrue(peerManager.isKeyStoreLow)
        
        // Initiate key renewal
        try await peerManager.initiateKeyRegeneration(with: testPeer)
        
        // Verify the method was called
        XCTAssertTrue(peerManager.initiateKeyRegenerationCalled)
        XCTAssertEqual(peerManager.lastPeerForKeyRegeneration, testPeer)
        
        // Verify the key exchange state was updated
        let exchangeState = peerManager.peerKeyExchangeStates[testPeer]
        XCTAssertNotNil(exchangeState)
        guard case .requestSent = exchangeState?.state else {
            XCTFail("Expected state to be requestSent, but was \(String(describing: exchangeState?.state))")
            return
        }
    }
    
    @MainActor func testKeyRenewalError() async {
        // Set up key counts for low detection
        peerManager.setKeyStoreInfo(keyCount: 100, expired: 0, capacity: 8192)
        
        // Set up error condition
        peerManager.shouldThrowError = true
        
        // Attempt to initiate key renewal and verify error
        do {
            try await peerManager.initiateKeyRegeneration(with: testPeer)
            XCTFail("Expected error but none was thrown")
        } catch {
            // Verify the correct error was thrown
            XCTAssertEqual(error as NSError, peerManager.mockError)
        }
    }
    
    @MainActor func testKeyStoreReplenishedAfterRenewal() {
        // Set up key counts for low detection
        peerManager.setKeyStoreInfo(keyCount: 100, expired: 0, capacity: 8192)
        
        // Verify key store is detected as low
        XCTAssertTrue(peerManager.isKeyStoreLow)
        
        // Simulate successful key exchange
        peerManager.simulateSuccessfulKeyExchange(with: testPeer)
        
        // Verify key store is replenished and no longer low
        XCTAssertFalse(peerManager.isKeyStoreLow)
        XCTAssertEqual(peerManager.localKeyStoreInfo?.validKeyCount, 8192)
        
        // Verify the key exchange state is completed
        let exchangeState = peerManager.peerKeyExchangeStates[testPeer]
        XCTAssertNotNil(exchangeState)
        guard case .completed = exchangeState?.state else {
            XCTFail("Expected state to be completed, but was \(String(describing: exchangeState?.state))")
            return
        }
    }
    
    @MainActor func testNoConnectedPeersForRenewal() async throws {
        // Remove connected peers
        peerManager.setupConnectedPeers([])
        
        // Set up key counts for low detection
        peerManager.setKeyStoreInfo(keyCount: 100, expired: 0, capacity: 8192)
        
        // Verify key store is detected as low
        XCTAssertTrue(peerManager.isKeyStoreLow)
        
        // No peers available for renewal
        XCTAssertEqual(peerManager.connectedPeers.count, 0)
        
        // In a real implementation, there would be a check for this condition
        // and appropriate UI or error handling. Here we just verify the state.
    }
}