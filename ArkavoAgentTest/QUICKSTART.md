# ArkavoAgentTest Quick Start

## 5-Minute Test

### Terminal 1: Start arkavo-edge Agent
```bash
cd ~/Projects/arkavo/arkavo-edge
arkavo
```

You should see:
```
Starting agent...
Registering mDNS service for agent: <agent-id>
mDNS service registered successfully
WebSocket server listening on ws://0.0.0.0:8080/ws
```

### Terminal 2: Run Test CLI
```bash
cd ~/Projects/arkavo/app
./Scripts/test-agent.sh
```

Expected output:
```
🧪 ArkavoAgent Test Suite
═══════════════════════════════════════════════════

✓ arkavo-edge agent detected

🔨 Building test tool...
...

🚀 Running all tests...

📡 Test 1: mDNS Discovery
─────────────────────────────────────────────────

✓ Started mDNS discovery for _a2a._tcp.local.
⏳ Waiting for agents (10s timeout)...
  1s...  2s...  3s...

✅ PASS: Discovered 1 agent(s)

Agent [0]:
  ID:       local-agent
  Name:     local-agent
  URL:      ws://192.168.1.100:8080/ws
  Model:    ollama/codellama
  Purpose:  Coding assistant
  ...

🔌 Test 2: WebSocket Connection
─────────────────────────────────────────────────

✅ PASS: Connected successfully
...

📞 Test 3: JSON-RPC Request/Response
─────────────────────────────────────────────────

✅ PASS: Received response
...

💬 Test 4: Chat Session
─────────────────────────────────────────────────

✅ PASS: Session closed

✅ All tests complete
```

## Interactive Testing

```bash
./Scripts/test-agent.sh --interactive
```

Try these commands:
```
> discover
> list
> connect 0
> status
> chat 0
> send What is the A2A protocol?
> close
> quit
```

## Single Test

```bash
./Scripts/test-agent.sh --test discovery
```

## Troubleshooting

### "No agents discovered"
1. Check arkavo-edge is running
2. Verify both on same network
3. Check firewall settings

### "Connection failed"
1. Note the port from arkavo-edge output
2. Verify it matches agent URL
3. Try `telnet <host> <port>` to test connectivity

## Next Steps

1. ✅ All tests pass → Integrate into iOS app
2. ❌ Tests fail → Debug with `--interactive` mode
3. File issues in ArkavoAgent package

## Example arkavo-edge Output

```
$ arkavo

Arkavo Edge Agent v0.30.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Agent ID: local-agent-a1b2c3d
Purpose:  General AI assistant
Model:    ollama/llama3

Network Configuration:
  mDNS Service: _a2a._tcp.local.
  WebSocket:    ws://0.0.0.0:8080/ws
  TXT Records:
    agent_id=local-agent
    model=ollama/llama3
    purpose=General AI assistant

✓ Agent ready for connections
```
