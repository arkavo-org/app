# NTDF-RTMP Streaming Architecture

This document describes the end-to-end flow for encrypted live streaming using NanoTDF over RTMP (NTDF-RTMP) between ArkavoCreator (publisher) and Arkavo (subscriber) iOS apps via the arkavo-rs Rust server.

## Architecture Overview

```
┌─────────────────────┐         ┌─────────────────────┐         ┌─────────────────────┐
│   ArkavoCreator     │         │    arkavo-rs        │         │      Arkavo         │
│   (Publisher)       │  RTMP   │    RTMP Server      │  RTMP   │   (Subscriber)      │
│                     │────────▶│                     │────────▶│                     │
│  Camera → Encode    │         │  Relay + Cache      │         │  Decrypt → Display  │
│  → Encrypt → Send   │         │  Sequence Headers   │         │                     │
└─────────────────────┘         └─────────────────────┘         └─────────────────────┘
         │                                                                │
         │                      ┌─────────────────────┐                   │
         └─────────────────────▶│   KAS Server        │◀──────────────────┘
                                │ (Key Access Server) │
                                │ identity.arkavo.net │
                                └─────────────────────┘
```

## Component Roles

| Component | Role |
|-----------|------|
| **ArkavoCreator** | Captures camera/mic, encodes H.264/AAC, encrypts with NanoTDF, publishes via RTMP |
| **arkavo-rs** | RTMP server that relays frames, caches sequence headers for late joiners |
| **Arkavo** | Subscribes to RTMP stream, performs KAS rewrap, decrypts frames, displays video |
| **KAS** | Key Access Server - manages encryption keys, performs rewrap for authorized clients |

---

## Publisher Flow (ArkavoCreator)

### 1. Video/Audio Capture & Encoding

**Files:**
- `ArkavoKit/Sources/ArkavoRecorder/VideoEncoder.swift`
- `ArkavoKit/Sources/ArkavoRecorder/AudioEncoder.swift`

```
Camera/Microphone
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ VideoEncoder                                             │
│ ├─ VTCompressionSession (H.264 hardware encoding)        │
│ ├─ 30 FPS, keyframe every 1 second                       │
│ └─ Output: CMSampleBuffer with NALUs                     │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ AudioEncoder                                             │
│ ├─ AVAudioConverter (AAC encoding)                       │
│ ├─ 48kHz stereo                                          │
│ └─ Output: AAC frames                                    │
└──────────────────────────────────────────────────────────┘
```

### 2. NanoTDF Encryption

**File:** `ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingManager.swift`

```
Encoded Frame
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ NanoTDFCollection                                        │
│ ├─ Initialize with KAS public key                        │
│ ├─ Generate collection header (sent once in metadata)    │
│ └─ Per-frame encryption:                                 │
│     ├─ 3-byte IV counter (incrementing)                  │
│     ├─ 3-byte payload length                             │
│     ├─ AES-256-GCM encrypted ciphertext                  │
│     └─ 16-byte authentication tag                        │
└──────────────────────────────────────────────────────────┘
       │
       ▼
Encrypted Frame (ready for RTMP)
```

### 3. RTMP Publishing

**File:** `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift`

```
RTMP Connection Flow:
1. TCP connect to rtmp://server:1935
2. RTMP Handshake (C0/C1 ↔ S0/S1/S2 ↔ C2)
3. connect("live") AMF0 command
4. createStream → get stream ID
5. publish(streamName)
6. Send @setDataFrame with onMetaData:
   - width, height, framerate
   - ntdf_header: base64-encoded NanoTDF collection header
7. Send video/audio frames with FLV container format
```

### Frame Format (FLV over RTMP):

**Video Frame:**
```
Byte 0: Frame type (4 bits) + Codec ID (4 bits)
        - 0x17 = Keyframe + AVC (H.264)
        - 0x27 = Inter-frame + AVC
Byte 1: AVC packet type
        - 0x00 = Sequence header (SPS/PPS)
        - 0x01 = NAL units
Bytes 2-4: Composition time offset (signed 24-bit)
Bytes 5+: Encrypted payload (or raw NALUs for sequence header)
```

