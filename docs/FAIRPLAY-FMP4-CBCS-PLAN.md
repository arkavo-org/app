# FairPlay fMP4/CBCS Implementation Plan

## Executive Summary

This document outlines the approach to implement true FairPlay DRM support in ArkavoCreator using fMP4 (fragmented MP4) with CBCS (Common Encryption Scheme - CBC mode) encryption.

## Current State

### What We Have
- **TDF HLS Protection**: AES-128-CBC encryption of entire HLS segments
- **KAS Integration**: Key wrapping/unwrapping via rewrap endpoint
- **Local Decryption**: Client decrypts segments before playback
- **Working Playback**: Content plays after local decryption

### What's Missing for True FairPlay
- **SAMPLE-AES/CBCS**: Encryption at NAL unit level (not full segment)
- **skd:// URIs**: FairPlay key delivery URLs in playlist
- **Hardware Decryption**: AVPlayer decrypts via Secure Enclave

## The Problem

**Apple provides playback/decryption APIs but NOT authoring/encryption APIs for CBCS content.**

| API | Purpose | Can Author Encrypted Content? |
|-----|---------|------------------------------|
| AVContentKeySession | FairPlay key handling during playback | No (playback only) |
| AVPlayer | Playback of encrypted content | No (playback only) |
| AVAssetWriter | Media file creation | No (unencrypted only) |
| AVAssetExportSession | Media export | No (unencrypted only) |
| VideoToolbox | Hardware encoding | No (encoding only) |
| CryptoKit | Cryptographic primitives | Yes (low-level AES) |

**Authoring CBCS-encrypted content typically requires:**
- Apple's `mediafilesegmenter` (cannot redistribute)
- Third-party packagers (Shaka Packager, Bento4)
- Cloud encoding services
- Custom implementation using low-level crypto + bitstream parsing

## Proposed Solution: Manual CBCS Implementation

Since Apple doesn't provide CBCS encryption APIs, we must implement it ourselves using:
1. **CryptoKit** for AES-128-CBC encryption
2. **AVFoundation** for media parsing
3. **Manual NAL unit extraction** from H.264/H.265 streams

### CBCS Encryption Specification

CBCS (Common Encryption Scheme - CBC mode) is part of the CENC (Common Encryption) standard
(ISO/IEC 23001-7) and encrypts media at the **sample/NAL unit level**.

