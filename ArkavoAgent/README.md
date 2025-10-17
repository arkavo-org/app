# ArkavoAgent

Swift library for A2A (Agent-to-Agent) protocol communication on iOS and macOS.

## Features

- **mDNS Service Discovery**: Automatically discover arkavo-edge agents on the local network using Bonjour
- **WebSocket Transport**: JSON-RPC 2.0 over WebSocket with support for both `ws://` and `wss://`
- **Connection Management**: Automatic reconnection with exponential backoff
- **Chat Sessions**: Full support for the A2A chat protocol with streaming deltas
- **SwiftUI Integration**: Observable objects for easy integration with SwiftUI views
- **Cross-Platform**: Works on both iOS 17+ and macOS 14+

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+
- Xcode 16.0+

## Installation

### Swift Package Manager

Add ArkavoAgent to your project:

```swift
dependencies: [
    .package(path: "../ArkavoAgent")
]
```

### Permissions

Add the following to your `Info.plist`:

```xml
<key>NSBonjourServices</key>
<array>
    <string>_a2a._tcp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>Arkavo uses the local network to discover and communicate with AI agents</string>
```

## Quick Start

### 1. Discover Agents

```swift
import ArkavoAgent

let manager = AgentManager.shared
manager.startDiscovery()

// Observe discovered agents
manager.$agents
    .sink { agents in
        print("Discovered \(agents.count) agents")
        for agent in agents {
            print("  - \(agent.metadata.name) (\(agent.metadata.model))")
        }
    }
    .store(in: &cancellables)
```

### 2. Connect to an Agent

```swift
// Manual connection
if let agent = manager.agents.first {
    try await manager.connect(to: agent)
}

// Or enable auto-connect
let manager = AgentManager(autoConnect: true, autoReconnect: true)
manager.startDiscovery()
// Agents will be connected automatically as they're discovered
```

### 3. Send Requests

```swift
// Simple request
let response = try await manager.sendRequest(
    to: agentId,
    method: "rpc.discover",
    params: [:]
)

// Handle response
switch response {
case .success(_, let result):
    print("Success: \(result)")
case .error(_, let code, let message):
    print("Error \(code): \(message)")
}
```

### 4. Chat Sessions

```swift
let chatManager = AgentChatSessionManager(agentManager: manager)

// Open a session
let session = try await chatManager.openSession(with: agentId)

// Send a message
try await chatManager.sendMessage(
    sessionId: session.id,
    content: "What is the weather like?"
)

// Close session when done
await chatManager.closeSession(sessionId: session.id)
```

## Architecture

```
┌─────────────────────────────────┐
│       AgentManager              │
│  - Discovery coordination       │
│  - Connection pool              │
│  - Auto-connect/reconnect       │
└────────┬───────────────┬────────┘
         │               │
┌────────▼────────┐ ┌────▼───────────┐
│ AgentDiscovery  │ │ AgentConnection│
│ Service         │ │ - Per-agent    │
│ - NetService    │ │ - WebSocket    │
│ - mDNS browse   │ │ - Reconnection │
└─────────────────┘ └────┬───────────┘
                         │
                  ┌──────▼──────────┐
                  │ AgentWebSocket  │
                  │ Transport       │
                  │ - JSON-RPC 2.0  │
                  │ - Request/resp  │
                  └─────────────────┘
```

## API Reference

### AgentManager

Main entry point for agent discovery and connection management.

```swift
class AgentManager: ObservableObject {
    static let shared: AgentManager

    @Published var agents: [AgentEndpoint]
    @Published var connections: [String: AgentConnection]
    @Published var statuses: [String: ConnectionStatus]

    func startDiscovery()
    func stopDiscovery()
    func connect(to: AgentEndpoint) async throws
    func disconnect(from: String) async
    func sendRequest(to: String, method: String, params: [String: Any]) async throws -> AgentResponse
}
```

### AgentDiscoveryService

Handles mDNS/Bonjour service discovery.

```swift
class AgentDiscoveryService: ObservableObject {
    @Published var discoveredAgents: [AgentEndpoint]
    @Published var isDiscovering: Bool

    func startDiscovery()
    func stopDiscovery()
}
```

### AgentChatSessionManager

Manages chat sessions with agents.

```swift
class AgentChatSessionManager: ObservableObject {
    @Published var activeSessions: [String: ChatSession]
    @Published var messageDeltas: [String: [MessageDelta]]

    func openSession(with: String, token: String?, context: [String: AnyCodable]?) async throws -> ChatSession
    func sendMessage(sessionId: String, content: String, attachments: [String]?) async throws
    func closeSession(sessionId: String) async
}
```

## SwiftUI Integration

```swift
import SwiftUI
import ArkavoAgent

struct AgentListView: View {
    @ObservedObject var manager = AgentManager.shared

    var body: some View {
        List(manager.agents) { agent in
            VStack(alignment: .leading) {
                Text(agent.metadata.name)
                    .font(.headline)
                Text(agent.metadata.purpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            manager.startDiscovery()
        }
        .onDisappear {
            manager.stopDiscovery()
        }
    }
}
```

## Testing

Run the test suite:

```bash
swift test
```

## Integration with arkavo-edge

This library is designed to work with the [arkavo-edge](https://github.com/arkavo-org/arkavo-edge) Rust agent platform.

### Starting an arkavo-edge Agent

```bash
# Start an agent with mDNS enabled
arkavo

# The agent will advertise itself on _a2a._tcp.local.
# ArkavoAgent will automatically discover it
```

### Protocol Compatibility

- JSON-RPC 2.0 over WebSocket
- Service type: `_a2a._tcp.local.`
- TXT record fields: `agent_id`, `purpose`, `model`
- Chat protocol: Compatible with arkavo-edge chat-v2

## Contributing

Contributions are welcome! Please see the main [arkavo](https://github.com/arkavo-com/arkavo) repository.

## License

Licensed under the same terms as the arkavo project.

## Related

- [arkavo-edge](https://github.com/arkavo-org/arkavo-edge) - Rust agent platform
- [OpenTDFKit](https://github.com/opentdf/opentdf-ios) - TDF encryption for iOS/macOS
