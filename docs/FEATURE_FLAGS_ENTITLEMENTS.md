# Feature Flags & Entitlements Map

Feature flags gate functionality for App Store review. Entitlements and Info.plist keys must stay in sync — only include entitlements for features that are enabled.

## Current Feature Flags

| Flag | Status | Description |
|------|--------|-------------|
| `aiAgent` | off | AI Agent discovery, chat, tools, and budget |
| `avatar` | off | VRM/Muse avatar rendering and face tracking |
| `remoteCameraBridge` | off | Remote camera bridge (WebSocket server for iOS companion) |
| `provenance` | off | C2PA provenance verification and display |
| `contentProtection` | off | Content protection (TDF3, HLS, FairPlay) and Iroh publishing |
| `arkavoStreaming` | off | Arkavo encrypted streaming platform |
| `youtube` | off | YouTube streaming and OAuth integration |
| `patreon` | off | Patreon patron management |
| `workflow` | off | Workflow management section |
| `social` | off | Marketing/social section |

## Entitlement Dependencies

When enabling a feature flag, add these entitlements and Info.plist keys:

### `remoteCameraBridge`
**Entitlements:**
- `com.apple.security.network.server` — NWListener for WebSocket server

**Info.plist:**
- `NSLocalNetworkUsageDescription` — "Arkavo Creator uses the local network to receive video from companion devices and to play back recordings."
- `NSBonjourServices` — `["_arkavo-remote._tcp."]`

### `youtube`
**Entitlements:**
- `com.apple.security.network.server` — local HTTP server for OAuth callback

**Info.plist:**
- `NSLocalNetworkUsageDescription` (same as above, if not already present)

### `contentProtection`
**Entitlements:**
- `com.apple.security.network.server` — LocalHTTPServer for FairPlay/TDF playback

**Info.plist:**
- `NSLocalNetworkUsageDescription` (same as above, if not already present)

### `patreon`
**Entitlements:**
- Keychain: `$(AppIdentifierPrefix)com.arkavo.patreon`

### `social`
**Entitlements:**
- Keychain: `$(AppIdentifierPrefix)com.arkavo.bluesky`

## Always-On Entitlements (no feature flag)

These are required by core functionality that is always active:

| Entitlement | Used by |
|-------------|---------|
| `app-sandbox` | Required for Mac App Store |
| `associated-domains` | Arkavo auth (webcredentials:identity.arkavo.net) |
| `application-groups` | Shared preferences (group.com.arkavo.shared) |
| `device.audio-input` | Microphone for recording/streaming |
| `device.camera` | Camera for recording/streaming |
| `files.user-selected.read-write` | Saving recordings to user-chosen folder |
| `network.client` | RTMP streaming, Twitch API, remote APIs |
| Keychain: `ArkavoCreator` | App credentials |
| Keychain: `webauthn`, `did`, `handle` | Arkavo authentication |

## Always-On Info.plist Keys

| Key | Description |
|-----|-------------|
| `NSMicrophoneUsageDescription` | Microphone for recording/streaming |
| `NSCameraUsageDescription` | Camera for recording/streaming |
| `NSScreenCaptureUsageDescription` | Screen capture via ScreenCaptureKit |
| `NSFileUsageDescription` | File access for recordings |
| `NSDocumentsFolderUsageDescription` | Documents folder for recordings |
| `CFBundleURLTypes` | `arkavocreator://` URL scheme for OAuth callbacks |

## Checklist: Before App Store Submission

1. Review `FeatureFlags.swift` — confirm all gated features are set correctly
2. Verify entitlements match enabled features using the table above
3. Verify Info.plist keys match enabled features
4. Build and run — confirm no sandbox violations in Console.app
5. Test each enabled feature's permission prompt appears correctly
