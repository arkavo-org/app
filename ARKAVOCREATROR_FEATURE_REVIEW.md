# ArkavoCreator — Complete Feature Inventory & App Store Wire-Off Plan

**Date:** 2026-03-13
**Platform:** macOS 26

---

## Feature Inventory

Every discrete feature in the app, with implementation status and wire-off recommendation.

---

### F01. Video Recording
**Location:** `RecordView.swift`, `RecordViewModel.swift`, `RecordingSession` (ArkavoKit)
**Status:** SHIP

Records video from camera + optional screen capture to `.mov` (H.264). Full start/stop/pause/resume lifecycle. Output URL generated via security-scoped bookmarks to a user-chosen folder. Duration timer, audio level metering, and title validation (3–200 chars, no filesystem-invalid chars).

- Generates `arkavo_recording_YYYYMMDD_HHmmss.mov`
- Posts `Notification.Name.recordingCompleted` when done
- Integrates with Stream Monitor for real-time frame inspection

**Verdict:** Fully functional. No issues.

---

### F02. Audio-Only Recording
**Location:** `RecordViewModel.swift` (line 357: `isAudioOnly` check), `StudioState.swift`
**Status:** SHIP

When no camera, no desktop, and no avatar are enabled, records audio-only to `.m4a`. Shows waveform animation placeholder in the stage view. Microphone toggle and audio level meter work.

**Verdict:** Fully functional. Clean fallback when all visual sources are off.

---

### F03. Screen Capture
**Location:** `RecordViewModel.swift` (`refreshDesktopPreview`), `ScreenCaptureManager` (ArkavoKit)
**Status:** SHIP

Captures a selected display via `ScreenCaptureManager.availableScreens()`. Shows live desktop preview as `NSImage`. Screen picker in control bar shows all displays with primary star badge. Supports selecting/deselecting screens during a session.

**Verdict:** Fully functional. Uses ScreenCaptureKit (public API).

---

### F04. Multi-Camera
**Location:** `RecordViewModel.swift` (`selectedCameraIDs`, `MultiCameraLayout`), `InspectorPanel.swift`
**Status:** SHIP

Supports up to 4 simultaneous camera sources with layout strategies: `pictureInPicture`, `grid`. Camera list from `RecordingSession.availableCameras()`. Per-camera toggle in Inspector panel. Shows transport type label (USB, built-in, etc.).

**Verdict:** Fully functional.

---

### F05. Remote Camera Bridge
**Location:** `RecordViewModel.swift` (`remoteBridgeEnabled`, `actualPort`), `RemoteCameraServer` (ArkavoKit)
**Status:** SHIP

Runs a local WebSocket server (`RemoteCameraServer`) that accepts connections from external devices (e.g., iPhone running companion app). Auto-assigns port. Discovered remote cameras appear in the Inspector and can be selected as sources. Connection info: `arkavo://connect?host=<hostname>&port=<port>`.

**Verdict:** Functional. Works on LAN. Requires companion app on the remote device.

---

### F06. Floating Head (Person Segmentation)
**Location:** `RecordViewModel.swift` (`floatingHeadEnabled`), `PersonSegmentationProcessor` (ArkavoKit)
**Status:** SHIP

Removes background from camera feed in real-time, showing just the person silhouette over the stage. Toggle in `StudioState`. When enabled, camera PiP corner radius is removed (person shape is the border).

**Verdict:** Functional. Uses Vision framework (public API).

---

### F07. Watermark
**Location:** `RecordViewModel.swift` (`watermarkEnabled`, `watermarkPosition`, `watermarkOpacity`)
**Status:** SHIP

Always-on watermark overlay on recordings/streams. Configurable position (`WatermarkPosition`) and opacity (0.0–1.0, default 0.6). No UI toggle to disable (hardcoded `watermarkEnabled = true`).

**Verdict:** Functional. Position/opacity configurable in code; no user-facing toggle to disable.

---

### F08. RTMP Streaming to Twitch
**Location:** `StreamViewModel.swift`, `StreamView.swift`, `RTMPPublisher` (ArkavoKit)
**Status:** SHIP

RTMP publish to `rtmp://live.twitch.tv/app` with user-provided stream key. Twitch OAuth login in Advanced Settings to verify identity. Stream key stored in Keychain via `KeychainManager.saveStreamKey`. Bandwidth test mode appends `?bandwidthtest=true` to key. Real-time stats: bitrate, FPS, frames sent, bytes sent, duration.

