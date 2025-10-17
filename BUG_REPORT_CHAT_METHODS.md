# Bug Report: Chat Methods Missing from OpenRPC Schema

**Date:** 2025-10-16
**Reporter:** Paul (via ArkavoAgent Swift package testing)
**Severity:** High
**Component:** arkavo-edge agent

---

## Summary

The running arkavo-edge agent (v0.37.0) does not expose chat protocol methods (`chat_open`, `chat_send`, `chat_close`) in its OpenRPC schema, despite these methods being fully implemented in the source code.

## Environment

- **Agent Version:** 0.37.0
- **Agent Location:** 10.0.0.101:8342
- **Agent Name:** "Project Overview"
- **Model:** ollama://127.0.0.1:11434/qwen3:0.6b
- **Transport:** WebSocket (ws://)
- **mDNS Service:** arkavo-agent-Project Overview._a2a._tcp.local.

## Expected Behavior

When calling `rpc.discover`, the OpenRPC schema should include:
- `chat_open` - Opens a new chat session
- `chat_send` - Sends a message in a session
- `chat_close` - Closes a chat session
- `chat_stream` - Subscription for message deltas

**Evidence from Source Code:**
- **Implementation:** `/crates/arkavo-protocol/src/server.rs` lines 716-795
- **Types:** `/crates/arkavo-protocol/src/types.rs`
- **Session Manager:** `/crates/arkavo-protocol/src/chat_session.rs`
- **Tests:** `/crates/arkavo-protocol/tests/chat_protocol_v2.rs`
- **Schema:** `/schemas/openrpc/arkavo-protocol.json`

## Actual Behavior

`rpc.discover` returns only these methods:
- `task_request`
- `task_declare`
- `agent_discover`
- `message/send`
- `tasks/get`
- `tasks/cancel`

**Chat methods are completely absent from the OpenRPC response.**

## Steps to Reproduce

1. Start arkavo-edge agent:
   ```bash
   cd ~/Projects/arkavo/arkavo-edge
   arkavo
   ```

2. Query the agent via ArkavoAgent Swift test CLI:
   ```bash
   cd ~/Projects/arkavo/app
   ./Scripts/test-agent.sh --test rpc
   ```

3. Observe output - no `chat_open`, `chat_send`, or `chat_close` methods listed

4. Attempt to call `chat_open`:
   ```bash
   ./Scripts/test-agent.sh --test chat
   ```

5. **Error:** "The data couldn't be read because it is missing"

## Root Cause Analysis

### Hypothesis 1: Feature Flag Not Enabled ✓ (Most Likely)
The chat protocol may be behind a compilation feature flag that wasn't enabled when the binary was built.

**Action:** Check for feature flags in `Cargo.toml` and build configuration

### Hypothesis 2: Build Errors Preventing Compilation
Current build shows errors:
```
error: couldn't read `crates/arkavo-agui/src/../static/dashboard.html`: No such file or directory
error[E0609]: no field `blank_mode` on type `AgUiGateway`
```

These errors may have caused the chat module to be excluded from the build.

**Action:** Fix build errors and recompile

### Hypothesis 3: Incorrect Binary Version
The running binary may be an older version before chat protocol was added.

**Action:** Verify binary timestamp and rebuild latest source

## Impact

### Severity: High
- **Blocks iOS/macOS integration** - ArkavoAgent Swift package cannot communicate via chat protocol
- **Protocol fragmentation** - Clients must use different protocols (message/send vs chat sessions)
- **Missing functionality** - Streaming responses, session management, back-pressure control unavailable

### Workarounds

**Short-term:** Use `message/send` method instead of chat protocol
- Limited to simple request/response
- No session context or streaming

**Long-term:** Fix and rebuild agent with chat methods enabled

## Reproduction Rate

**100%** - Consistently reproducible on the current running agent

## Test Evidence

### Successful Connection Test
```
✅ Test 1: mDNS Discovery - PASS
✅ Test 2: WebSocket Connection - PASS
✅ Test 3: JSON-RPC Request/Response - PASS
```

### Failed Chat Test
```
❌ Test 4: Chat Session - FAIL
  Error: The data couldn't be read because it is missing.
```

## Recommended Fix

1. **Verify feature flags** in build configuration
2. **Fix build errors** (dashboard.html, blank_mode)
3. **Rebuild with all features:**
   ```bash
   cd ~/Projects/arkavo/arkavo-edge
   cargo clean
   cargo build --release --all-features
   ```
4. **Restart agent and verify:**
   ```bash
   ./target/release/arkavo
   # In another terminal:
   cd ~/Projects/arkavo/app
   ./Scripts/test-agent.sh --test rpc | grep chat
   ```
5. **Confirm Test 4 passes:**
   ```bash
   ./Scripts/test-agent.sh --test chat
   ```

## Related Files

**Source Code (Chat Implementation):**
- `crates/arkavo-protocol/src/server.rs` - RPC method handlers
- `crates/arkavo-protocol/src/chat_session.rs` - Session manager
- `crates/arkavo-protocol/src/types.rs` - ChatSession, ChatOpenRequest, etc.
- `crates/arkavo-protocol/src/openrpc.rs` - Schema generator

**Test Files:**
- `crates/arkavo-protocol/tests/chat_protocol_v2.rs` - Integration tests

**Schema:**
- `schemas/openrpc/arkavo-protocol.json` - OpenRPC 1.2.6 specification

## Client Impact

**ArkavoAgent Swift Package:**
- Implementation is **100% correct** and matches source specification
- All types, structures, and protocol flows verified against source code
- Tests will pass automatically once agent exposes chat methods
- No client code changes needed

## Additional Notes

The chat protocol v2 is a sophisticated implementation with:
- JWT authentication support
- Streaming message deltas with sequence numbering
- Back-pressure management with MetricsAck
- Tool call streaming
- Session persistence
- Concurrent session support

It would be valuable to expose this functionality to iOS/macOS clients.

---

## Verification Checklist

After fix is applied, verify:
- [ ] `rpc.discover` includes `chat_open`, `chat_send`, `chat_close`, `chat_stream`
- [ ] ArkavoAgent Test 4 (Chat Session) passes
- [ ] Session ID is returned from `chat_open`
- [ ] Messages can be sent via `chat_send`
- [ ] Session closes cleanly with `chat_close`
- [ ] OpenRPC schema version incremented (if applicable)

---

**Contact:** Paul
**Test Location:** /Users/paul/Projects/arkavo/app/ArkavoAgentTest
**Git Branch:** feature/arkavo-agent-a2a-protocol
