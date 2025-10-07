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

## Known Limitations

⚠️ **Critical**: This package requires additional implementation before production use.

### Implementation Required

1. **`fetchNanoTDFHeader()` Method** (TDF3ContentKeyDelegate.swift)
   - **Status**: Placeholder implementation that throws `notImplemented` error
   - **Impact**: Playback will not work until implemented
   - **Options**: Parse from HLS manifest, fetch from metadata endpoint, or load from cache
   - **Documentation**: See method documentation for integration guide

2. **KAS Server Integration**
   - **Status**: Requires arkavo-rs deployment with media DRM endpoints
   - **Required Endpoints**:
     - `POST /media/v1/key-request`
     - `POST /media/v1/session/start`
     - `POST /media/v1/session/{id}/heartbeat`
     - `DELETE /media/v1/session/{id}`
   - **Reference**: See [Integration Guide](INTEGRATION_GUIDE.md#backend-setup)

### Current Limitations

1. **No Session Persistence**
   - Sessions stored in memory only
   - Lost on app restart
   - No cross-device synchronization
   - **Workaround**: Implement Redis integration (see IMPLEMENTATION.md)

2. **No Offline Playback**
   - `AVAssetDownloadTask` integration not implemented
   - Cannot download content for offline viewing
   - **Roadmap**: Planned for future release

3. **Performance Not Validated**
   - Claims <50ms P95 key delivery but not benchmarked
   - No production load testing
   - **Action**: Run performance tests before production deployment

4. **No Policy Caching**
   - Policies evaluated on every key request
   - Potential performance bottleneck under load
   - **Optimization**: Implement Redis policy cache

5. **Limited Error Recovery**
   - Basic retry logic only
   - No circuit breaker for KAS failures
   - **Enhancement**: Add resilience patterns

### Security Hardening Required

Before production deployment, implement:

1. **TLS Certificate Pinning** - Pin KAS server certificates
2. **Rate Limiting** - Per-user request limits (60/min recommended)
3. **Audit Logging** - Log all key requests and policy violations
4. **Key Rotation** - KAS key rotation procedure (90-day schedule)
5. **Monitoring** - Metrics collection and alerting

See [SECURITY.md](SECURITY.md) for complete security guide.

### Platform Support

- ✅ iOS 18.0+
- ✅ macOS 15.0+
- ✅ tvOS 18.0+
- ❌ watchOS (AVPlayer limitations)

## Testing

Run tests:
```bash
swift test
```

**Current Coverage**:
- ✅ Unit tests (6 tests)
- ✅ Integration tests (6 tests)
- ❌ Performance tests (not implemented)
- ❌ E2E tests with real KAS (requires deployment)

## License

Same as parent Arkavo project.

## Related

- [Integration Guide](INTEGRATION_GUIDE.md) - Step-by-step integration
- [Security Guide](SECURITY.md) - Security best practices
- [Implementation Details](IMPLEMENTATION.md) - Technical architecture
- [TDF3 Media DRM Testing Plan](../FairPlay_Streaming_Server_SDK_5.1/TDF3_MEDIA_DRM_TESTING_PLAN.md)
- [arkavo-rs KAS Implementation](https://github.com/arkavo-org/arkavo-rs/issues/21)