#### Video Encryption (H.264/H.265)
```
┌─────────────────────────────────────────────────────────────────┐
│                    CBCS Video-Level Encryption                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  NAL Unit Structure:                                            │
│  ┌──────────┬──────────────────────────────────────────────┐   │
│  │  Header  │              Payload (encrypted)              │   │
│  │ (clear)  │  ┌────────┬────────┬────────┬────────┐       │   │
│  │          │  │ Block1 │ Block2 │ Block3 │  ...   │       │   │
│  │          │  │ (enc)  │(clear) │ (enc)  │        │       │   │
│  └──────────┴──┴────────┴────────┴────────┴────────┴───────┘   │
│                                                                 │
│  Encryption Pattern (configurable profile):                     │
│  - Common pattern: 1:9 (encrypt 1 block, skip 9 blocks)        │
│  - Pattern is a profile/configuration choice, NOT mandatory    │
│                                                                 │
│  Block size: 16 bytes (AES block)                              │
│  IV: Constant per sample or derived from sample number         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Audio Encryption (AAC)
Audio encryption in CBCS differs from video. Since AAC does not use NAL units, encryption is applied to the raw AAC access units.
- **Scheme**: CBCS (AES-128-CBC)
- **Pattern**: 0:0 (Full encryption is required for audio by FairPlay specs).
- **Subsample Mapping**: Audio samples are typically treated as a single encrypted subsample per access unit, preserving the ADTS header (if present) in the clear.
- **Signaling**: Must be signaled in the `stsd` (Sample Description) atom using the `enca` (encrypted audio) box instead of `mp4a`.

**Note**: The 1:9 pattern is a recommended configuration in ISO/IEC 23001-7 for video to balance
encryption coverage and performance. Audio requires full payload encryption for complete hardware enforcement protection.

### NAL Units to Encrypt (H.264)
- **Type 1**: Non-IDR slice (P/B frames) - ENCRYPT
- **Type 5**: IDR slice (I frames) - ENCRYPT
- **Type 6**: SEI - DO NOT ENCRYPT
- **Type 7**: SPS - DO NOT ENCRYPT
- **Type 8**: PPS - DO NOT ENCRYPT

## Implementation Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ArkavoCreator Packaging                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Source Video                                                │
│     └─► AVAsset                                                 │
│                                                                 │
│  2. Extract Samples                                             │
│     └─► AVAssetReader + CMSampleBuffer                         │
│         └─► Extract NAL units from each sample                  │
│                                                                 │
│  3. CBCS Encryption                                             │
│     └─► CBCSEncryptor (new component)                          │
│         ├─► Parse NAL unit headers                              │
│         ├─► Identify Type 1/5 NAL units                         │
│         ├─► Apply 1:9 encryption pattern                        │
│         └─► Preserve headers in clear                           │
│                                                                 │
│  4. Create fMP4 Segments                                        │
│     └─► FMP4Writer (new component)                             │
│         ├─► Write encrypted samples to fMP4                     │
│         ├─► Add PSSH box (encryption metadata)                  │
│         └─► Create init segment + media segments                │
│                                                                 │
│  5. Generate HLS Playlist                                       │
│     └─► FairPlayPlaylistGenerator                              │
│         ├─► EXT-X-KEY with skd:// URI                          │
│         ├─► KEYFORMAT="com.apple.streamingkeydelivery"         │
│         └─► fMP4 segment references                            │
│                                                                 │
│  6. Package as TDF                                              │
│     └─► TDF archive with manifest + encrypted fMP4             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## New Components Required

### 1. CBCSEncryptor
```swift
/// Encrypts video samples using CBCS pattern
actor CBCSEncryptor {
    /// Encrypt a NAL unit using CBCS 1:9 pattern
    func encryptNALUnit(
        data: Data,
        key: SymmetricKey,
        iv: Data
    ) -> Data

    /// Parse NAL units from CMSampleBuffer
    func extractNALUnits(from sample: CMSampleBuffer) -> [NALUnit]

    /// Determine if NAL unit should be encrypted
    func shouldEncrypt(nalType: UInt8) -> Bool
}
```

### 2. AudioEncryptor
```swift
/// Encrypts audio samples using CBCS (full encryption)
actor AudioEncryptor {
    /// Encrypt an AAC access unit
    func encryptAudioSample(
        data: Data,
        key: SymmetricKey,
        iv: Data
    ) -> Data
}
```

### 3. FMP4Writer
```swift
/// Creates fragmented MP4 files with encrypted samples
actor FMP4Writer {
    /// Write initialization segment (moov box)
    func writeInitSegment(
        videoFormat: CMFormatDescription,
        audioFormat: CMFormatDescription?
    ) -> Data

    /// Write media segment (moof + mdat boxes)
    func writeMediaSegment(
        samples: [CMSampleBuffer],
        segmentNumber: Int
    ) -> Data

    /// Add encryption metadata (PSSH box)
    func addPSSHBox(keyID: Data, systemID: Data) -> Data
}
```

### 3. FairPlayPlaylistGenerator
```swift
/// Generates HLS playlist with FairPlay encryption tags
struct FairPlayPlaylistGenerator {
    /// Generate master playlist
    func generateMasterPlaylist(
        variants: [HLSVariant]
    ) -> String

    /// Generate media playlist with FairPlay tags
    func generateMediaPlaylist(
        segments: [FMP4Segment],
        assetID: String,
        keyServerURL: URL
    ) -> String
}
```

## HLS Playlist Format

### Master Playlist
```m3u8
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS

#EXT-X-STREAM-INF:BANDWIDTH=2000000,CODECS="avc1.4d401f,mp4a.40.2"
variant.m3u8
```

### Media Playlist (FairPlay)
```m3u8
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-MAP:URI="init.mp4"

#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI="skd://asset-id-here",KEYFORMAT="com.apple.streamingkeydelivery",KEYFORMATVERSIONS="1"

#EXTINF:6.000,
segment0.m4s
#EXTINF:6.000,
segment1.m4s
#EXTINF:4.500,
segment2.m4s