- Stream key validation: 10–200 chars, alphanumeric + hyphens/underscores
- Key persisted per-platform in Keychain

**Verdict:** Fully functional. Complete OAuth + stream key + RTMP pipeline.

---

### F09. RTMP Streaming to YouTube
**Location:** `StreamViewModel.swift`, `StreamDestinationPicker.swift`, `YouTubeClient` (ArkavoKit)
**Status:** SHIP

RTMP publish to `rtmp://a.rtmp.youtube.com/live2`. YouTube OAuth via local HTTP server. "Fetch from YouTube" button auto-retrieves stream key via `youtubeClient.fetchStreamKey()`. Shows channel info (title, subscriber count, video count) after auth.

**Verdict:** Fully functional. Auto-fetch stream key is a nice UX.

---

### F10. RTMP Streaming to Custom Server
**Location:** `StreamViewModel.swift` (`.custom` case)
**Status:** SHIP

User enters any `rtmp://` or `rtmps://` URL. URL validation checks scheme, host presence, max 500 chars. Stream key input same as other platforms. Custom RTMP URL persisted via `KeychainManager.saveCustomRTMPURL`.

**Verdict:** Fully functional.

---

### F11. Arkavo Encrypted Streaming (NTDF)
**Location:** `StreamViewModel.swift` (`.arkavo` case), `RecordView.swift` (`startStreaming`)
**Status:** WIRE OFF

RTMP to `rtmp://100.arkavo.net:1935` with NanoTDF encryption via `session.startNTDFStreaming`. Requires Arkavo WebAuthn authentication. Uses hardcoded KAS URL `https://100.arkavo.net`. Stream key is fixed to `"live/creator"`.

- Dashboard card shows "End-to-end encrypted streaming is available" when authed
- `StreamDestinationPicker` disables Arkavo option if not authenticated

**Verdict:** Requires Arkavo backend. Reviewer cannot authenticate. Wire off the Arkavo option from `StreamPlatform.allCases`, or ensure graceful failure. The encrypted streaming feature itself works but is inaccessible without the backend.

---

### F12. Twitch OAuth Integration
**Location:** `TwitchAuthClient.swift`, `ContentView.swift` (dashboard card)
**Status:** SHIP

Full OAuth 2.0 authorization code flow. Fetches: username, profile image URL, follower count, live status, viewer count, channel description, stream key. Login via WebView presenter. Logout clears tokens. Refresh button for channel data.

**Verdict:** Fully functional.

---

### F13. YouTube OAuth Integration
**Location:** `YouTubeClient` (ArkavoKit), `ContentView.swift`
**Status:** SHIP

OAuth via local HTTP server redirect. Fetches channel info (title, subscriber count, video count) and stream key. Error handling for `YouTubeError.userCancelled`.

**Verdict:** Fully functional.

---

### F14. Patreon OAuth Integration
**Location:** `PatreonClient` (ArkavoKit), `PatreonView.swift`, `PatronManagementView.swift`
**Status:** SHIP (with caveat)

OAuth 2.0 flow. After auth, checks `isCreator()` to toggle creator-specific UI. Read operations: campaigns, patrons list, tier info. User identity view shows Patreon profile.

**Caveat:** `PatronManagementView` has toolbar actions with empty implementations:
- `sendMessageToSelected()` — empty body (line 90)
- `exportSelectedData()` — empty body (line 94)
- `removeSelected()` — empty body (line 98)
- Export menu: CSV/Excel/PDF buttons all have `/* TODO */` comments (lines 63-65)

**Verdict:** Read-only operations work. Remove or disable the Send Message, Export, and Remove toolbar actions before submission — a reviewer clicking these will see nothing happen.

---

### F15. Reddit OAuth Integration
**Location:** `RedditClient` (ArkavoKit), `ContentView.swift`
**Status:** SHIP

OAuth flow with stored tokens. Dashboard card shows login button or root view when authenticated. `loadStoredTokens()` on app launch.

**Verdict:** Functional. Minimal feature surface (auth + user info).

---

### F16. Bluesky Integration
**Location:** `BlueskyClient` (ArkavoKit), `ContentView.swift` (`BlueskyLoginView`, `BlueskyRootView`)
**Status:** SHIP

