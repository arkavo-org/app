# ArkavoMediaKit Integration Guide

This guide walks through integrating ArkavoMediaKit into your iOS or macOS application.

## Prerequisites

- Xcode 16.0+ (Swift 6.2)
- iOS 18.0+ / macOS 15.0+ / tvOS 18.0+
- arkavo-rs KAS server deployment (see [Backend Setup](#backend-setup))

## Installation

### Add Package Dependency

1. Open your Xcode project
2. File → Add Package Dependencies
3. Enter package path: `../ArkavoMediaKit` (for local) or repository URL
4. Select version/branch
5. Add to your app target

## iOS App Integration (Arkavo)

### Step 1: Import the Framework

```swift
import ArkavoMediaKit
import OpenTDFKit
```

### Step 2: Configure KAS Connection

```swift
// Configure KAS metadata
let kasMetadata = try KasMetadata(
    resourceLocator: ResourceLocator(
        protocol: "https",
        body: "kas.arkavo.net"  // Your KAS server
    ),
    publicKey: kasPublicKeyData,  // KAS public key
    curve: .secp256r1
)

// Create key store with your private key
let keyStore = try await KeyStore(curve: .secp256r1)
```

### Step 3: Initialize Session Manager

```swift
// Create session manager
let sessionManager = TDF3MediaSession(heartbeatTimeout: 300) // 5 minutes

// Create key provider
let keyProvider = TDF3KeyProvider(
    kasMetadata: kasMetadata,
    keyStore: keyStore,
    sessionManager: sessionManager
)
```

### Step 4: Define Media Policy

```swift
let policy = MediaDRMPolicy(
    rentalWindow: .init(
        purchaseWindow: 7 * 24 * 3600,  // 7 days
        playbackWindow: 48 * 3600        // 48 hours
    ),
    maxConcurrentStreams: 2,
    allowedRegions: ["US", "CA"],
    hdcpLevel: .type1,
    minSecurityLevel: .high,
    allowVirtualMachines: false
)
```

### Step 5: Start Playback Session

```swift
// Start session
let session = try await sessionManager.startSession(
    userID: currentUser.id,
    assetID: "movie-12345",
    clientIP: deviceIP,
    geoRegion: "US",
    policy: policy
)

// Get device info
let deviceInfo = DeviceInfo(
    securityLevel: .high,
    isVirtualMachine: false,
    hdcpCapability: .type1
)

// Create player
let player = TDF3StreamingPlayer(
    keyProvider: keyProvider,
    policy: policy,
    deviceInfo: deviceInfo,
    sessionID: session.sessionID
)
```

### Step 6: Load and Play Stream

```swift
// Load HLS stream
let streamURL = URL(string: "https://cdn.arkavo.net/movie-12345/playlist.m3u8")!

try await player.loadStream(url: streamURL, session: session)

// Play
player.play()

// Observe playback state
player.$status
    .sink { status in
        switch status {
        case .playing:
            print("Playback started")
        case .failed(let error):
            print("Playback failed: \(error)")
        default:
            break
        }
    }
    .store(in: &cancellables)
```

### Step 7: Send Heartbeats

```swift
// Send periodic heartbeats (every 30 seconds)
Timer.publish(every: 30, on: .main, in: .common)
    .autoconnect()
    .sink { _ in
        Task {
            try? await sessionManager.updateHeartbeat(
                sessionID: session.sessionID,
                state: .playing
            )
        }
    }
    .store(in: &cancellables)
```

### Step 8: Clean Up on Stop

```swift
// When user stops playback
player.stop()

try await sessionManager.endSession(sessionID: session.sessionID)
```

## macOS App Integration (ArkavoCreator)

### Content Creation Flow

#### Step 1: Import and Segment Video

```swift
import AVFoundation
import ArkavoMediaKit

// Load video asset
let videoURL = URL(fileURLWithPath: "/path/to/video.mp4")
let asset = AVURLAsset(url: videoURL)

// Segment into HLS segments (using AVAssetWriter or similar)
let segments: [(Data, Double)] = try await segmentVideo(asset)
```

#### Step 2: Encrypt Segments

```swift
// Create encryptor
let encryptor = HLSSegmentEncryptor(
    keyProvider: keyProvider,
    policy: policy
)

// Encrypt all segments
let results = try await encryptor.encryptSegments(
    segments: segments,
    assetID: "movie-12345",
    startIndex: 0
)

// Save encrypted segments
for (index, result) in results.enumerated() {
    let segmentURL = outputDir.appendingPathComponent("segment_\(index).ts")
    try result.encryptedData.write(to: segmentURL)
}
```

#### Step 3: Generate HLS Playlist

```swift
// Create playlist generator
let generator = HLSPlaylistGenerator(
    kasBaseURL: URL(string: "https://kas.arkavo.net")!,
    cdnBaseURL: URL(string: "https://cdn.arkavo.net")!
)

// Generate media playlist
let playlist = generator.generateMediaPlaylist(
    segments: results.map(\.metadata),
    assetID: "movie-12345",
    userID: "creator-001",
    sessionID: UUID()
)

// Save playlist
let playlistURL = outputDir.appendingPathComponent("playlist.m3u8")
try generator.savePlaylist(playlist, to: playlistURL)
```

#### Step 4: Upload to CDN

```swift
// Upload segments and playlist to CDN
for segment in results {
    try await uploadToCDN(segmentURL: segment.metadata.url)
}

try await uploadToCDN(playlistURL: playlistURL)
```

## Backend Setup

### arkavo-rs KAS Server

The backend server is located at `/Users/paul/Projects/arkavo/arkavo-rs`.

#### Required Endpoints

The KAS server must implement these endpoints:

1. **Key Request** - `POST /media/v1/key-request`
   ```json
   {
     "session_id": "uuid",
     "user_id": "string",
     "asset_id": "string",
     "segment_index": 0,
     "nanotdf_header": "base64-encoded-header"
   }
   ```

   Response:
   ```json
   {
     "wrapped_key": "base64-encoded-key",
     "metadata": {
       "segment_index": 0,
       "latency_ms": 15
     }
   }
   ```

2. **Session Start** - `POST /media/v1/session/start`
3. **Session Heartbeat** - `POST /media/v1/session/{id}/heartbeat`
4. **Session End** - `DELETE /media/v1/session/{id}`

See `TDF3_MEDIA_DRM_TESTING_PLAN.md` for complete API specification.

### Environment Configuration

```bash
# KAS Configuration
export KAS_URL=https://kas.arkavo.net
export KAS_PUBLIC_KEY_PATH=/path/to/kas_public.pem
export KAS_PRIVATE_KEY_PATH=/path/to/kas_private.pem

# Policy Service
export POLICY_URL=https://policy.arkavo.net

# Media DRM
export MAX_CONCURRENT_STREAMS=5
export SESSION_HEARTBEAT_TIMEOUT=300
```

## Troubleshooting

### Common Issues

#### 1. "fetchNanoTDFHeader() requires implementation"

**Error**: Key requests fail with `notImplemented` error.

**Solution**: Implement `fetchNanoTDFHeader()` in `TDF3ContentKeyDelegate`. See method documentation for implementation options.

#### 2. Session Timeout

**Error**: "Session expired" or "Session not found"

**Solution**: Ensure heartbeats are sent at least every 5 minutes (or your configured timeout).

#### 3. Policy Validation Failed

**Error**: Various policy violations (geo-restriction, concurrency, etc.)

**Solution**: Check policy configuration matches user's entitlements and device capabilities.

#### 4. Invalid Input

**Error**: `ValidationError` thrown

**Solution**: Ensure assetID/userID contain only alphanumeric characters, hyphens, and underscores.

### Debug Logging

Enable verbose logging:

```swift
// In your app delegate
if ProcessInfo.processInfo.environment["DEBUG_TDF3"] != nil {
    // Enable logging
}
```

### Performance Issues

If key delivery exceeds 50ms P95:

1. Check network latency to KAS server
2. Enable policy caching (future enhancement)
3. Use CDN edge locations closer to users
4. Monitor KAS server performance

## Security Considerations

See [SECURITY.md](SECURITY.md) for complete security guide.

### Required for Production

1. **TLS Certificate Pinning**: Pin KAS server certificates
2. **Input Validation**: Already implemented, but verify at network boundary
3. **Rate Limiting**: Implement per-user rate limits
4. **Audit Logging**: Log all key requests and policy violations
5. **Key Rotation**: Implement regular KAS key rotation

## Testing

Run the test suite:

```bash
cd ArkavoMediaKit
swift test
```

### Integration Testing

Test against local KAS server:

```swift
// Use localhost KAS for testing
let kasMetadata = try KasMetadata(
    resourceLocator: ResourceLocator(
        protocol: "http",
        body: "localhost:8443"
    ),
    publicKey: testKASPublicKey,
    curve: .secp256r1
)
```

## Support

For issues and questions:
- GitHub Issues: https://github.com/arkavo-org/app/issues
- Documentation: See README.md and IMPLEMENTATION.md
