# P2PClient for One-Time TDF

This document provides an overview of the `P2PClient` implementation for handling secure peer-to-peer communication with One-Time TDF (Trusted Data Format).

## Overview

The `P2PClient` abstracts peer-to-peer encryption and communication, similar to how `ArkavoClient` handles server communication. It leverages OpenTDFKit for encryption and the existing PeerDiscoveryManager for peer connectivity.

Key features:
- One-Time TDF implementation for perfect forward secrecy
- KeyStore management with automatic key regeneration
- Stream-based and direct peer-to-peer messaging
- Persistent storage of messages via Thought model
- Clean delegate pattern for events and error handling

## Integration

### 1. Factory Access

The `P2PClient` integrates with the `ViewModelFactory`:

```swift
// Get the P2PClient instance
let p2pClient = ViewModelFactory.shared.getP2PClient()
```

### 2. Update ChatViewModel

Modify the ChatViewModel to use P2PClient instead of direct P2P implementation:

1. Add a P2PClient property:
```swift
private var p2pClient: P2PClient?
```

2. Initialize in the constructor:
```swift
init(...) {
    // ...existing code
    self.p2pClient = ViewModelFactory.shared.getP2PClient()
    // ...
}
```

3. Implement P2PClientDelegate:
```swift
extension ChatViewModel: P2PClientDelegate {
    func clientDidReceiveMessage(_ client: P2PClient, streamID: Data, messageData: Data, from profile: Profile) {
        // Handle received messages
    }
    
    func clientDidChangeConnectionStatus(_ client: P2PClient, status: P2PConnectionStatus) {
        // Update UI based on connection status
    }
    
    func clientDidUpdateKeyStatus(_ client: P2PClient, localKeys: Int, totalCapacity: Int) {
        // Update key status UI if needed
    }
    
    func clientDidEncounterError(_ client: P2PClient, error: Error) {
        // Handle errors
    }
}
```

4. Replace direct P2P methods with P2PClient calls:
```swift
// Replace:
try await sendP2PMessage(content, stream: stream)

// With:
try await p2pClient?.sendMessage(content, toStream: stream.publicID)

// Replace:
try await sendDirectMessageToPeer(directProfile, content: content)

// With:
try await p2pClient?.sendDirectMessage(content, toPeer: directProfile.publicID, inStream: streamPublicID)
```

### 3. Connect to P2P Streams

When joining a P2P stream, connect using the P2PClient:

```swift
try await p2pClient.connect(to: stream)
```

## Implementation Details

### Key Management

The P2PClient automatically manages the KeyStore:
- Loads existing KeyStore from persistence or creates a new one
- Monitors key usage and regenerates keys when below threshold
- Marks used keys as consumed for one-time TDF implementation
- Persists KeyStore changes

### Security Features

- Perfect forward secrecy via one-time keys
- Stream-specific and direct message encryption policies
- Automatic key rotation and regeneration
- Local persistence of encrypted messages

### Error Handling

All P2P operations use Swift's structured concurrency with typed errors:
- `P2PError` enum provides detailed error information
- Errors are reported through the delegate pattern
- All async methods properly propagate errors

## Usage Examples

### Sending Messages

```swift
// Send to all peers in a stream
try await p2pClient.sendMessage("Hello everyone!", toStream: streamID)

// Send directly to a specific peer
try await p2pClient.sendDirectMessage("Hi there!", toPeer: peerProfileID, inStream: streamID)
```

### Managing Keys

```swift
// Get current key statistics
let (keyCount, capacity) = p2pClient.getKeyStatistics()

// Manually trigger key regeneration (usually handled automatically)
await p2pClient.regenerateKeys()
```

### Working with Peers

```swift
// Get connected peer profiles
let peerProfiles = p2pClient.connectedPeerProfiles

// Get peer browser controller for manual peer selection
let browserVC = p2pClient.getPeerBrowser()
present(browserVC, animated: true)
```

## Additional Notes

1. The P2PClient maintains a singleton instance through the ViewModelFactory
2. Multiple ViewModels can share the same P2PClient instance
3. KeyStore operations are asynchronous and thread-safe
4. The implementation is designed for one-time TDF usage
5. All persistent storage uses SwiftData via PersistenceController