**Audio Frame:**
```
Byte 0: Sound format (4 bits) + rate/size/type
        - 0xAF = AAC, 44kHz, 16-bit, stereo
Byte 1: AAC packet type
        - 0x00 = Sequence header (AudioSpecificConfig)
        - 0x01 = Raw AAC frame
Bytes 2+: Encrypted payload (or raw config for sequence header)
```

---

## Server Flow (arkavo-rs)

### RTMP Session Handling

**Files:**
- `arkavo-rs/src/modules/rtmp/server.rs`
- `arkavo-rs/src/modules/rtmp/session.rs`
- `arkavo-rs/src/modules/rtmp/registry.rs`

```
┌──────────────────────────────────────────────────────────┐
│ RtmpServer                                               │
│ ├─ Listen on port 1935                                   │
│ ├─ Accept connections                                    │
│ └─ Spawn RtmpSession per connection                      │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ RtmpSession                                              │
│ ├─ RTMP handshake                                        │
│ ├─ Detect role: Publisher or Subscriber                  │
│ │                                                        │
│ │ Publisher:                                             │
│ │ ├─ Register in StreamRegistry                          │
│ │ ├─ Cache video/audio sequence headers                  │
│ │ ├─ Relay frames via broadcast channel                  │
│ │ └─ Broadcast stream_started/stopped events             │
│ │                                                        │
│ │ Subscriber:                                            │
│ │ ├─ Subscribe to StreamRegistry                         │
│ │ ├─ Receive cached sequence headers                     │
│ │ ├─ Send headers before first frame                     │
│ │ └─ Relay frames from publisher                         │
└──────────────────────────────────────────────────────────┘
```

### StreamRegistry (Publisher-Subscriber Linking)

```rust
pub struct StreamRegistry {
    streams: HashMap<String, ActiveStream>,
}

pub struct ActiveStream {
    stream_key: String,
    frame_sender: broadcast::Sender<RelayFrame>,
    video_sequence_header: Option<Vec<u8>>,  // Cached for late joiners
    audio_sequence_header: Option<Vec<u8>>,  // Cached for late joiners
}
```

### Sequence Header Detection

```rust
// Video: Keyframe + AVC + Sequence header
fn is_video_sequence_header(data: &[u8]) -> bool {
    data.len() >= 2
        && (data[0] >> 4) == 1      // Keyframe
        && (data[0] & 0x0F) == 7    // AVC codec
        && data[1] == 0             // Sequence header
}

// Audio: AAC + Sequence header
fn is_audio_sequence_header(data: &[u8]) -> bool {
    data.len() >= 2
        && (data[0] >> 4) == 10     // AAC
        && data[1] == 0             // Sequence header
}
```

---

## Subscriber Flow (Arkavo iOS)

### 1. RTMPSubscriber - Connection & Raw Frame Reception

**File:** `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPSubscriber.swift`

```
RTMP Connection Flow:
1. TCP connect via NWConnection
2. RTMP Handshake
3. connect("live") AMF0 command
4. createStream → get stream ID
5. play(streamName)
6. Start receive loop for chunks
```

### Chunk Handling:

```
Chunk Basic Header (1-3 bytes):
├─ Format (2 bits): 0=full, 1=no stream ID, 2=timestamp only, 3=continuation
└─ Chunk Stream ID (6+ bits)

Chunk Message Header (0-11 bytes based on format):
├─ Format 0: timestamp(3) + length(3) + type(1) + streamID(4)
├─ Format 1: timestamp(3) + length(3) + type(1)
├─ Format 2: timestamp(3)
└─ Format 3: (none - use previous header)

Chunk reassembly:
├─ Maintain per-chunk-stream state
├─ Read payload in chunks (default 128 bytes)
└─ Send acknowledgements when window exceeded
```

### 2. NTDFStreamingSubscriber - Decryption Layer

**File:** `ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingSubscriber.swift`

```
Metadata Received (contains ntdf_header)
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ StreamingCollectionDecryptor Initialization              │
│                                                          │
│ 1. Parse NanoTDF header                                  │
│    ├─ Extract cipher: AES-256-GCM-128                    │
│    └─ Extract key metadata                               │
│                                                          │
│ 2. KAS Rewrap                                            │
│    ├─ Generate ephemeral P-256 key pair                  │
│    ├─ POST to KAS: rewrapNanoTDF(header, clientPubKey)   │
│    ├─ Receive: (wrappedKey, sessionPublicKey)            │
│    │                                                     │
│    └─ Unwrap symmetric key:                              │
│        ├─ ECDH: clientPrivKey × sessionPubKey            │
│        ├─ HKDF-SHA256 → unwrap key                       │
│        └─ AES-GCM decrypt → payload symmetric key        │
│                                                          │
│ 3. Create OpenTDFKit.NanoTDFCollectionDecryptor          │
└──────────────────────────────────────────────────────────┘
```

