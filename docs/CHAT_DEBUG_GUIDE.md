# Chat Debugging Guide - iOS to arkavo-edge

## Problem Summary

The iOS app was connecting to arkavo-edge agents but messages weren't sending/receiving. The issue was **WebSocket request timeouts** during the `chat_stream` subscription call.

## Root Causes Identified

### 1. Parameter Structure - Nested Message Object (FIXED ✅)
**Location:** `ArkavoAgent/Sources/ArkavoAgent/AgentChatSession.swift:239-257`

**Problem:**
The server expects JSON-RPC parameters with **named fields** matching the method signature, not positional.

**Fix:**
Keep the nested structure with `session_id` and `message` as separate fields:
```swift
// CORRECT - nested structure with named parameters
let params: [String: Any] = [
    "session_id": sessionId,
    "message": messageParams  // UserMessage object with content, attachments
]
```

The arkavo-edge JSON-RPC trait expects:
```rust
async fn chat_send(&self, session_id: String, message: UserMessage)
```

This means parameters should be:
```json
{
  "session_id": "abc-123",
  "message": {
    "content": "Hello",
    "attachments": null
  }
}
```

### 2. Missing Comprehensive Logging (FIXED ✅)

Added detailed logging at every step of the request/response flow to diagnose issues.

**iOS Files Modified:**
- `AgentChatSession.swift` - sendMessage method
- `AgentWebSocketTransport.swift` - sendRequest, handleMessage
- `AgentStreamHandler.swift` - subscribe method

**Rust Files Modified:**
- `server.rs` - chat_send, chat_stream methods

## Changes Made

### iOS Changes

#### File: `AgentChatSession.swift`
```swift
// Lines 220-267
- Fixed parameter flattening (messageDict + session_id at same level)
- Added 8 log points:
  - Sending message
  - Session validation
  - Connection validation
  - UserMessage creation
  - Parameter construction (with keys logged)
  - Response received
  - Error handling
  - Success confirmation
```

#### File: `AgentWebSocketTransport.swift`
```swift
// Lines 106-144 (sendRequest)
- Log request method and ID
- Log full JSON payload being sent
- Log response received
- Log any errors

// Lines 163-204 (handleMessage)
- Log all received messages (first 200 chars)
- Log notification detection
- Log response decoding
- Log pending request matching
- Log unmatched responses (with pending request IDs)
- Log decoding errors with message text
```

#### File: `AgentStreamHandler.swift`
```swift
// Lines 40-82 (subscribe)
- Log subscription request
- Log parameters
- Log subscription response
- Log subscription ID
- Log errors
- Log completion
```

### Rust Changes

#### File: `server.rs`
```rust
// Lines 750-781 (chat_send)
- Log when chat_send is called with session_id and content length
- Log rate limit checks
- Log forwarding to session manager
- Log success/failure
- Error logging with details

// Lines 803-862 (chat_stream)
- Log subscription request
- Log subscription acceptance
- Log delta stream retrieval
- Log delta forwarding task start
- Log each delta forwarded (with count)
- Log client disconnection
- Log task completion with total delta count
- Log session not found errors
```

## Testing Instructions

### Step 1: Rebuild and Deploy

**iOS:**
```bash
cd /Users/paul/Projects/arkavo/app
# Rebuild iOS app with new logging
# Deploy to device/simulator
```

**arkavo-edge:**
```bash
cd /Users/paul/Projects/arkavo/arkavo-edge
cargo build --release
# Restart the agent with logging enabled
RUST_LOG=info,arkavo_protocol=debug ./target/release/arkavo
```

### Step 2: Monitor Logs

**Terminal 1 - arkavo-edge logs:**
```bash
# Watch for these log lines:
# - "chat_send called" - confirms request received
# - "Forwarding message to chat session manager" - routing works
# - "Message sent successfully to session" - session manager processed it
# - "chat_stream subscription requested" - subscription call received
# - "Subscription accepted successfully" - subscription established
# - "Delta forwarder task started" - streaming ready
# - "Forwarding delta to client" - deltas being sent
```

**Xcode Console - iOS logs:**
```
# Watch for these patterns:
# [AgentChatSessionManager] Sending message in session: ...
# [AgentChatSessionManager] Calling chat_send with params: ...
# [AgentWebSocketTransport] Sending request: method=chat_send, id=...
# [AgentWebSocketTransport] JSON payload: {"jsonrpc":"2.0","method":"chat_send",...}
# [AgentWebSocketTransport] Request sent, waiting for response...
# [AgentWebSocketTransport] Received message: ...
# [AgentWebSocketTransport] Received response for request ...
# [AgentChatSessionManager] Received response: ...
# [AgentChatSessionManager] Message sent successfully
```

### Step 3: Test Chat Flow

