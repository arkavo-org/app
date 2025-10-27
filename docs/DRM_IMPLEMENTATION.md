# DRM Implementation for ArkavoMediaKit

## Overview

Successfully extended **ArkavoMediaKit** with FairPlay Streaming DRM capabilities that integrate with the Arkavo media server API at `https://100.arkavo.net`.

## Architecture

```
ArkavoMediaKit (Extended)
├── Existing: TDF3 + OpenTDF encryption
└── New: FairPlay Streaming DRM
    ├── MediaSessionManager (actor)
    │   └── Session lifecycle: start → heartbeat → terminate
    ├── FairPlayContentKeyDelegate (AVContentKeySessionDelegate)
    │   ├── Online streaming (SPC/CKC exchange)
    │   └── Offline playback (persistable keys on iOS)
    └── DRMMediaPlayer (high-level API)
        └── Unified TDF3 + FairPlay playback
```

## Components Created

### 1. Configuration (`Config/DRMConfiguration.swift`)
- Loads FPS test certificate from bundle resources
- Configures server URL (default: `https://100.arkavo.net`)
- Manages heartbeat and session timeout settings

### 2. Network Layer (`Network/MediaServerClient.swift`)
HTTP client (actor) for Arkavo media server endpoints:
- `POST /media/v1/session/start` → Start playback session
- `POST /media/v1/key-request` → FairPlay CKC exchange
- `POST /media/v1/session/:id/heartbeat` → Keep session alive
- `DELETE /media/v1/session/:id` → End session

### 3. Session Management (`Core/MediaSessionManager.swift`)
Actor-based session lifecycle manager:
- Tracks multiple concurrent sessions
- Automatic heartbeat timer (default: 30s interval)
- Session timeout handling (default: 300s)
- Automatic cleanup on expiration

### 4. FairPlay Delegate (`Core/FairPlayContentKeyDelegate.swift`)
Implements `AVContentKeySessionDelegate`:
- **Online streaming**: SPC generation → server CKC request → AVPlayer key provisioning
- **Offline playback** (iOS only): Persistable key support with keychain storage
- Thread-safe DEK caching
- Content key identifier parsing (`skd://` and `tdf3://` URL schemes)
- Automatic retry on timeout/expired keys

### 5. High-Level Player API (`Player/DRMMediaPlayer.swift`)
SwiftUI-ready `@Observable` player:
- Unified session + playback management
- Automatic FairPlay content key session setup
- Play/pause/seek controls
- State tracking (idle, loading, playing, paused, buffering, ended, error)
- iOS persistable key support

### 6. Models (`Models/`)
- `SessionStartResponse` - Server session response
- `KeyRequestResponse` - FairPlay CKC response
- `KeyRequestBody` - FairPlay SPC request
- `HeartbeatRequest` - Session heartbeat

### 7. Error Handling
Extended `ValidationError` with FairPlay-specific cases:
- `missingContentKeyIdentifier`
- `invalidContentKeyIdentifier`
- `contentKeyRequestFailed`
- `persistableKeyNotSupported`

New error types:
- `DRMConfigurationError` - Certificate and config errors
- `MediaServerError` - HTTP communication errors
- `KeyRequestError` - Key exchange errors
- `DRMPlayerError` - Playback errors

## Usage Example

```swift
import ArkavoMediaKit

// Initialize player with default configuration
let player = DRMMediaPlayer()

// Start playback session
let sessionId = try await player.startSession(
    userID: "user123",
    assetID: "movie456"
)

// Play DRM-protected HLS stream
try await player.play(url: URL(string: "https://example.com/manifest.m3u8")!)

// Player automatically:
// - Requests FairPlay keys via /media/v1/key-request
// - Sends heartbeats every 30s
// - Manages session lifecycle

// Pause/resume
await player.pause()
await player.resume()

// Seek
await player.seek(to: CMTime(seconds: 120, preferredTimescale: 1))

// iOS: Request offline key
#if os(iOS)
player.requestPersistableKey(for: "movie456")
#endif

// End session
try await player.endSession()
```

## Certificate Management

Currently using test certificate from FairPlay SDK v26:
- Location: `ArkavoMediaKit/Sources/ArkavoMediaKit/Resources/test_fps_certificate_v26.bin`
- Source: `vendor/FairPlay_Streaming_Server_SDK_26/Development/Key_Server_Module/credentials/`

**For Production**: Replace with production FPS certificate via `DRMConfiguration`:

```swift
let productionCert = try Data(contentsOf: URL(fileURLWithPath: "/path/to/prod_cert.der"))
let config = try DRMConfiguration(
    serverURL: URL(string: "https://100.arkavo.net")!,
    fpsCertificateData: productionCert
)
let player = DRMMediaPlayer(configuration: config)
```

## Platform Support

- **iOS 26+**: Full support including offline playback
- **macOS 26+**: Online streaming only
- **tvOS 26+**: Online streaming only

## Server Integration

The implementation expects the following server responses:

**Session Start Response:**
```json
{
  "sessionId": "uuid-string",
  "status": "active"
}
```

**Key Request Response:**
```json
{
  "ckcData": "base64-encoded-ckc",
  "expiresAt": "2025-10-28T12:00:00Z"
}
```

## Concurrency

All components use Swift 6 strict concurrency:
- `MediaServerClient` - Actor
- `MediaSessionManager` - Actor
- `FairPlayContentKeyDelegate` - `@unchecked Sendable` (NSObject subclass)
- `DRMMediaPlayer` - `@Observable` (main actor isolated)

## Testing

Build verification:
```bash
cd ArkavoMediaKit
swift build
# Build complete! (0.58s)
```

## Future Enhancements

1. **TDF3 Integration**: Support nanotdf headers via `/kas/v2/rewrap`
2. **C2PA Support**: Content authenticity via `/c2pa/v1/*` endpoints
3. **WebSocket Events**: Real-time notifications via `/ws`
4. **Metrics**: Playback analytics and quality monitoring
5. **Multi-DRM**: Add Widevine/PlayReady support

## Files Modified/Created

### New Files (10):
1. `Config/DRMConfiguration.swift`
2. `Network/MediaServerClient.swift`
3. `Core/MediaSessionManager.swift`
4. `Core/FairPlayContentKeyDelegate.swift`
5. `Player/DRMMediaPlayer.swift`
6. `Models/SessionStartResponse.swift`
7. `Models/KeyRequestResponse.swift`
8. `Resources/test_fps_certificate_v26.bin`
9. `docs/DRM_IMPLEMENTATION.md` (this file)

### Modified Files (2):
1. `Package.swift` - Added resource bundle
2. `Core/ValidationError.swift` - Extended with FairPlay errors

## References

- FairPlay SDK: `vendor/FairPlay_Streaming_Server_SDK_26/`
- Server code: `/Users/paul/Projects/arkavo/arkavo-rs`
- Apple FairPlay Streaming Guide: https://developer.apple.com/streaming/fps/
