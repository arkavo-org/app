# Arkavo Hybrid Agent Architecture

## Overview

Arkavo implements a hybrid agent architecture where the iOS/macOS LocalAIAgent acts as a **participant** (not a coordinator) in a distributed agent system orchestrated by arkavo-edge. This architecture enables seamless collaboration between on-device AI capabilities and cloud-based agent services.

## Architectural Principles

### Single Source of Truth
- **Orchestrator (arkavo-edge)**: Responsible for planning, task graphing, routing, and escalation
- **LocalAIAgent (iOS/macOS)**: Exposes on-device capabilities and sensors as an A2A participant
- **Human**: Can chat directly with any agent via A2A, including the Orchestrator or LocalAIAgent

### Agent Roles

#### Orchestrator (arkavo-edge)
Lives off-device and provides:
- Task decomposition and planning
- Agent routing and selection
- Task graph execution
- Cross-agent coordination
- Long-running job management

#### LocalAIAgent (iOS/macOS)
On-device participant that:
- Exposes Apple Intelligence capabilities (Foundation Models, Writing Tools, Image Playground)
- Brokers device sensors behind permissions and policy
- Speaks A2A protocol to Orchestrator and peer agents
- Executes local tool calls
- **Does NOT coordinate** - only participates

#### Human
Directly engages with agents via A2A chat channels:
- Human ↔ Orchestrator: New goals, status updates, clarifications, planning
- Human ↔ LocalAIAgent: Device tasks, sensor access, on-device AI
- Human ↔ Other Agents: Task-specific assistance as needed

## Control & Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                       User Intent (iOS App)                      │
│          (Siri, App Intent, Spotlight, Direct Chat)              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
            ┌───────────────────────────────┐
            │     LocalAIAgent (iOS)        │
            │   • TaskOffer → Orchestrator  │
            │   • Direct chat available     │
            └───────────────┬───────────────┘
                            │ A2A WebSocket
                            ▼
            ┌───────────────────────────────┐
            │   Orchestrator (arkavo-edge)  │
            │   • Decomposes into sub-tasks │
            │   • Assigns to agents         │
            │   • Routes sensor requests    │
            └───────────────┬───────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ LocalAIAgent  │   │ Remote Agent  │   │ Remote Agent  │
