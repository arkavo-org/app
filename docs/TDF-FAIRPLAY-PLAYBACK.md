# TDF + FairPlay DRM Playback

This document describes the implementation of TDF-protected content playback using Apple's FairPlay DRM on iOS.

## Overview

Content protected with OpenTDF Standard TDF format is played back using FairPlay Streaming DRM. Instead of decrypting content in app memory (which would expose keys), we leverage Apple's hardware-backed FairPlay to securely handle keys and decrypt video using the Secure Enclave.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TDF + FairPlay Playback Architecture                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   iOS App (Arkavo)                                                           │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                                                                       │  │
│   │  1. ContentDetailView                                                 │  │
│   │     ├─ Fetch TDF via Iroh (payloadTicket)                            │  │
│   │     │   └─ Returns: ZIP archive (manifest.json + 0.payload)          │  │
│   │     │                                                                 │  │
│   │  2. TDFArchiveReader                                                  │  │
│   │     ├─ Extract manifest.json from ZIP                                │  │
│   │     │   └─ Contains: wrappedKey, iv, algorithm, kasURL               │  │
│   │     └─ Write 0.payload to temp file                                  │  │
│   │         └─ AES-128-CBC encrypted video                               │  │
│   │                                                                       │  │
│   │  3. TDFVideoPlayerView + AVPlayer                                     │  │
│   │     └─ AVContentKeySession (FairPlay)                                │  │
│   │         └─ Generates SPC (Server Playback Context)                   │  │
│   │                                                                       │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                              │                                               │
│                              │ POST /media/v1/key-request                    │
│                              │ Body: { spcData, tdfManifest (base64) }       │
│                              ▼                                               │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                                                                       │  │
│   │  Arkavo Server (https://100.arkavo.net)                              │  │
│   │     │                                                                 │  │
│   │     ├─ Parse TDF manifest                                            │  │
│   │     ├─ Extract RSA-wrapped DEK (wrappedKey)                          │  │
│   │     ├─ Unwrap DEK with KAS RSA private key                           │  │
│   │     ├─ Re-wrap DEK with FairPlay SDK → CKC                           │  │
│   │     └─ Return CKC to client                                          │  │
│   │                                                                       │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                              │                                               │
│                              │ Response: { wrappedKey: base64(CKC) }         │
│                              ▼                                               │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                                                                       │  │
│   │  iOS Secure Enclave                                                   │  │
│   │     └─ AVPlayer processes CKC                                        │  │
│   │     └─ Hardware decrypts video (key never exposed to app)            │  │
│   │     └─ Plays decrypted video                                         │  │
│   │                                                                       │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## End-to-End Flow

### Content Publishing (ArkavoCreator - macOS)

```
1. Record Video
   └─ AVCaptureSession records to .mov file

2. TDF Protection
   └─ RecordingProtectionService.protectVideo()
       ├─ Generate AES-128-CBC key (DEK)
       ├─ Encrypt video with DEK
       ├─ Wrap DEK with KAS RSA public key
       └─ Create TDF ZIP archive:
           ├─ manifest.json (kasURL, wrappedKey, iv, algorithm)
           └─ 0.payload (encrypted video)

3. Publish to Iroh Network
   └─ IrohContentService.publishContent()
       ├─ Upload TDF archive → payloadTicket
       ├─ Create ContentDescriptor (metadata + payloadTicket)
       └─ Upload descriptor → contentTicket

4. Share Ticket
   └─ Copy contentTicket for viewers
```

### Content Playback (Arkavo - iOS)

```
1. Enter Content Ticket
   └─ CreatorContentView → TicketInputSheet

2. Fetch Content Descriptor
   └─ IrohContentService.fetchContent(ticket:)
       └─ Returns: ContentDescriptor with payloadTicket

3. Fetch TDF Archive
   └─ ContentDetailView → "Fetch Content" button
       └─ IrohContentService.fetchPayloadWithRetry(payloadTicket:)
           └─ Returns: TDF ZIP archive data

4. Extract & Prepare
   └─ ContentDetailView → "Play Video" button
       └─ TDFArchiveReader.extractAll(from:)
           ├─ Parse manifest.json → TDFManifestLite
           └─ Write 0.payload to temp file

5. FairPlay Playback
   └─ TDFVideoPlayerView
       ├─ Create AVContentKeySession(.fairPlayStreaming)
       ├─ Set TDFContentKeyDelegate
       ├─ Add asset as content key recipient
       └─ AVPlayer plays encrypted content

6. Key Exchange (automatic)
   └─ TDFContentKeyDelegate
       ├─ Start session: POST /media/v1/session/start
       ├─ Get certificate: GET /media/v1/certificate
       ├─ Generate SPC from AVPlayer
       ├─ Request CKC: POST /media/v1/key-request
       │   └─ Body: { sessionId, spcData, tdfManifest }
       └─ Provide CKC to AVPlayer
           └─ Hardware decryption via Secure Enclave
```

## Technical Details

### TDF3 Archive Format

```
content.tdf (ZIP archive)
├── manifest.json     ← Encryption metadata
└── 0.payload         ← AES-128-CBC encrypted content
```

### manifest.json Structure

```json
{
  "encryptionInformation": {
    "type": "split",
    "keyAccess": [{
      "type": "wrapped",
      "url": "https://100.arkavo.net/kas",
      "wrappedKey": "BASE64_RSA_OAEP_WRAPPED_DEK"
    }],
    "method": {
      "algorithm": "AES-128-CBC",
      "iv": "BASE64_INITIALIZATION_VECTOR"
    }
  },
  "meta": {
    "assetId": "UUID",
    "protectedAt": "ISO8601_TIMESTAMP"
  }
}
```

### Server API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/media/v1/session/start` | POST | Initialize FairPlay session |
| `/media/v1/certificate` | GET | Fetch FairPlay certificate |
| `/media/v1/key-request` | POST | Exchange SPC for CKC |

### Key Request Payload

```json
{
  "sessionId": "session-uuid",
  "userId": "user-id",
  "assetId": "content-uuid",
  "spcData": "base64-spc-from-avplayer",
  "tdfManifest": "base64-encoded-manifest-json"
}
```

### Key Response

```json
{
  "sessionPublicKey": "-----BEGIN PUBLIC KEY-----...",
  "wrappedKey": "base64-fairplay-ckc",
  "status": "success"
}
```

## File Structure

### ArkavoKit (Shared Library)

```
ArkavoKit/Sources/ArkavoSocial/
├── TDFArchiveReader.swift      ← Extract manifest/payload from TDF ZIP
├── IrohContentService.swift    ← Publish/fetch content via Iroh
├── ContentTicketCache.swift    ← Cache content tickets locally
└── ...
```

### Arkavo (iOS App)

```
Arkavo/Arkavo/
├── TDFContentKeyDelegate.swift  ← AVContentKeySessionDelegate for FairPlay
├── TDFVideoPlayerView.swift     ← Video player with FairPlay integration
├── ContentDetailView.swift      ← Content details + play button
├── CreatorContentView.swift     ← List of creator's content
└── CreatorProfileDisplayView.swift ← Creator profile with content
```

## Security Model

### Key Protection Chain

1. **Content Encryption**: AES-128-CBC with random DEK
2. **Key Wrapping**: RSA-2048 OAEP (KAS public key)
3. **Transport**: HTTPS with certificate pinning
4. **Key Delivery**: FairPlay CKC (hardware-bound)
5. **Decryption**: Secure Enclave (key never in app memory)

### FairPlay DRM L1

- Hardware-backed key storage
- Keys never exposed to application code
- Secure video path to display
- Meets premium content protection requirements

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| ZIPFoundation | 0.9.19 | Extract TDF ZIP archives |
| AVFoundation | iOS 26+ | FairPlay content key session |
| AVKit | iOS 26+ | Video player UI |

## Testing Checklist

### ArkavoCreator (macOS)

- [ ] Record 10s test video
- [ ] TDF protect (verify .tdf file created)
- [ ] Publish to Iroh (verify ticket shown)
- [ ] Copy content ticket

### Arkavo (iOS)

- [ ] Enter ticket in CreatorContentView
- [ ] Content card shows correct metadata
- [ ] Tap "Fetch Content" → Progress → Success
- [ ] Tap "Play Video" → Video plays with audio
- [ ] Verify no raw key visible in logs (FairPlay L1)
- [ ] Dismiss player → returns to detail view

### Error Scenarios

| Scenario | Expected |
|----------|----------|
| Invalid ticket | "Content not found" |
| Server down | "Session failed" |
| No FairPlay cert | "Certificate error" |
| Invalid CKC | "Playback failed" |

## Related Documentation

- [Standard TDF + FairPlay Integration](/arkavo-rs/docs/standard_tdf_fairplay_integration.md)
- [FairPlay Streaming](/arkavo-rs/docs/fairplay.md)
- [NTDF-RTMP Streaming](NTDF-RTMP-STREAMING.md)
