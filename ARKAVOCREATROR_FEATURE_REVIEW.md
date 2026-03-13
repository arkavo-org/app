# ArkavoCreator Feature Review & App Store Readiness

**Date:** 2026-03-13
**Platform:** macOS 26

## Complete Feature Inventory

The app uses a sidebar navigation with 10 sections:

| # | Sidebar Section | Navigation Case | Status |
|---|----------------|-----------------|--------|
| 1 | Dashboard | `.dashboard` | Working — aggregates all platform cards |
| 2 | Profile | `.profile` | Working — creator profile editor |
| 3 | Studio | `.studio` | Working — record & stream |
| 4 | Library | `.library` | Working — recordings browser |
| 5 | Workflow | `.workflow` | Requires Arkavo auth — content processing |
| 6 | AI Assistant | `.assistant` | Incomplete — agent framework stubs |
| 7 | Patron Management | `.patrons` | Requires Patreon auth — patron tools |
| 8 | Protection | `.protection` | Placeholder — "Coming Soon" cards only |
| 9 | Marketing | `.social` | Placeholder — "Coming Soon" cards only |
| 10 | Settings | `.settings` | Working — VRM models, feedback toggle |

---

## Feature Details by Section

### 1. Dashboard (SHIP)
- Platform login cards (Arkavo, Twitch, YouTube, Patreon, Reddit, Micro.blog, Bluesky)
- Agent status card (connected count, model info)
- Each card shows auth state and key metrics (followers, live status, subscribers)
- **Status:** Fully functional

### 2. Profile (SHIP)
- Display name, bio, avatar image, banner image
- Social links management
- Content category tags
- Streaming schedule (day/time slots)
- Patron tier definitions with benefits
- **Status:** Fully functional, data persisted locally

### 3. Studio (SHIP)
- **Recording:** Camera, screen capture, audio-only, multi-source composition
- **Streaming:** RTMP to Twitch, YouTube, custom RTMP, Arkavo (NTDF-encrypted)
- Visual source picker: Face (camera), Avatar (VRM), Muse (AI avatar), Audio-only
- Watermark overlay with position/opacity controls
- Multi-camera support (up to 4 cameras, PiP/grid layouts)
- Real-time audio level metering
- Pause/resume recording
- Stream statistics (bitrate, FPS, frames, bytes)
- Remote camera bridge
- **Status:** Fully functional core. Avatar/Muse modes depend on VRM model availability.

### 4. Library (SHIP)
- Browse recorded files (.mov, .m4a)
- Thumbnail generation
- File metadata (duration, size, date)
- Delete recordings
- C2PA provenance status indicator per recording
- "Verify Provenance" action opens ProvenanceView (calls C2PASigner.verify)
- TDF protection status indicator
- Security-scoped bookmark file access
- **Status:** Fully functional. Provenance verification will show "No C2PA Manifest" for all recordings since signing is not implemented — but the verification UI itself works correctly.

### 5. Workflow (WIRE OFF)
- Requires Arkavo WebAuthn authentication
- Content import (QuickTime .mov files)
- Video scene segmentation using CoreML (VideoSegmentationProcessor)
- Scene change detection with configurable threshold
- Message queue with send/retry/status tracking
- Sends processed content to Arkavo network via WebSocket
- **Status:** Functional but depends entirely on Arkavo backend. Without a running Arkavo server, shows login screen → user authenticates → empty message list with no obvious purpose. The video processing pipeline works but results are only visible in debug logs.

### 6. AI Assistant (WIRE OFF)
Three sub-tabs:
- **Agents tab:** Discovery panel, manual connection URL, auto-discover toggle
- **Tools tab:** "Draft Post", "Summarize", "Brainstorm" — agent-powered creation tools
- **Budget tab:** Daily spending cap, usage tracking
- **Status:** Framework exists but no actual inference occurs. Agent discovery runs but will find nothing without a running agent server. Buttons like "New Chat", "Draft Post" in the dashboard are no-ops (empty action closures). The chat UI works if an agent connects, but there's no built-in agent to connect to.

### 7. Patron Management (CONDITIONAL)
- Requires Patreon OAuth authentication
- View campaigns and patron lists
- Patron messaging interface (composer UI exists, `sendMessage()` dismisses without sending)
- Tier management
- **Status:** Read operations work (list patrons, view campaigns). Message sending is a stub. Only appears when `isCreator` is true.

### 8. Protection (WIRE OFF)
- Shows `DefaultSectionView` with `PreviewAlert` ("Coming Soon!")
- Two static feature cards:
  - "Creator Ownership Control" — description only
  - "Attribution & Compensation" — description only
- No interactive functionality whatsoever
- **Status:** Pure marketing placeholder

### 9. Marketing (WIRE OFF)
- Shows `DefaultSectionView` with `PreviewAlert` ("Coming Soon!")
- Three static feature cards:
  - "Cross-Platform Sharing"
  - "Analytics Dashboard"
  - "Notification Management"
- No interactive functionality
- **Status:** Pure marketing placeholder