### Per-Frame Decryption:

```
Encrypted Frame
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ Wire Format:                                             │
│ ├─ 3 bytes: IV counter (big-endian)                      │
│ ├─ 3 bytes: payload length (big-endian)                  │
│ └─ N bytes: ciphertext + 16-byte tag                     │
│                                                          │
│ Decrypt via OpenTDFKit.decryptItem()                     │
│ → Plaintext FLV frame data                               │
└──────────────────────────────────────────────────────────┘
```

### 3. FLVDemuxer - Media Frame Parsing

**File:** `ArkavoKit/Sources/ArkavoStreaming/RTMP/FLVDemuxer.swift`

```
Decrypted Frame
       │
       ├─── Video ───▶ parseAVCVideoFrame()
       │               ├─ Extract NALUs
       │               ├─ Parse composition time offset
       │               ├─ Calculate PTS = timestamp + CTS
       │               └─ createVideoSampleBuffer()
       │
       └─── Audio ───▶ parseAACAudioFrame()
                       ├─ Extract raw AAC frame
                       └─ createAudioSampleBuffer()
       │
       ▼
CMSampleBuffer (ready for display)
```

### 4. Display Pipeline

**Files:**
- `Arkavo/Arkavo/LiveStreamViewModel.swift`
- `Arkavo/Arkavo/EmbeddedLiveStreamView.swift`

```
CMSampleBuffer
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ LiveStreamViewModel                                      │
│ └─ displayLayer.enqueue(sampleBuffer)                    │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│ AVSampleBufferDisplayLayer                               │
│ ├─ Hardware H.264 decoding                               │
│ └─ Render to CALayer                                     │
└──────────────────────────────────────────────────────────┘
```

---

## Key Points

### Sequence Headers Are NOT Encrypted

Sequence headers contain decoder configuration required before any frames can be decoded:
- **Video**: SPS/PPS (H.264 parameter sets)
- **Audio**: AudioSpecificConfig (AAC configuration)

These are sent in cleartext because:
1. They contain no user content
2. Decoders need them to initialize
3. Late joiners need them from server cache

### Late Joiner Support

When a subscriber connects after the stream has started:
1. Server sends cached video sequence header (timestamp 0)
2. Server sends cached audio sequence header (timestamp 0)
3. Server begins relaying live frames
4. Subscriber can decode immediately

### NTDF Token

The NTDF token (OAuth access token from `identity.arkavo.net`) is:
- Stored in iOS Keychain after authentication
- Retrieved via `KeychainManager.getAuthenticationToken()`
- Sent to KAS for rewrap authorization

---

## File Reference

### ArkavoCreator (Publisher)

| Component | File |
|-----------|------|
| Video Encoding | `ArkavoKit/Sources/ArkavoRecorder/VideoEncoder.swift` |
| Audio Encoding | `ArkavoKit/Sources/ArkavoRecorder/AudioEncoder.swift` |
| RTMP Publishing | `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPPublisher.swift` |
| NTDF Encryption | `ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingManager.swift` |

### arkavo-rs (Server)

| Component | File |
|-----------|------|
| TCP Listener | `src/modules/rtmp/server.rs` |
| Session Handler | `src/modules/rtmp/session.rs` |
| Stream Registry | `src/modules/rtmp/registry.rs` |
| Module Entry | `src/modules/rtmp/mod.rs` |

### Arkavo (Subscriber)

| Component | File |
|-----------|------|
| RTMP Protocol | `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPSubscriber.swift` |
| NTDF Decryption | `ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingSubscriber.swift` |
| FLV Parsing | `ArkavoKit/Sources/ArkavoStreaming/RTMP/FLVDemuxer.swift` |
| KAS Client | `ArkavoKit/Sources/ArkavoStreaming/RTMP/KASPublicKeyService.swift` |
| ViewModel | `Arkavo/Arkavo/LiveStreamViewModel.swift` |
| UI View | `Arkavo/Arkavo/EmbeddedLiveStreamView.swift` |