Login with handle/email + password (not OAuth — Bluesky uses AT Protocol auth). After login: profile fetch, timeline, likes, post creation.

**Verdict:** Fully functional including write operations.

---

### F17. Micro.blog (Micropub) Integration
**Location:** `MicropubClient` (ArkavoKit), `MicroblogView .swift`
**Status:** SHIP

OAuth flow via `micropubClient.authURL`. Supports Micropub protocol for posting. Stored tokens loaded on launch.

**Verdict:** Functional.

---

### F18. Arkavo Authentication (WebAuthn/Passkey)
**Location:** `ArkavoAuthState.swift`, `ArkavoCreatorApp.swift`, `ArkavoClient` (ArkavoKit)
**Status:** CONDITIONAL — depends on backend availability

WebAuthn-based authentication via `ASAuthorizationPlatformPublicKeyCredentialAssertion`. Checks stored credentials on appear. Config URLs from `Config.swift`: `arkavoAuthURL`, `arkavoWebSocketURL`, `arkavoRelyingPartyID`. Initializes Iroh P2P node on app launch.

**Verdict:** Works if backend is reachable. Fails silently if not. Dashboard card shows login button and error messages gracefully. Safe to ship IF the reviewer can't see errors — but if they click "Login with Arkavo" and it fails, it could raise concerns. Consider hiding the Arkavo dashboard card if the backend won't be available during review.

---

### F19. VRM Avatar Rendering
**Location:** `AvatarViewModel.swift`, `AvatarRecordView.swift`, `VRMAvatarRenderer.swift`
**Status:** SHIP

Loads VRM models from disk, renders via Metal (`VRMMetalKit`). Supports background customization (solid color, image, video). Avatar scale adjustment. Face tracking from ARKit metadata (received via remote camera bridge). Body skeleton tracking. Model auto-loads from persisted path.

- Visual source selector: `.avatar` in control bar
- Full-stage or PiP over screen share (draggable)
- Inspector panel shows model selection, background, scale, tracking overlays

**Verdict:** Functional when a VRM model is available. Gracefully shows placeholder "No VRM Model Loaded" when not. No crash paths.

---

### F20. VRMA Motion Capture Recording
**Location:** `AvatarViewModel.swift` (`isVRMARecording`, `vrmaRecorder`), `VRMARecorder.swift`, `VRMAExporter.swift`
**Status:** SHIP

Records face blend shapes and body skeleton data as VRM Animation (VRMA) format. Quality diagnostics with warnings when capture quality is low. Export produces `.vrma` file with quality report.

**Verdict:** Functional. Niche feature that works correctly.

---

### F21. Muse AI Avatar
**Location:** `MuseAvatarViewModel.swift`, `MuseAvatarRenderer.swift`, `MuseCore/`
**Status:** CONDITIONAL

AI-driven avatar that reacts to stream chat. Metal rendering via `MuseAvatarRenderer`. Lip-sync via TTS (`MuseTTSAudioSource`). Emotion mapping from chat sentiment. LLM fallback chain for generating responses. Stream chat reactor for processing Twitch/YouTube chat messages.

Dependencies:
- VRM model loaded
- LLM provider available (Edge via agent service, or fallback)
- Chat provider connected (TwitchChatClient or YouTubeLiveChatClient)

**Verdict:** The rendering and animation system works. The LLM response generation requires either an agent connection (EdgeLLMProvider) or falls back to emote-only mode (nod + happy expression). Safe to ship — gracefully degrades. But won't demonstrate its full capability without an LLM backend.

---

### F22. Twitch Chat Integration (for Muse)
**Location:** `TwitchChatClient.swift`, `StreamChatReactor.swift`
**Status:** SHIP (but passive)

Connects to Twitch IRC over WebSocket (`wss://irc-ws.chat.twitch.tv:443`). Parses PRIVMSG for chat messages, detects subscriber/mod badges. Feeds messages to `StreamChatReactor` which rate-limits (8s between responses), filters (min 2 chars, no commands), and prioritizes (highlighted/subscriber messages first). Queue depth capped at 5.

**Verdict:** Fully implemented protocol client. Works when Twitch OAuth token and channel are provided. Not exposed as standalone UI — operates behind the scenes for Muse avatar.

---