### 10. Settings (SHIP)
- VRM model path configuration
- VRM Hub model download
- Feedback toggle (UserDefaults)
- Agent connection settings
- **Status:** Functional

---

## Social Platform Integrations

| Platform | OAuth | Read Data | Write/Act | Ship? |
|----------|-------|-----------|-----------|-------|
| Twitch | Working | Channel, followers, live status, stream key | Stream via RTMP | YES |
| YouTube | Working | Channel info, subscribers, stream key | Stream via RTMP | YES |
| Patreon | Working | Campaigns, patrons, tiers | Message stub (no-op) | YES (read-only) |
| Reddit | Working | User info | None visible | YES |
| Bluesky | Working | Profile, timeline, likes | Post creation | YES |
| Micro.blog | Working | Posts | Post via Micropub | YES |
| Arkavo | WebAuthn | Messages via WebSocket | Send content, encrypted streaming | CONDITIONAL |

---

## DRM/Protection Features (Background)

These operate behind the scenes during recording, not as separate UI:
- **TDF3 encryption** of recordings (AES-128-CBC + RSA-2048 OAEP)
- **HLS segment encryption** with TDF wrapping
- **fMP4 CBCS encryption** for FairPlay compatibility
- **C2PA verification** (read-only, signing not implemented)
- **Status:** Encryption works. These don't need their own UI section.

---

## Debug/Dev Artifacts to Clean Up

1. **Commented screenshot capture** in ArkavoCreatorApp.swift (lines 70-117) — harmless but messy
2. **Debug localhost URLs:**
   - `ws://localhost:8080` in WebSocketRelayManager
   - `ws://localhost:8342` for remote camera bridge
   - These should be `#if DEBUG` guarded
3. **Avatar debug views** (FaceDebugView, SkeletonDebugView, PipelineDiagnostics) — should be hidden from release builds or behind a developer toggle
4. **Stream Monitor window** (Cmd+Shift+M) — useful but technical; consider hiding

---

## Wire-Off Recommendations for App Store

### WIRE OFF (Remove from sidebar)

| Section | Why | Risk if Shipped |
|---------|-----|-----------------|
| **Protection** | Pure "Coming Soon" placeholder with zero functionality. App Store reviewers explicitly reject apps with non-functional tabs. | **Rejection: Guideline 2.1** — apps that are not fully functional |
| **Marketing** | Same as Protection — "Coming Soon" placeholder. | **Rejection: Guideline 2.1** |
| **AI Assistant** | Agent discovery finds nothing without a server. Chat UI has no built-in agent. Budget dashboard tracks nothing. Reviewers will see an empty, non-functional section. | **Rejection: Guideline 2.1** — or at minimum reviewer confusion leading to extended review |
| **Workflow** | Requires Arkavo backend authentication. If the reviewer can't authenticate, they see a login wall with no way forward. Even if they could, the feature processes video into debug logs with no visible output. | **Rejection: Guideline 2.1** — or **Guideline 3.2** if login gate can't be passed |

### CONDITIONALLY SHIP (Keep but fix)

| Section | Issue | Fix Needed |
|---------|-------|------------|
| **Patron Management** | Message composer `sendMessage()` is a no-op | Either remove the compose button or implement sending. Reviewer might test this. |
| **Dashboard — Agent card** | "New Chat" and "Draft Post" buttons have empty closures | Remove the buttons or wire them to navigate to a real feature. |
| **Dashboard — Arkavo card** | Login requires WebAuthn to an external server the reviewer can't access | Keep the card but ensure graceful behavior when auth fails. Consider a demo/offline mode. |

### SHIP AS-IS

| Section | Notes |
|---------|-------|
| **Dashboard** | Core platform cards work. Remove/disable agent and Arkavo cards if those backends won't be available during review. |
| **Profile** | Fully functional, local-only |
| **Studio** | Core recording and streaming work. Avatar/Muse modes gracefully degrade if no VRM model loaded. |
| **Library** | Works. C2PA showing "No Manifest" is accurate (not a broken feature, just unsigned content). |
| **Settings** | Functional |

---

## Implementation Approach

The cleanest approach is to filter `NavigationSection.allCases` to exclude wired-off sections:

```swift
// In NavigationSection
static func availableSections(isCreator: Bool) -> [NavigationSection] {
    let shipped: Set<NavigationSection> = [
        .dashboard, .profile, .studio, .library, .settings
    ]

    var sections = allCases.filter { shipped.contains($0) }

    if isCreator {
        sections.append(.patrons) // Only if Patreon messaging is fixed
    }

    return sections
}
```

This keeps all code intact for future enablement while presenting a clean, fully-functional app to reviewers.

---

## Summary

**Ship 5 sections:** Dashboard, Profile, Studio, Library, Settings
**Wire off 4 sections:** Protection, Marketing, AI Assistant, Workflow
**Fix then ship 1 section:** Patron Management (remove message compose stub)

The resulting app is a focused **streaming/recording studio** with social platform integrations — a clear, reviewable value proposition for App Store review.
