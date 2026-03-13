# Test Coverage Analysis

**Date:** 2026-03-13
**Scope:** Full codebase (Arkavo, ArkavoKit, ArkavoMediaKit, ArkavoCreator, HYPERforum, MuseCore)

## Current State

| Project | Source Files | Test Files | Test Methods | Coverage Quality |
|---------|-------------|------------|--------------|-----------------|
| Arkavo | ~111 | 23 (13 unit + 10 UI) | ~106 | Moderate — focused on crypto/contacts |
| ArkavoKit | ~90 | 7 | ~40 | **Weak** — vast majority untested |
| ArkavoMediaKit | ~35 | 14 | ~215 | Good — strong FMP4/HLS/DRM coverage |
| ArkavoCreator | ~70 | 23 (14 unit + 9 UI) | ~150 | Moderate — strong avatar/VRM, weak elsewhere |
| HYPERforum | ~12 | 6 (1 unit + 5 UI) | ~12 | **Weak** — minimal unit tests |
| MuseCore | ~35 | 0 | 0 | **None** — completely untested |

**Total: ~353 source files, ~77 test files, ~542 test methods**

---

## High-Priority Gaps (Security & Data Integrity)

### 1. AuthenticationManager — `Arkavo/Arkavo/AuthenticationManager.swift` (578 lines, 0 tests)

Handles the entire auth flow including Apple Sign-In, token management, and session lifecycle. A bug here could lock users out or expose auth tokens.

**Recommended tests:**
- Token refresh logic and expiry edge cases
- Session state transitions (signed in → signed out → expired)
- Error handling for network failures during auth
- Keychain credential persistence

### 2. ArkavoClient — `ArkavoKit/Sources/ArkavoSocial/ArkavoClient.swift` (1,700 lines, 0 tests)

The largest untested file. Main backend API client handling WebSocket communication, event routing, and server interactions.

**Recommended tests:**
- Message serialization/deserialization round-trips
- Connection state machine (connecting → connected → disconnected → reconnecting)
- Event dispatch to correct delegate methods
- Reconnection logic after disconnects and backoff behavior

### 3. KeychainManager — `ArkavoKit/Sources/ArkavoSocial/KeychainManager.swift` (681 lines, 0 tests)

Stores cryptographic keys and credentials. Incorrect behavior could cause data loss or security vulnerabilities.

**Recommended tests:**
- Store/retrieve/delete operations for each key type
- Error handling for keychain access failures
- Behavior when keychain items don't exist
- Key migration and update scenarios

### 4. AgeVerificationManager — `Arkavo/Arkavo/AgeVerificationManager.swift` (245 lines, 0 tests)

Compliance-critical: age verification gates access to content.

**Recommended tests:**
- Age threshold validation with various dates of birth
- ID scanning result parsing
- Verification state persistence across sessions
- Edge cases: exactly at age boundary, future dates, invalid input

---

## High-Priority Gap: MuseCore (35+ files, 0 tests)

MuseCore is an entire untested module providing avatar animation, lip-sync, LLM integration, and sentiment analysis. Key areas needing tests:

### Lip-Sync Pipeline
- `LipSyncCoordinator.swift` — orchestration of text → phonemes → visemes → animation
- `TextToPhonemeMapper.swift` — text-to-phoneme conversion correctness
- `PhonemeToVisemeMapper.swift` — phoneme-to-viseme mapping accuracy
- `VisemeScheduler.swift` — timing and scheduling of visemes
- `JapanesePhonemeMapper.swift` — Japanese language support

### LLM Integration
- `ConversationManager.swift` — conversation history and context management
- `IntentClassifier.swift` — intent classification accuracy
- `FenceParser.swift` — LLM response parsing (structured output extraction)
- `ToolCallingStrategy.swift` — tool selection logic
- `LLMFallbackChain.swift` — fallback behavior when primary LLM fails

### Animation
- `ProceduralAnimationController.swift` — procedural animation correctness
- `SpeakingDynamicsLayer.swift` — speech-driven animation
- `EmotionMapper.swift` — emotion-to-animation mapping
- `SentimentAnalyzer.swift` — sentiment detection accuracy

---

## Medium-Priority Gaps (Core Business Logic)

### 5. ArkavoMessageRouter — `Arkavo/Arkavo/ArkavoMessageRouter.swift` (485 lines, 0 tests)

Routes messages between components. Incorrect routing causes silent message loss.

**Recommended tests:**
- Message routing by type/destination
- Handler registration and deregistration
- Concurrent message delivery safety
- Unknown message type handling

### 6. ChatViewModel — `Arkavo/Arkavo/ChatViewModel.swift` (510 lines, 0 tests)

Drives the main chat UX. Users interact with this every session.

**Recommended tests:**
- Message ordering and deduplication
- Send state transitions (sending → sent → failed)
- Offline queuing behavior
- Pagination and history loading

### 7. MessageQueueManager — `Arkavo/Arkavo/MessageQueueManager.swift` (240 lines, 0 tests)

Queues messages for reliable delivery.

**Recommended tests:**
- FIFO ordering guarantees
- Retry logic for failed sends
- Queue persistence across app restarts
- Queue capacity limits and overflow behavior

### 8. AgentChatSession — `ArkavoKit/Sources/ArkavoAgent/AgentChatSession.swift` (501 lines, 0 tests)

Manages AI agent chat sessions.

**Recommended tests:**
- Session lifecycle (create → message → close)
- Message history management and context windowing
- Error handling for agent unavailability
- Concurrent message handling