### F23. YouTube Live Chat Integration (for Muse)
**Location:** `YouTubeLiveChatClient.swift`
**Status:** SHIP (but passive)

Polls YouTube Data API v3 `liveChatMessages.list` endpoint. Respects `pollingIntervalMillis` from API response. Requires API key and `liveChatId`.

**Verdict:** Implemented. Same as Twitch — feeds Muse avatar, not standalone UI.

---

### F24. TDF3 Content Encryption
**Location:** `RecordingProtectionService.swift`
**Status:** SHIP (background feature)

Encrypts recordings using Standard TDF format (ZIP: `manifest.json` + `0.payload`). AES-128-CBC content encryption, RSA-2048 OAEP (SHA-1) key wrapping. Fetches KAS RSA public key from `https://100.arkavo.net/kas/v2/kas_public_key`. Creates proper TDF ZIP archive via ZIPFoundation.

Also includes `TDFArchiveReader` for extracting manifests and files from TDF archives.

**Verdict:** Functional encryption service. Used by Library for "Protect" context menu action. Requires KAS backend.

---

### F25. HLS Segment Encryption
**Location:** `HLSRecordingProtectionService.swift`
**Status:** SHIP (background feature)

Converts video to HLS segments (6s duration) via `HLSConverter`, then packages into TDF archive via `HLSTDFPackager` with per-segment AES-128-CBC encryption. FairPlay-compatible format.

**Verdict:** Functional. Requires KAS backend for key fetching.

---

### F26. C2PA Content Provenance (Verification Only)
**Location:** `ProvenanceView.swift`, `RecordViewModel.swift` (lines 204-246)
**Status:** SHIP (read-only)

**Verification:** `ProvenanceView` calls `C2PASigner().verify(file:)` and displays results: manifest present/absent, signature valid/invalid, claim generator, assertions count, raw JSON. Copy-to-clipboard for raw manifest.

**Signing:** Commented out in `RecordViewModel.swift` with note "C2PA signing pending c2pa-opentdf-rs integration". The `signRecording` method exists as a complete implementation in a block comment (manifest building, device metadata, self-signed mode) but is not compiled.

**Verdict:** Verification UI works correctly — will show "No C2PA Manifest" for unsigned recordings, which is accurate. Not a broken feature. The Library shows provenance status per recording and "Verify Provenance" in context menu opens the view. Ship as-is.

---

### F27. Iroh P2P Content Publishing
**Location:** `RecordingsLibraryView.swift` (publish action), `ArkavoIrohManager` (ArkavoKit)
**Status:** CONDITIONAL

Library context menu includes "Publish to Iroh" which publishes recording content via the Iroh P2P network. Shows success with `ContentTicket` or error. `ArkavoIrohManager.shared.initialize()` called on app launch.

**Verdict:** Requires Iroh node to be reachable. If publishing fails, error is shown gracefully. Consider hiding the "Publish" action if Iroh won't be available during review.

---

### F28. Stream Monitor
**Location:** `StreamMonitorView.swift`, `StreamMonitorViewModel.swift`, `StreamMonitorWindow.swift`
**Status:** SHIP

Separate window (Cmd+Shift+M) showing real-time composed frame preview during recording/streaming. Tracks frame metrics (resolution, timing). `StreamMonitorViewModel.shared` receives frames from `RecordingSession.monitorFrameHandler`.

**Verdict:** Functional developer tool. Harmless for review — it's a standard menu command.

---

### F29. AI Agent Discovery
**Location:** `CreatorAgentService.swift`, `AgentDiscoveryPanel.swift`
**Status:** WIRE OFF

Discovers A2A (Agent-to-Agent) agents via `AgentManager.startDiscovery()`. Shows discovered agents with metadata (name, model, purpose, capabilities). Manual connection via WebSocket URL. Auto-starts device agent (`LocalAIAgent.shared`) on app appear.

The built-in device agent is always present (`local://in-process`) showing "on-device" model with sensors/foundation_models/writing_tools capabilities. Remote agents appear via network discovery.

**Verdict:** Device agent always shows as connected but provides minimal functionality. Remote agent discovery finds nothing without `arkavo-edge` running. Wire off the entire AI Assistant section.

---

### F30. AI Agent Chat
**Location:** `CreatorChatView.swift`, `CreatorAgentService.swift` (`sendMessage`)
**Status:** WIRE OFF