#EXT-X-ENDLIST
```

## Server-Side Requirements

### KAS FairPlay Endpoint
The KAS must support FairPlay key delivery:

```
POST /media/v1/key-request
Input:
{
    "session_id": "uuid",
    "asset_id": "asset-id",
    "spc_data": "<base64 SPC from AVContentKeySession>",
    "tdf_wrapped_key": "<base64 RSA-wrapped DEK>"
}

Output:
{
    "wrapped_key": "<base64 CKC>",
    "metadata": { "ckc_size": 1234 }
}
```

The server:
1. Receives SPC (Server Playback Context) from client
2. Unwraps TDF DEK using KAS private key
3. Re-wraps DEK using FairPlay Server SDK
4. Returns CKC (Content Key Context)

## Implementation Phases

### Phase 1: NAL Unit & Audio Parsing (Week 1)
- [ ] Create NAL unit parser for H.264
- [ ] Create NAL unit parser for H.265 (HEVC)
- [ ] Create AAC access unit extractor
- [ ] Unit tests for media parsing

### Phase 2: CBCS Encryption (Week 2)
- [ ] Implement CBCS 1:9 pattern encryption for video
- [ ] Implement CBCS full encryption for audio
- [ ] Handle subsample encryption mapping for both tracks
- [ ] Unit tests with test vectors

### Phase 3: fMP4 Core Structure (Week 3)
- [ ] Implement ISO BMFF box writer foundations
- [ ] Create valid unencrypted fMP4 segments (init + media)
- [ ] Verify playback of unencrypted custom segments in AVPlayer

### Phase 4: Encryption Atoms & Signaling (Week 4)
- [ ] Implement encryption boxes (`senc`, `saiz`, `saio`)
- [ ] Implement Protection System Specific Header (`pssh`)
- [ ] Implement Track Encryption Box (`tenc`) in `moov`
- [ ] Implement `enca` (encrypted audio) signaling in `stsd`

### Phase 5: Timing & Synchronization (Week 5)
- [ ] Implement correct `ctts` (Composition Time) calculation
- [ ] Implement `tfdt` (Track Fragment Decode Time) continuity
- [ ] Validate A/V sync on generated segments

### Phase 6: Playlist & Validation (Week 6)
- [ ] Generate FairPlay-compatible HLS playlists
- [ ] Binary inspection of generated files vs reference fMP4s
- [ ] Debugging with `MP4Box` and `ffprobe`
- [ ] Validate encryption coverage with test keys

### Phase 7: Integration & UI (Week 7)
- [ ] Integrate with ArkavoCreator UI
- [ ] Update TDF packaging
- [ ] End-to-end testing with KAS and AVPlayer
- [ ] Performance profiling and optimization

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Complex MP4 box structure | High | Use reference implementations, extensive testing; consider integrating a C-based muxer if Swift implementation fails validation |
| Audio/Video Sync (fMP4) | High | Rigorous validation of `ctts`, `tfdt`, and `sdtp` atoms during packaging |
| CBCS pattern variations | Medium | Follow Apple's exact spec from HLS authoring guide |
| FairPlay SDK compatibility | High | Test with real FairPlay certificate early |
| Performance Overhead | Medium | Use async/parallel processing for segments; profile CPU usage on older devices |

## Alternative: Hybrid Approach

If full CBCS implementation proves too complex, a hybrid approach:

1. **Encrypt segments with AES-128-CBC** (current approach)
2. **Use AVAssetResourceLoaderDelegate** (not AVContentKeySession)
3. **Intercept key requests** and provide decrypted key
4. **Local decryption** in resource loader

This sacrifices hardware decryption but maintains FairPlay-style key delivery.

## References

- [ISO/IEC 23001-7:2016 - Common encryption](https://www.iso.org/standard/68042.html)
- [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
- [FairPlay Streaming Overview](https://developer.apple.com/streaming/fps/)
- [ISO Base Media File Format](https://www.iso.org/standard/68960.html)

## Decision Required

**Recommended**: Proceed with Phase 1-2 (NAL parsing + CBCS encryption) to validate feasibility before committing to full fMP4 implementation.

**Alternative**: If timeline is critical, continue with current TDF + local decryption approach, which is working and secure (just not "true" FairPlay).
