# ArkavoAgentTest

Command-line test harness for the ArkavoAgent Swift package. Test mDNS discovery, WebSocket connections, JSON-RPC calls, and chat sessions with arkavo-edge agents.

## Prerequisites

- macOS 14+ with Swift 6.2
- arkavo-edge agent running on the same local network

## Quick Start

### 1. Start arkavo-edge Agent

In a separate terminal:
```bash
cd ~/Projects/arkavo/arkavo-edge
arkavo
```

The agent will advertise itself on `_a2a._tcp.local.`

### 2. Run Tests

```bash
# Run all tests
./Scripts/test-agent.sh

# Run specific test
./Scripts/test-agent.sh --test discovery

# Interactive mode
./Scripts/test-agent.sh --interactive
```

## Usage

### Automated Tests

Run all tests in sequence:
```bash
cd ArkavoAgentTest
swift run ArkavoAgentTest --test-all
```

Run specific test:
```bash
swift run ArkavoAgentTest --test discovery
swift run ArkavoAgentTest --test connection
swift run ArkavoAgentTest --test rpc
swift run ArkavoAgentTest --test chat
```

### Interactive CLI

Launch interactive mode for manual testing:
```bash
swift run ArkavoAgentTest --interactive
```

#### Interactive Commands

**Discovery:**
- `discover` - Start mDNS discovery for agents
- `list` - Show discovered agents
- `status` - Display connection status

**Connection:**
- `connect <n>` - Connect to agent number n
- `disconnect <n>` - Disconnect from agent

**Chat:**
- `chat <n>` - Open chat session with agent
- `send <message>` - Send message to active chat
- `close` - Close active chat session

**RPC:**
- `rpc <method>` - Call JSON-RPC method (e.g., `rpc rpc.discover`)

**General:**
- `help` - Show available commands
- `quit` - Exit CLI

### Example Interactive Session

```
$ swift run ArkavoAgentTest --interactive

ArkavoAgent Interactive CLI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Type 'help' for available commands

> discover
📡 Starting mDNS discovery...
⏳ Waiting for agents (5s)...
✓ Found 1 agent(s)

Discovered Agents:
─────────────────────────────────────────────
[0] ○ local-agent
    URL:     ws://192.168.1.100:8080/ws
    Model:   ollama/codellama
    Purpose: Coding assistant
    Status:  Disconnected

> connect 0
🔌 Connecting to local-agent...
✅ Connected successfully

> chat 0
💬 Chat session opened with local-agent
   Session ID: 550e8400-e29b-41d4-a716-446655440000
   Use 'send <message>' to chat
   Use 'close' to end session

> send Hello, can you help me with Swift code?
→ You: Hello, can you help me with Swift code?
✓ Message sent

> close
✓ Chat session closed

> quit
👋 Goodbye!
```

## Test Scenarios

### Test 1: mDNS Discovery
- Starts NetService browser for `_a2a._tcp.local.`
- Waits 10 seconds for agents to appear
- Parses TXT records (agent_id, model, purpose)
- Displays all discovered agents

### Test 2: WebSocket Connection
- Connects to first discovered agent
- Verifies connection status
- Checks transport-level connectivity
- Cleanly disconnects

### Test 3: JSON-RPC Request/Response
- Sends `rpc.discover` request
- Validates JSON-RPC 2.0 response format
- Handles success and error responses
- Verifies request ID correlation

### Test 4: Chat Session
- Opens authenticated chat session
- Sends test message
- Waits for response (note: full streaming not implemented in test)
- Closes session properly

## Troubleshooting

### No agents discovered
- Ensure arkavo-edge is running: `arkavo`
- Check both devices on same WiFi network
- Verify no firewall blocking mDNS (port 5353)
- Check Info.plist has `_a2a._tcp` in NSBonjourServices

### Connection failed
- Verify arkavo-edge WebSocket server is running
- Check firewall allows connections on agent port
- Try `ws://` URL (not `wss://` unless mTLS configured)

### Build errors
- Ensure Swift 6.2+ installed: `swift --version`
- Check ArkavoAgent package builds: `cd ../ArkavoAgent && swift build`
- Clean build: `swift package clean`

## Development

### Adding New Tests

Edit `Sources/ArkavoAgentTest/AgentTester.swift`:

```swift
func testN_YourTest() async {
    print("🧪 Test N: Your Test Name")
    print("─────────────────────────────────────────────────\n")

    // Your test logic here

    print("✅ PASS\n")
}
```

Update `runAllTests()` to include your test.

### Modifying Interactive CLI

Edit `Sources/ArkavoAgentTest/InteractiveCLI.swift`:

```swift
case "yourcommand":
    await cmdYourCommand()
```

## CI/CD Integration

Run tests in automation:
```bash
#!/bin/bash
# Start arkavo-edge agent in background
arkavo &
AGENT_PID=$!

# Wait for startup
sleep 2

# Run tests
cd ArkavoAgentTest
swift test

# Cleanup
kill $AGENT_PID
```

## Next Steps

Once all tests pass:
1. ✅ Verify discovery works consistently
2. ✅ Validate connection stability
3. ✅ Test chat protocol compatibility
4. → Integrate ArkavoAgent into iOS app
5. → Build production UI

## Related

- [ArkavoAgent Package](../ArkavoAgent/README.md)
- [arkavo-edge](https://github.com/arkavo-org/arkavo-edge)
- [A2A Protocol Spec](../ArkavoAgent/IMPLEMENTATION.md)
