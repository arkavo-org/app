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
