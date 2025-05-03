# Key Exchange Protocol Test Suite Documentation

## Overview

This document outlines the comprehensive test suite implemented for the One-Time TDF Key Exchange Protocol in the Arkavo app. The test suite verifies the correct functioning of the key exchange mechanism between peers, which provides the foundation for secure P2P communication with perfect forward secrecy.

## Test Components

The test suite consists of five main components:

1. **Key Exchange State Machine Tests** (`KeyExchangeTests.swift`)
   - Tests the state transitions of the key exchange protocol
   - Verifies correct nonce handling and state persistence
   - Includes failure state testing

2. **KeyStoreData Model Tests** (`KeyStoreDataTests.swift`)
   - Verifies the correct implementation of the KeyStoreData model
   - Tests serialization and deserialization of key data
   - Verifies curve handling and default behavior

3. **Profile Key Store Persistence Tests** (`ProfileKeyStorePersistenceTests.swift`)
   - Tests the persistence of keyStorePublic and keyStorePrivate in the Profile model
   - Verifies profile sharing excludes sensitive key data
   - Tests key store data deletion

4. **Initial Key Exchange Tests** (`InitialKeyExchangeTests.swift`)
   - Tests the complete flow of the initial key exchange process
   - Verifies each step of the protocol from request to completion
   - Includes error handling and timeout testing

5. **Key Renewal Tests** (`KeyRenewalTests.swift`)
   - Tests the detection of low key count conditions
   - Verifies the key renewal process initiation
   - Tests successful key replenishment after renewal
   - Includes handling of edge cases like no connected peers

## Key Exchange Protocol Flow

The Key Exchange Protocol follows these steps:

1. **Threshold Detection:** The system detects when the KeyStore's valid key count falls below a threshold (10% of capacity).

2. **Initiation:** The initiator sends a `KeyRegenerationRequest` to the responder.

3. **Responder Offer:** The responder sends a `KeyRegenerationOffer` back with a nonce.

4. **Initiator Acknowledgment:** The initiator sends a `KeyRegenerationAcknowledgement` with their nonce.

5. **Responder Commitment:** The responder sends a `KeyRegenerationCommit` to finalize the agreement.

6. **Key Generation:** Both peers generate new key pairs locally.

7. **Key Exchange:** Both peers exchange their public KeyStore data.

8. **Completion:** Both peers update their stored relationships and key counts.

## State Machine

The state machine for key exchange includes these states:

- `idle`: No key exchange in progress
- `requestSent(nonce)`: Initiator sent request
- `requestReceived(nonce)`: Responder received request 
- `offerSent(nonce)`: Responder sent offer
- `offerReceived(nonce)`: Initiator received offer
- `ackSent(nonce)`: Initiator sent acknowledgement
- `ackReceived(nonce)`: Responder received acknowledgement
- `commitSent(nonce)`: Responder sent commit
- `commitReceivedWaitingForKeys(nonce)`: Initiator received commit and awaiting keys
- `completed(nonce)`: Exchange completed successfully
- `failed(reason)`: Exchange failed with reason

## Test Mocks

The test suite uses several mock classes to isolate testing:

- `MockP2PGroupViewModel`: Simulates the P2P group view model for testing state transitions and message handling
- `MockPeerDiscoveryManager`: Simulates the peer discovery manager for testing key renewal
- `MockPersistenceController`: Simulates the persistence controller for testing profile and key store data persistence
- `MockKeyStore`: Mocks the OpenTDFKit KeyStore for testing key generation and serialization
- `MockArkavoClient`: Mocks the ArkavoClient for testing encryption and sending operations

## Key Storage Model

The test suite verifies the key storage model:

- Each peer relationship stores two key sets in the Profile model:
  - `keyStorePublic`: Stores the peer's public keys
  - `keyStorePrivate`: Stores the local user's private keys generated for this peer

- The `KeyStoreData` class manages serialization and deserialization of the key data.

## Running the Tests

To run the test suite:

```bash
xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64'
```

To run a specific test class:

```bash
xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64' -only-testing:ArkavoTests/KeyExchangeTests
```

## Test Coverage

The test suite covers:

1. **Normal Operation**: Complete and successful key exchange process
2. **Error Handling**: Tests various error conditions and recovery
3. **Edge Cases**: Low key count detection, no peers available, etc.
4. **Security Properties**: Verifies that sensitive key data is properly handled

## Future Test Enhancements

Potential enhancements to the test suite:

1. **Integration Tests**: Test with actual MultipeerConnectivity sessions
2. **Performance Tests**: Measure the performance of key generation and exchange
3. **Stress Tests**: Test with large numbers of peers and key exchanges
4. **Security Tests**: Verify the cryptographic properties of the protocol