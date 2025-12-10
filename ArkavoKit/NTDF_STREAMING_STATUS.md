# NTDF Streaming Status - 2025-12-09

## Current State: KAS Rewrap Working, Decryption Pending

### What's Working
1. **v12 (L1L) header format** - OpenTDFKit NanoTDFCollectionBuilder now defaults to v12
2. **GMAC binding** - Fixed arkavo-rs to use 8 bytes (not 16) per NanoTDF spec 3.3.1.3
3. **KAS rewrap** - Successfully returns wrapped key (60 bytes) and session key (33 bytes)
4. **Session key parsing** - Client now handles raw SEC1 65-byte format from server
5. **Symmetric key unwrap** - 256-bit key successfully derived
6. **Decryptor initialization** - Reports success
7. **Sequence headers** - Video (SPS/PPS) and Audio (48kHz stereo) parsed correctly

### What's NOT Working
- **Video playback** - Decryptor initialized but no video frames displayed
- Need to investigate frame decryption and delivery to video renderer

### Recent Fixes (commits to check)
- `OpenTDFKit` main branch:
  - `cc38a26` - v12 (L1L) format default in NanoTDFCollectionBuilder
  - `e3ffe32` - Support raw SEC1 format for session public key parsing

- `arkavo-rs` opentdf-kas-public-key branch:
  - `10782a8` - GMAC binding size 8 bytes (not 16)
  - `f453cd7` - Reverted SPKI change (server sends raw SEC1, client handles it)

- `ArkavoKit` ntdf-rtmp-streaming branch:
  - `e60ca22` - Updated OpenTDFKit dependency

### Next Steps to Debug
1. Check if encrypted frames are being received after sequence headers
2. Verify frame decryption is actually happening (add logging)
3. Check if decrypted frames are being passed to video decoder
4. Verify CMSampleBuffer creation from decrypted NALUs
5. Check if frames are being enqueued to AVSampleBufferDisplayLayer

### Key Files
- `/Users/paul/Projects/arkavo/app/ArkavoKit/Sources/ArkavoStreaming/RTMP/NTDFStreamingSubscriber.swift`
  - `StreamingCollectionDecryptor` - handles frame decryption
  - Check `decryptVideoFrame()` and callback delivery

- `/Users/paul/Projects/arkavo/OpenTDFKit/OpenTDFKit/NanoTDFCollectionDecryptor.swift`
  - `decryptItem()` - actual AES-GCM decryption

### Wire Format
- Collection item format: `[3-byte IV][3-byte length][ciphertext+16-byte tag]`
- Publisher sends NTDF header before each keyframe for late-joining subscribers
- Magic bytes `NTDF` (0x4E544446) identify header frames in video stream

### Logs to Look For
After "Decryptor initialized, ready to decrypt frames":
- Look for video frame processing logs
- Check for decryption errors
- Verify frame callback invocations