---

## Troubleshooting

### "Received video frame before sequence header"

**Cause:** Subscriber connected but didn't receive the video sequence header.

**Fix:** Server must cache and send sequence headers to late joiners before relaying frames.

### Connection Reset by Peer

**Cause:** Server closed connection, possibly due to:
- Timeout waiting for data
- Protocol error
- Server crash

**Debug:** Check server logs for errors around the time of disconnect.

### KAS Rewrap Failure

**Cause:** Invalid or expired NTDF token.

**Fix:** Re-authenticate with `identity.arkavo.net` to get fresh token.

### AES-GCM Authentication Failure (Decryption Fails)

**Symptom:** KAS rewrap succeeds, symmetric key is unwrapped, but decryption fails with `authenticationFailure`.

**Cause:** Symmetric key mismatch between publisher and subscriber.

**Debug Steps:**
1. Compare key fingerprints:
   - Publisher logs: `🔐 [NTDFStreamingManager] Rotated collection: - Key fingerprint: XXXXXXXX`
   - Subscriber logs: `✅ Symmetric key unwrapped: 256 bits, fingerprint: XXXXXXXX`
2. Compare ephemeral public keys:
   - Publisher logs: `- Ephemeral pubkey (33 bytes): <HEX>`
   - Subscriber logs: `🔐 [DEBUG] Ephemeral public key (33 bytes): <HEX>`
3. Compare KAS public keys:
   - Publisher logs: `🔐 [NTDFStreamingManager] Using KAS public key (33 bytes): <HEX>`
   - Fetch from KAS: `curl https://platform.arkavo.net/kas/v2/kas_public_key?algorithm=ec`

**Root Cause (Under Investigation - Dec 2024):**
The symmetric key derived by the publisher differs from the key returned by KAS rewrap. This indicates:
- KAS may be using a different private key than the one corresponding to the fetched public key
- Possible key rotation on the KAS server
- NanoTDF v12 (L1L) format does not include KAS public key in header - KAS must determine which key to use

**Potential Fixes:**
1. Ensure KAS uses the same key pair for public key endpoint and rewrap
2. Include `kid` (key ID) in NanoTDF header for KAS to identify correct key
3. Clear KAS public key cache on each collection rotation (implemented)

---

## CLI Testing

The `NTDFTestCLI` tool provides quick testing of NTDF streaming components.

### Build CLI
```bash
swift build --package-path ArkavoKit -c debug --product ntdf-test
```

### Run Publisher Tests (local RTMP)
```bash
.build/debug/ntdf-test
```

### Run Subscriber Test (remote RTMP)
```bash
.build/debug/ntdf-test --subscriber
```

### Test Key Derivation Match
```bash
# Run this to verify publisher/subscriber derive same symmetric key
.build/debug/ntdf-test --key-test
```

---

## Current Status (Dec 11, 2024)

| Component | Status | Notes |
|-----------|--------|-------|
| Publisher encoding | ✅ Working | Video/audio frames encoded and encrypted |
| RTMP connection | ✅ Working | Publisher connects and sends frames |
| Server relay | ✅ Working | arkavo-rs relays frames to subscribers |
| Subscriber RTMP | ✅ Working | Receives frames, timestamps, and sequence headers |
| RTMP chunk interleaving | ✅ Fixed | Properly handles interleaved chunks from different streams |
| KAS rewrap | ✅ Working | Returns wrapped key and session public key |
| Key unwrap | ✅ Working | Symmetric key unwrapped successfully |
| Key derivation | ✅ Working | `ntdf-test --key-test` confirms keys match |
| Late joiner sync | ✅ Fixed | Metadata update on rotation implemented |
| **E2E Decryption** | ✅ **WORKING** | `ntdf-test --e2e` confirms full pipeline works |

### E2E Test Results (Dec 11, 2024)

```bash
.build/debug/ntdf-test --e2e
```

**Result: DECRYPTION WORKING!**

| Metric | Value |
|--------|-------|
| Publisher key fingerprint | `2DA6B2E273806DE2` |
| Subscriber key fingerprint | `2DA6B2E273806DE2` |
| Key match | ✅ YES |
| IV counter start | 1 (correct) |
| Decryption | ✅ `45 → 23 bytes` |

