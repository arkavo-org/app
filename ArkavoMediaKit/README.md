# ArkavoMediaKit

A Swift package for TDF3-based HLS streaming with DRM protection, providing an open alternative to proprietary DRM systems like FairPlay, Widevine, and PlayReady.

## Overview

ArkavoMediaKit enables:
- **TDF3 Encryption**: Per-segment encryption using NanoTDF format
- **HLS Streaming**: Compatible with standard HLS players via AVFoundation
- **Media DRM Policies**: Rental windows, concurrency limits, geo-restrictions, HDCP
- **Cross-Platform**: iOS 18+, macOS 15+, tvOS 18+

## Architecture

### Components

- **Core**: Session management, key provision, AVContentKeySession integration
- **HLS**: Segment encryption, playlist generation, streaming player
- **Crypto**: TDF3 key wrapping, policy enforcement
- **Models**: Session, segment metadata, key access requests

### How It Works

1. **Content Creation** (macOS):
   - Import video → Segment with AVFoundation
   - Generate unique DEK per segment
   - Encrypt segment with AES-256-GCM
   - Wrap DEK in NanoTDF with policy
   - Generate HLS manifest with TDF3 key URLs

2. **Playback** (iOS/macOS/tvOS):
   - AVPlayer requests segment
   - TDF3ContentKeyDelegate intercepts key request
   - Validates session and policy
   - Unwraps DEK from NanoTDF
   - Returns key to AVPlayer for decryption

## Usage

### Create Encrypted HLS Stream

```swift
import ArkavoMediaKit
import OpenTDFKit

// Setup
let kasMetadata = try KasMetadata(
    resourceLocator: ResourceLocator(
        protocol: "https",
        body: "kas.arkavo.net"
    ),
    publicKey: kasPublicKey,
    curve: .secp256r1
)

let keyStore = try await KeyStore(curve: .secp256r1)
let sessionManager = TDF3MediaSession()
let keyProvider = TDF3KeyProvider(
    kasMetadata: kasMetadata,
    keyStore: keyStore,
    sessionManager: sessionManager
)

let policy = MediaDRMPolicy(
    rentalWindow: .init(
        purchaseWindow: 7 * 24 * 3600,  // 7 days
        playbackWindow: 48 * 3600        // 48 hours
    ),
    maxConcurrentStreams: 2
)

// Encrypt segments
let encryptor = HLSSegmentEncryptor(
    keyProvider: keyProvider,
    policy: policy
)

let segments: [(Data, Double)] = // ... load video segments
let results = try await encryptor.encryptSegments(
    segments: segments,
    assetID: "movie-12345",
    startIndex: 0
)

// Generate playlist
let generator = HLSPlaylistGenerator(
    kasBaseURL: URL(string: "https://kas.arkavo.net")!,
    cdnBaseURL: URL(string: "https://cdn.arkavo.net")!
)

let playlist = generator.generateMediaPlaylist(
    segments: results.map(\.metadata),
    assetID: "movie-12345",
    userID: "user-001",
    sessionID: UUID()
)

try generator.savePlaylist(playlist, to: playlistURL)
```

### Play Encrypted Stream

```swift
import ArkavoMediaKit

// Start session
let session = try await sessionManager.startSession(
    userID: "user-001",
    assetID: "movie-12345",
    policy: policy
)

// Create player
let player = TDF3StreamingPlayer(
    keyProvider: keyProvider,
    policy: policy,
    deviceInfo: DeviceInfo(),
    sessionID: session.sessionID
)

// Load and play
try await player.loadStream(
    url: playlistURL,
    session: session
)

player.play()
```

## Policy Enforcement

```swift
let policy = MediaDRMPolicy(
    rentalWindow: .init(
        purchaseWindow: 7 * 24 * 3600,
        playbackWindow: 48 * 3600
    ),
    maxConcurrentStreams: 2,
    allowedRegions: ["US", "CA", "GB"],
    hdcpLevel: .type1,
    minSecurityLevel: .high,
    allowVirtualMachines: false
)
```

## Integration

### iOS App (Arkavo.xcodeproj)

Add package dependency:
1. File → Add Package Dependencies
2. Enter path: `../ArkavoMediaKit`
3. Add to target: Arkavo

### macOS App (ArkavoCreator.xcodeproj)

Same steps as iOS app.

## Testing

Run tests:
```bash
swift test
```

Performance benchmarks target <50ms P95 key delivery latency.

## Dependencies

- [OpenTDFKit](https://github.com/arkavo-org/OpenTDFKit) - TDF3/NanoTDF implementation
- AVFoundation - Video playback and content key management
- CryptoKit - AES-GCM encryption

## License

Same as parent Arkavo project.

## Related

- [TDF3 Media DRM Testing Plan](../FairPlay_Streaming_Server_SDK_5.1/TDF3_MEDIA_DRM_TESTING_PLAN.md)
- [arkavo-rs KAS Implementation](https://github.com/arkavo-org/arkavo-rs/issues/21)