Chat interface for messaging agents. Streaming text accumulation. Session lifecycle (open/send/close). For device agent: calls `localAgent.sendDirectMessage` which uses on-device Foundation Models. For remote agents: uses `AgentStreamHandler` with WebSocket.

**Verdict:** Device agent chat works (uses Apple Intelligence on-device), but the UX is minimal and responses depend on Foundation Models availability. Remote agent chat requires backend. Wire off with the AI Assistant section.

---

### F31. AI Creator Tools
**Location:** `CreatorToolsView.swift`, `CreatorAgentService.swift` (convenience methods)
**Status:** WIRE OFF

Four tools:
1. **Draft Social Post** — platform picker, tone, topic → generates post via agent
2. **Generate Stream Title** — game + topic → title + 5 tags
3. **Describe Recording** — context → YouTube description with SEO
4. **Analyze Content** — text → sentiment, reading level, themes

Each tool opens a form sheet, finds a connected agent, opens a chat session, sends a structured prompt, and polls for streaming response (60s timeout).

**Verdict:** Well-built UI, but entirely dependent on agent availability. Shows "No connected agent" error immediately for most users. Wire off.

---

### F32. AI Budget Dashboard
**Location:** `BudgetDashboardView.swift`, `BudgetModels.swift`
**Status:** WIRE OFF

Displays AI spending: daily/session/hourly/monthly/total. Breakdown by provider and model. Daily cap control (default $5.00). Fetches budget via JSON-RPC `GetBudgetStatus` / `SetAgentBudget` calls to connected agent.

Shows "No remote agent connected" when no `arkavo-edge` is available.

**Verdict:** Requires remote agent. Wire off.

---

### F33. Arkavo Workflow (Content Processing)
**Location:** `ArkavoWorkflowView.swift`
**Status:** WIRE OFF

Requires Arkavo WebAuthn login. Imports `.mov` files via file picker. Processes video with:
1. `VideoSegmentationProcessor` (CoreML) — segments video frames
2. `VideoSceneDetector` — generates metadata and detects scene changes
3. `SceneMatchDetector` — finds matches against reference metadata

Results tracked as `ArkavoMessage` objects in a list with send/retry/status. Messages sent to Arkavo backend via `client.sendMessage(data)`.

**Verdict:** The CoreML video processing works, but all output goes to debug logs — the user sees only a message list with opaque IDs. Login wall blocks reviewer. Wire off.

---

### F34. Creator Profile
**Location:** `CreatorProfileView.swift`, `CreatorProfileViewModel.swift`
**Status:** SHIP

Editable profile with: display name, bio, avatar image (file picker), banner image (file picker), social links, content categories (tags), streaming schedule (day/time/duration slots), patron tiers with benefits. All data persisted via `CreatorProfile` model.

**Verdict:** Fully functional local-only feature. No external dependencies.

---

### F35. Recordings Library
**Location:** `RecordingsLibraryView.swift`, `Recording.swift`
**Status:** SHIP (with caveats)

Grid view of recorded files. Per-recording: thumbnail, title, date, duration, file size. Context menu: Play, Verify Provenance, Protect (TDF), Protect (HLS), Publish (Iroh), Delete.

Caveats:
- "Protect" actions require KAS backend at `https://100.arkavo.net`
- "Publish to Iroh" requires Iroh node
- These fail gracefully with error alerts

**Verdict:** Core library (browse, play, delete) works perfectly. Protection and publishing degrade gracefully. Consider hiding Protect/Publish context menu items if backends unavailable.

---

### F36. Dashboard
**Location:** `ContentView.swift` (`SectionContainer`, `sortedDashboardSections`)
**Status:** SHIP (with caveats)

Aggregates cards for: Arkavo, Twitch, YouTube, Patreon, Reddit, Micro.blog, Bluesky, Agent status. Cards sorted by: active content > authenticated > not authenticated.

Caveats:
- Agent card has "New Chat" and "Draft Post" buttons with **empty closures** (lines 529-536)
- Arkavo card may show auth errors if backend unavailable

**Verdict:** Remove the no-op buttons from the agent card. Consider hiding Arkavo card if backend unavailable during review.

---

### F37. QR Code Generator
**Location:** `QRCodeGenerator.swift`
**Status:** SHIP