1. **Start arkavo-edge agent:**
   ```bash
   RUST_LOG=info,arkavo_protocol=debug ./target/release/arkavo
   ```

2. **Open iOS app** and navigate to Agents tab

3. **Connect to agent:**
   - Tap on the arkavo-edge agent
   - Tap "Connect"
   - Wait for "Connected" status

4. **Open chat session:**
   - Tap "Start New Chat"
   - Should see session created log

5. **Send test message:**
   - Type "Hello, agent!"
   - Tap send
   - Watch both logs simultaneously

### Step 4: Diagnose Issues

#### If request times out again:

**Check iOS logs for:**
```
[AgentWebSocketTransport] JSON payload: ...
```
Copy the payload and verify it has the correct structure.

**Check arkavo-edge logs for:**
```
chat_send called
```
If you DON'T see this, the request isn't reaching the server → network issue or WebSocket connection broken.

#### If server receives request but doesn't respond:

**Check arkavo-edge logs for:**
```
Failed to send message to session
```
This means the session doesn't exist or there's an LLM issue.

#### If subscription times out:

**Check arkavo-edge logs for:**
```
chat_stream subscription requested
Accepting chat_stream subscription
Subscription accepted successfully
```

If any of these are missing, the subscription protocol is failing.

## Expected Log Flow (Success Case)

### iOS App:
```
[AgentChatSessionManager] Sending message in session: abc-123
[AgentChatSessionManager] Created UserMessage with content length: 13
[AgentChatSessionManager] Calling chat_send with params: ["attachments", "content", "session_id"]
[AgentWebSocketTransport] Sending request: method=chat_send, id=xyz-456
[AgentWebSocketTransport] JSON payload: {"jsonrpc":"2.0","method":"chat_send","params":{"session_id":"abc-123","content":"Hello, agent!"},"id":"xyz-456"}
[AgentWebSocketTransport] Request sent, waiting for response...
[AgentWebSocketTransport] Received message: {"jsonrpc":"2.0","id":"xyz-456","result":null}
[AgentWebSocketTransport] Decoded response with id: xyz-456
[AgentWebSocketTransport] Matched pending request for id: xyz-456
[AgentWebSocketTransport] Received response for request xyz-456: success
[AgentChatSessionManager] Received response: success
[AgentChatSessionManager] Message sent successfully
```

### arkavo-edge:
```
INFO  chat_send called session.id=abc-123 content_len=13
INFO  Forwarding message to chat session manager session.id=abc-123
INFO  Message sent successfully to session session.id=abc-123
INFO  chat_stream subscription requested session.id=abc-123
INFO  Accepting chat_stream subscription session.id=abc-123
INFO  Subscription accepted successfully session.id=abc-123
INFO  Got delta stream, spawning forwarder task session.id=abc-123
INFO  Delta forwarder task started session.id=abc-123
INFO  Forwarding delta to client session.id=abc-123 delta_count=1
INFO  Forwarding delta to client session.id=abc-123 delta_count=2
...
```

## Common Issues and Solutions

### Issue: "No pending request found for id: xyz"

**Cause:** Response received but request was already cleaned up (timeout) or ID mismatch.

**Solution:**
- Check timeout values (default 30s)
- Verify request ID in logs matches response ID
- Check if request actually sent before response arrived

### Issue: "Session not found for chat_stream subscription"

**Cause:** Trying to subscribe to a session that doesn't exist or was closed.

**Solution:**
- Verify `chat_open` was called first
- Check session_id in logs matches
- Ensure session wasn't closed prematurely

### Issue: WebSocket connection drops during chat

**Cause:** Network instability or connection timeout.

**Solution:**
- Check WiFi connection
- Verify firewall/network allows WebSocket traffic
- Check arkavo-edge isn't crashing (check process)
- Look for connection state logs

## Next Steps

After confirming chat works:
1. Test with longer messages
2. Test with multiple concurrent sessions
3. Test streaming with long responses
4. Test reconnection after disconnect
5. Proceed to orchestrator task planning implementation

## Files Changed

**iOS:**
- `/Users/paul/Projects/arkavo/app/ArkavoAgent/Sources/ArkavoAgent/AgentChatSession.swift`
- `/Users/paul/Projects/arkavo/app/ArkavoAgent/Sources/ArkavoAgent/AgentWebSocketTransport.swift`
- `/Users/paul/Projects/arkavo/app/ArkavoAgent/Sources/ArkavoAgent/AgentStreamHandler.swift`

**Rust:**
- `/Users/paul/Projects/arkavo/arkavo-edge/crates/arkavo-protocol/src/server.rs`

**Total Changes:**
- iOS: ~60 lines of logging
- Rust: ~30 lines of logging
- 1 critical parameter structure fix