### 9. AgentManager — `ArkavoKit/Sources/ArkavoAgent/AgentManager.swift` (185 lines, 0 tests)

Manages agent registration and discovery.

**Recommended tests:**
- Agent registration and deregistration
- Discovery state machine
- Connection failure handling and retry

### 10. AICouncilManager — `HYPERforum/HYPERforum/AICouncilManager.swift` (619 lines, 0 tests)

AI council decision-making — complex multi-agent orchestration.

**Recommended tests:**
- Council session creation and management
- Vote aggregation logic
- Timeout and quorum handling
- Provider fallback behavior

---

## Medium-Priority Gaps (Media & Streaming)

### 11. RTMPPublisher — `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift` (1,712 lines, 0 tests)

Largest file in ArkavoKit. RTMP live streaming protocol implementation.

**Recommended tests:**
- RTMP handshake sequence (C0/C1/C2 → S0/S1/S2)
- Chunk stream encoding/decoding
- FLV tag construction
- Connection state machine
- Error handling for malformed server responses

### 12. RTMPSubscriber — `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPSubscriber.swift` (1,111 lines, 0 tests)

Receiving side of RTMP streaming.

**Recommended tests:**
- Stream subscription protocol negotiation
- Media data parsing and demuxing
- Reconnection behavior
- Handling of corrupted stream data

### 13. RecordingSession — `ArkavoKit/Sources/ArkavoRecorder/RecordingSession.swift` (932 lines, 0 tests)

Core recording orchestration.

**Recommended tests:**
- Recording state machine (idle → recording → paused → stopped)
- Source attachment/detachment lifecycle
- Output file management and cleanup
- Error recovery during recording

### 14. AudioMixer — `ArkavoKit/Sources/ArkavoRecorder/AudioMixer.swift` (201 lines, 0 tests)

Multi-track audio mixing.

**Recommended tests:**
- Volume level mixing correctness
- Source add/remove during active mixing
- Sample rate conversion handling

---

## Lower-Priority Gaps

### 15. PatreonClient — `ArkavoKit/Sources/ArkavoSocial/PatreonClient.swift` (1,394 lines, 0 tests)

OAuth and API integration for Patreon.

**Recommended tests:**
- OAuth token exchange flow
- API response parsing (memberships, tiers, campaigns)
- Token refresh and expiry handling
- Error responses from Patreon API

### 16. ArkavoWebSocket — `Arkavo/Arkavo/ArkavoWebSocket.swift` (347 lines, 0 tests)

WebSocket transport layer.

**Recommended tests:**
- Connection lifecycle (open → message → close)
- Ping/pong keep-alive handling
- Binary vs text message framing
- Reconnection on unexpected disconnect

### 17. EncryptionManager (HYPERforum) — `HYPERforum/HYPERforum/EncryptionManager.swift` (268 lines, ~12 tests)

Existing tests are minimal for a security component.

**Recommended additional tests:**
- Round-trip encryption/decryption with various payload sizes
- Key rotation scenarios
- Edge cases: empty data, max-size payloads, corrupted ciphertext
- Thread safety under concurrent encrypt/decrypt

### 18. Social Clients (BlueskyClient, YouTubeClient, RedditClient)

All social API clients in ArkavoKit/Sources/ArkavoSocial/ lack tests.

**Recommended tests:**
- API response parsing for each platform
- OAuth flow handling
- Error/rate-limiting response handling

---

## Structural Recommendations

### 1. ArkavoKit has the weakest test-to-source ratio
Only 7 test files for ~90 source files across 7 modules. `ArkavoSocial` (18 files), `ArkavoAgent` (17 files), `ArkavoRecorder` (21 files), and `ArkavoStreaming` (14 files) are largely untested.

### 2. MuseCore is completely untested
35+ source files with zero test coverage. Given it handles LLM integration, animation math, and lip-sync timing, this is a significant risk area.

### 3. No tests for networking error handling
WebSocket, RTMP, and HTTP networking exist across multiple modules, but connection failure, timeout, and retry logic is untested.

### 4. No tests for SwiftData schema migration
SwiftData models are used extensively (Account, Profile, Stream, Thought) but there are no migration tests.

### 5. Missing adversarial/edge-case tests in existing suites
The key exchange tests cover happy paths well but don't test malformed messages, replay attacks, or out-of-order operations.

### 6. No snapshot/regression tests for UI
UI tests focus on App Store screenshots and navigation flows rather than visual regression detection.

---

## Recommended Priority Order

If starting from scratch, maximum impact with minimum effort:

| Priority | Target | Lines | Why |
|----------|--------|-------|-----|
| 1 | `AuthenticationManager` | 578 | Security-critical, testable in isolation |
| 2 | `ArkavoClient` | 1,700 | Central networking hub, largest untested file |
| 3 | `KeychainManager` | 681 | Security-critical, straightforward to test |
| 4 | MuseCore lip-sync pipeline | ~500 | Pure logic (text→phoneme→viseme), easy to unit test |
| 5 | `ArkavoMessageRouter` | 485 | Core message bus, easy to unit test |
| 6 | `MessageQueueManager` | 240 | Reliability-critical, pure logic |
| 7 | MuseCore LLM integration | ~600 | FenceParser and IntentClassifier are pure logic |
| 8 | `RTMPPublisher` protocol logic | 1,712 | Handshake/chunk encoding is testable in isolation |
| 9 | `ChatViewModel` | 510 | User-facing, high interaction frequency |
| 10 | `AICouncilManager` | 619 | Complex orchestration prone to subtle bugs |