Generates QR codes for remote camera connection info. Used in Inspector panel to share connection URL.

**Verdict:** Functional utility.

---

### F38. Video Playback
**Location:** `RecordingsLibraryView.swift` (`VideoPlayerView`, `ProtectedVideoPlayerView`)
**Status:** SHIP

Standard `AVPlayer` for unprotected recordings. Protected player for TDF-encrypted content (requires KAS for decryption key).

**Verdict:** Unprotected playback works perfectly. Protected playback requires backend.

---

---

## Wire-Off Summary

### WIRE OFF — Remove from sidebar/UI entirely

| # | Feature | Why |
|---|---------|-----|
| F11 | Arkavo Encrypted Streaming | Requires Arkavo backend; reviewer can't authenticate |
| F29 | AI Agent Discovery | Shows empty state without `arkavo-edge` server |
| F30 | AI Agent Chat | Requires agent backend or limited on-device model |
| F31 | AI Creator Tools | "No connected agent" error for all users |
| F32 | AI Budget Dashboard | Requires remote agent connection |
| F33 | Arkavo Workflow | Login wall + no visible output to users |

**Implementation:** Remove these sidebar sections from `NavigationSection.allCases`:
- `.workflow`
- `.assistant`
- `.protection` (pure placeholder)
- `.social` (pure placeholder)

Remove `.arkavo` from `StreamPlatform.allCases`.

### FIX BEFORE SHIPPING

| # | Feature | Fix |
|---|---------|-----|
| F14 | Patreon — Patron Management | Remove Send Message, Export (CSV/Excel/PDF), and Remove toolbar actions — all are empty stubs |
| F36 | Dashboard — Agent card | Remove "New Chat" and "Draft Post" buttons (empty closures) |
| F36 | Dashboard — Arkavo card | Either hide entirely or ensure graceful "service unavailable" message |
| F35 | Library — Protect/Publish | Hide "Protect (TDF)", "Protect (HLS)", "Publish to Iroh" context menu items if KAS/Iroh unavailable |
| F27 | Iroh P2P Publishing | Hide publish action or ensure graceful error |

### SHIP AS-IS

| # | Feature | Notes |
|---|---------|-------|
| F01 | Video Recording | Fully functional |
| F02 | Audio-Only Recording | Fully functional |
| F03 | Screen Capture | Fully functional |
| F04 | Multi-Camera | Fully functional |
| F05 | Remote Camera Bridge | Functional on LAN |
| F06 | Floating Head | Functional |
| F07 | Watermark | Functional, always-on |
| F08 | Twitch Streaming | Full OAuth + RTMP pipeline |
| F09 | YouTube Streaming | Full OAuth + stream key fetch |
| F10 | Custom RTMP Streaming | Fully functional |
| F12 | Twitch OAuth | Fully functional |
| F13 | YouTube OAuth | Fully functional |
| F15 | Reddit OAuth | Functional (minimal surface) |
| F16 | Bluesky Integration | Full read/write |
| F17 | Micropub Integration | Functional |
| F19 | VRM Avatar Rendering | Graceful degradation |
| F20 | VRMA Motion Capture | Functional niche feature |
| F21 | Muse AI Avatar | Degrades gracefully without LLM |
| F22 | Twitch Chat (for Muse) | Fully implemented |
| F23 | YouTube Chat (for Muse) | Fully implemented |
| F24 | TDF3 Encryption | Background service |
| F25 | HLS Encryption | Background service |
| F26 | C2PA Verification | Read-only, shows accurate status |
| F28 | Stream Monitor | Developer window, harmless |
| F34 | Creator Profile | Fully functional |
| F37 | QR Code Generator | Utility |
| F38 | Video Playback | Standard AVPlayer |

---

## App Store Narrative

After wire-off, the app presents as:

**Arkavo Creator** — A professional macOS streaming and recording studio for content creators.

Core value proposition:
1. **Record** with multi-camera, screen share, VRM avatar, or audio-only
2. **Stream live** to Twitch, YouTube, or custom RTMP servers
3. **Manage content** in a recordings library with provenance verification
4. **Connect accounts** across Twitch, YouTube, Patreon, Reddit, Bluesky, Micro.blog
5. **Build your brand** with a creator profile, streaming schedule, and patron tiers

This is a clear, complete, reviewable app with no dead ends.