The E2E test:
1. Creates unique stream name to avoid conflicts
2. Publisher starts first, sends metadata with `ntdf_header`
3. Subscriber connects, receives metadata, initializes decryptor
4. KAS rewrap returns correct symmetric key
5. Frames decrypted successfully (IV 1, 2, 3...)

### Key Rotation Support

The publisher rotates encryption keys periodically (e.g., on keyframes). When this happens:
1. Publisher sends new `onMetaData` with updated `ntdf_header` (**NEW: Dec 11, 2024**)
2. Publisher sends in-band NTDF header frame before keyframe
3. Subscriber detects header change (`isNewHeader = metadataHeaderBase64 != ntdfHeaderBase64`)
4. Subscriber calls `addAlternateFromHeader()` to add the new key
5. Decryption tries primary key first, then alternates

**Files:**
- `ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingManager.swift` - `rotateCollection()` now sends metadata update
- `ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingSubscriber.swift` - `handleMetadata()`

### Late Joiner Issue (Dec 11, 2024)

**Symptom:** Subscriber joins an existing stream, gets `authenticationFailure` on decryption.

**Root Cause:** When the publisher rotates keys on keyframes, it was only sending an in-band NTDF header frame but **NOT** updating the RTMP metadata. Late joiners receive stale metadata with the old key.

**Evidence:**
- First frame IV counter is high (e.g., 69) instead of 1
- This indicates frames are from a collection that started before the current metadata header

**Fix Applied (Dec 11, 2024):**
Updated `NTDFStreamingManager.rotateCollection()` to also send updated metadata:
```swift
// Send updated metadata with new ntdf_header (for late joiners)
let base64Header = headerBytes.base64EncodedString()
try await rtmpPublisher.sendMetadata(
    width: streamWidth,
    height: streamHeight,
    framerate: streamFramerate,
    videoBitrate: streamVideoBitrate,
    audioBitrate: streamAudioBitrate,
    customFields: ["ntdf_header": base64Header]
)
```

**Subscriber Warning:** Now logs warning when first IV counter > 10:
```
⚠️ [Decrypt] HIGH IV COUNTER on first frame! ivCounter=69
   This likely means the metadata ntdf_header is from a previous key rotation.
```

### RTMP Interleaved Chunk Handling (Fixed Dec 11, 2024)

**Issue:** RTMP chunks from video and audio streams can be interleaved. When reading a multi-chunk video message, an audio chunk might arrive in between.

**Fix Applied:** Updated `RTMPSubscriber.receiveRTMPMessage()` to:
1. Parse interleaved chunk headers (format 0, 1, 2, 3)
2. Skip interleaved chunk data
3. Continue reading continuation header for original message

**File:** `ArkavoKit/Sources/ArkavoStreaming/RTMP/RTMPSubscriber.swift`

### Previous Issue: KAS Key Derivation Bug (RESOLVED Dec 10, 2024)

CLI test (`ntdf-test --key-test`) confirmed the issue and fix:

**Before fix:**
```
Publisher fingerprint: 28D09B01669BBAC5
Subscriber fingerprint: 4222196A1E9C1D51
❌ KEYS DO NOT MATCH!
```

**After fix:**
```
Publisher fingerprint: 63EA76CCF8E92EE7
Subscriber fingerprint: 63EA76CCF8E92EE7
✅ KEYS MATCH!
```

**Root Cause:** The `rewrap_dek()` function in `arkavo-rs/src/modules/crypto.rs` was returning the **raw ECDH x-coordinate** instead of the **HKDF-derived symmetric key**.

The publisher derives the DEK via:
```
ECDH(eph_private, kas_public) → shared_secret
HKDF(salt=SHA256("L1L"), shared_secret) → symmetric_key
```

But the KAS was returning only `shared_secret` without the HKDF derivation step.

**Fix Applied:** Updated `rewrap_dek()` to:
1. First derive the actual DEK: `HKDF(salt, dek_shared_secret)` → `dek`
2. Then derive wrapping key: `HKDF(salt, session_shared_secret)` → `wrapping_key`
3. Wrap `dek` with `wrapping_key` for transport

**File Changed:** `arkavo-rs/src/modules/crypto.rs` - `rewrap_dek()` function