│ (Sensors,AI)  │   │ (Web, RAG)    │   │ (DB, API)     │
└───────────────┘   └───────────────┘   └───────────────┘
```

### Detailed Flow

1. **Intent In**
   - User triggers via App Intent, Siri, or direct chat
   - LocalAIAgent wraps as A2A `TaskOffer`
   - Sends to Orchestrator (if available)
   - No global planning happens on-device

2. **Plan Out**
   - Orchestrator decomposes intent into sub-tasks
   - Assigns tasks to agents based on capabilities
   - May assign back to LocalAIAgent for device-local work

3. **On-Device Capability**
   - Foundation Models: Structured generation, tool calling (local tools only)
   - Writing Tools: Text refinement, proofreading, where UI supports
   - Image Playground: On-device image synthesis
   - All stays on-device, no per-request cost

4. **Sensors/Actuators**
   - Any agent requests device data via `SensorRequest`
   - Orchestrator routes to LocalAIAgent
   - LocalAIAgent enforces:
     - User permission prompting
     - Scope limiting (minimal/standard/detailed)
     - Rate limiting
     - Data redaction
     - Audit logging

5. **Human-in-the-Loop**
   - Any agent can send `HumanAssistRequest`
   - Human chats directly with requesting agent over A2A
   - LocalAIAgent only hosts the chat channel (does not coordinate)

6. **Results Return**
   - Agents send `TaskResult` to Orchestrator
   - Orchestrator aggregates and delivers to app

## A2A Protocol Primitives

### TaskOffer
```json
{
  "intent_id": "uuid",
  "intent": "Find nearby coffee shops with outdoor seating",
  "capabilities_hint": ["location", "maps"],
  "device_caps": {
    "ai_capabilities": ["foundation_models", "writing_tools"],
    "sensors": ["location", "camera", "motion"],
    "platform": "ios",
    "os_version": "26.0.0"
  }
}
```

### SensorRequest
```json
{
  "task_id": "task-123",
  "sensor": "location",
  "scope": "standard",
  "retention": 300,
  "rate": 1.0,
  "policy_tag": "location-for-search"
}
```

### SensorResponse
```json
{
  "task_id": "task-123",
  "payload": {
    "latitude": 37.78,
    "longitude": -122.42
  },
  "redactions": ["Rounded to street-level precision", "Removed altitude"],
  "timestamp": "2025-10-18T12:00:00Z"
}
```

### ToolCall
```json
{
  "tool_call_id": "call-456",
  "name": "foundation_models_generate",
  "args": {
    "prompt": "Summarize this text...",
    "max_tokens": 100
  },
  "locality": "local"
}
```

### HumanAssistRequest
```json
{
  "agent_id": "map-search-agent",
  "reason": "Need clarification on preferred coffee shop atmosphere",
  "context_handle": "session-789",
  "suggested_questions": [
    "Do you prefer quiet or lively atmosphere?",
    "Indoor or outdoor seating?"
  ]
}
```

### TaskResult
```json
{
  "task_id": "task-123",
  "artifacts": [
    {
      "artifact_type": "data",
      "content": {
        "coffee_shops": [...]
      }
    }
  ],
  "citations": [
    {
      "source": "Google Maps API",
      "url": "https://maps.google.com"
    }
  ],
  "policy_tag": "search-results",
  "timestamp": "2025-10-18T12:01:00Z"
}
```

## LocalAIAgent Responsibilities

### Capabilities Exposure
- Apple Intelligence: Foundation Models, Writing Tools, Image Playground
- Sensors: Location, Camera, Microphone, Motion, Nearby Devices, Compass
- Platform Info: iOS/macOS version, device capabilities

### Sensor Policy Enforcement
- **Permission**: Prompt user for sensor access
- **Scope**: Enforce minimal/standard/detailed data levels
- **Rate Limiting**: Max samples per second per sensor type
- **Redaction**: Remove sensitive data based on scope
- **Retention**: Auto-delete data after specified duration
- **Audit Trail**: Log all sensor access with policy tags

### A2A Communication
- Publishes as `_a2a._tcp.` mDNS service
- Accepts WebSocket connections
- Handles JSON-RPC 2.0 requests:
  - `sensor_request` - Access device sensors
  - `tool_call` - Execute local AI capabilities
  - `chat_open` - Open human chat channel

### Chat Routing
- Human can connect directly to LocalAIAgent
- LocalAIAgent can bridge chat to other agents
- No coordination - just hosting the channel

## Decision Policy

### When to Execute Locally (On-Device)
- Device is eligible (iOS 26+, macOS 26+)
- Small to medium reasoning tasks
- Privacy-sensitive data processing
- Sensor-tight loops
- Real-time responsiveness needed

### When to Execute Remotely (via Orchestrator)
- Heavy reasoning or large models
- Cross-agent tool chains
- Web search or RAG
- Long-running jobs
- Multi-step workflows

**Decision Authority**: Always the Orchestrator (never LocalAIAgent)

## Offline / Degraded Mode

When Orchestrator is unreachable:
- Human can still chat directly with LocalAIAgent over A2A
- LocalAIAgent can fulfill device-local tasks independently
- Foundation Models, Writing Tools, Image Playground remain available
- Sensor access continues to work with policy enforcement
- No global planning, but local capabilities remain functional

## Sensor Types & Policies

| Sensor | Scope Levels | Max Rate | Platform Support |
|--------|-------------|----------|------------------|
| Location | minimal (city), standard (street), detailed (GPS) | 1 Hz | iOS, macOS, tvOS, watchOS |
| Camera | N/A | 60 Hz | iOS, macOS |
| Microphone | N/A | 60 Hz | iOS, macOS |
| Motion | N/A | 100 Hz | iOS, watchOS |
| Nearby Devices | N/A | 10 Hz | iOS, macOS |
| Compass | N/A | 10 Hz | iOS, watchOS |
| Ambient Light | N/A | 10 Hz | iOS |
| Barometer | N/A | 10 Hz | iOS, watchOS |

### Scope Examples

**Location - Minimal:**
```json
{
  "latitude": 37.0,
  "longitude": -122.0
}
```
Redactions: Rounded to city-level, removed altitude

**Location - Standard:**
```json
{
  "latitude": 37.78,
  "longitude": -122.42
}
```
Redactions: Rounded to street-level, removed altitude

**Location - Detailed:**
```json
{
  "latitude": 37.7749295,
  "longitude": -122.4194155,
  "altitude": 16.0,
  "horizontalAccuracy": 5.0,
  "verticalAccuracy": 3.0
}
```
Redactions: None

## Technology Stack

### iOS/macOS (LocalAIAgent)
- **Language**: Swift 6.2
- **Concurrency**: Swift Structured Concurrency, Actors
- **Networking**: Network.framework (NWListener, NWConnection)
- **Protocol**: JSON-RPC 2.0 over WebSocket
- **Discovery**: mDNS via Bonjour
- **Sensors**: CoreLocation, CoreMotion, AVFoundation
- **AI**: Foundation Models (iOS 26), Writing Tools, Image Playground

### Orchestrator (arkavo-edge)
- **Language**: Rust
- **Framework**: arkavo-protocol crate
- **Transport**: HTTP/WebSocket with mTLS support
- **Protocol**: A2A (agent-to-agent) over JSON-RPC 2.0
- **Discovery**: mDNS integration
- **Security**: rustls (no OpenSSL dependency)

## Security Considerations

### Sensor Access
- All sensor requests require user permission
- Policy enforcement at the bridge layer
- Audit logging with policy tags
- Automatic data deletion after retention period
- Redaction applied based on scope

### A2A Communication
- mTLS support for agent-to-agent connections
- Certificate-based authentication
- WebSocket over TLS
- No plaintext communication in production

### Privacy
- On-device AI processing (no cloud round-trip)
- Data minimization via scope enforcement
- Automatic redaction of sensitive fields
- User consent required for all sensor access

## File Organization

### iOS App Structure
```
Arkavo/
├── ArkavoAgent/               # Swift Package for A2A agent functionality
│   └── Sources/ArkavoAgent/
│       ├── A2AMessages.swift         # Protocol message types
│       ├── LocalAIAgent.swift        # Core agent implementation
│       ├── SensorBridge.swift        # Sensor access with policy
│       ├── AgentConnection.swift      # WebSocket client
│       ├── AgentDiscoveryService.swift # mDNS discovery
│       └── AgentChatSession.swift    # Chat session management
├── Arkavo/
│   └── Arkavo/
│       ├── AgentService.swift        # UI-layer agent service
│       ├── AgentDiscoveryView.swift  # Agent browser
│       ├── AgentChatView.swift       # Chat UI
│       └── AppIntents/               # Siri/Spotlight integration
└── ARCHITECTURE.md            # This file
```

### arkavo-edge Structure
```
arkavo-edge/
└── crates/
    └── arkavo-protocol/
        └── src/
            ├── types.rs          # A2A protocol types
            ├── server.rs         # WebSocket server
            ├── task_executor.rs  # Task execution
            └── task_planner.rs   # Task planning (TBD)
```

## Future Enhancements

### Short Term
- AppleIntelligenceClient integration with Foundation Models
- WritingToolsIntegration for text refinement
- ImagePlaygroundIntegration for image synthesis
- App Intents for Siri/Spotlight triggers
- Orchestrator task planning implementation

### Long Term
- Multi-device coordination (iPhone + Mac + Watch)
- Federated learning across devices
- Enhanced privacy with differential privacy
- Cross-platform agent discovery beyond Apple ecosystem
- Tool marketplace for third-party tools

## References

- [A2A Protocol Specification](../arkavo-edge/crates/arkavo-protocol/README.md)
- [arkavo-edge AGENTS.md](../arkavo-edge/AGENTS.md)
- [iOS AGENTS.md](./AGENTS.md)
