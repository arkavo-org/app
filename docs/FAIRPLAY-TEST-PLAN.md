# FairPlay fMP4/CBCS Test Plan

## Overview
This document defines the testing strategy for the `ArkavoMediaKit` FairPlay implementation. Testing will focus on cryptographic correctness, ISO BMFF compliance, and playback stability.

## Test Levels

### 1. Unit Testing (Low Level)
**Objective:** Verify individual components (Parsers, Encryptors, Atoms) in isolation.

#### A. NAL Unit Parsing
*   **Test Case:** `testExtractNALUnitsH264`
    *   **Input:** Raw H.264 byte stream with known SPS, PPS, IDR, and Non-IDR slices.
    *   **Assertion:** Parser correctly identifies NAL types and boundaries.
*   **Test Case:** `testExtractNALUnitsHEVC`
    *   **Input:** HEVC byte stream.
    *   **Assertion:** Parser correctly identifies NAL types (H.265 specific).

#### B. CBCS Encryption
*   **Test Case:** `testCBCSVideoPattern1_9`
    *   **Input:** 1600 bytes of data (100 blocks).
    *   **Assertion:** 
        *   Block 1: Encrypted.
        *   Blocks 2-10: Clear.
        *   Block 11: Encrypted.
        *   ...
        *   IV check: Ensure IV is correctly applied.
*   **Test Case:** `testCBCSAudioFullEncryption`
    *   **Input:** AAC frame payload.
    *   **Assertion:** Entire payload is encrypted (excluding ADTS header if modeled).
*   **Test Case:** `testSubsampleDescription`
    *   **Input:** Encrypted NAL unit.
    *   **Assertion:** Generated `saiz` (Sample Auxiliary Information Sizes) and `saio` (Offsets) data matches the encryption layout.

#### C. Atom Generation
*   **Test Case:** `testPSSHBoxGeneration`
    *   **Input:** System ID, Key ID.
    *   **Assertion:** Output bytes match standard PSSH box structure.

### 2. Integration Testing (Component Level)
**Objective:** Verify the interaction between the Parser, Encryptor, and Writer.

*   **Test Case:** `testWriteUnencryptedSegment`
    *   **Action:** Feed raw samples to `FMP4Writer` with encryption disabled.
    *   **Verification:**
        *   Use `mp4dump` (Bento4) or `ffprobe` to validate structure.
        *   Check that `moov` and `moof` atoms are structurally correct.
*   **Test Case:** `testWriteEncryptedSegmentStructure`
    *   **Action:** Feed raw samples to `FMP4Writer` with encryption enabled.
    *   **Verification:**
        *   Verify existence of `senc`, `saiz`, `saio` atoms in the output.
        *   Verify `schm` scheme type is `cbcs`.

### 3. Playback Verification (System Level)
**Objective:** Verify real-world playback and hardware enforcement.

#### A. Local Playback (Simulator/Device)
*   **Test Case:** `testPlaybackClearFMP4`
    *   **Setup:** Serve generated unencrypted fMP4 locally.
    *   **Action:** Play in `AVPlayer`.
    *   **Success:** Video plays, audio plays, A/V sync is correct.

*   **Test Case:** `testPlaybackFairPlay` (Device Only)
    *   **Setup:** 
        *   Generate encrypted HLS asset (Master + Media Playlists + Init + Segments).
        *   Host local HTTP server for assets.
        *   Implement `AVAssetResourceLoaderDelegate` to handle `skd://` requests.
    *   **Action:** Play in `AVPlayer`.
    *   **Success:** 
        *   Delegate receives key request.
        *   CKC is returned.
        *   Video plays securely.
        *   **Crucial:** Screen recording the player produces a black screen (Hardware Enforcement).

### 4. Regression & Negative Testing
*   **Test Case:** `testCorruptKey`
    *   **Action:** Provide wrong Key/IV to player.
    *   **Success:** Player throws specific decode error, app does not crash.
*   **Test Case:** `testMissingAtom`
    *   **Action:** Intentionally omit `pssh` box.
    *   **Success:** Player fails gracefully (error state) rather than hanging.

## Tools & Fixtures
*   **Reference Vectors:** Pre-generated valid CBCS fMP4 files (using Bento4) to compare byte-for-byte (or atom-for-atom) against `ArkavoMediaKit` output.
*   **Hex Editor:** For manual inspection of atom headers.
*   **Bento4 Tools:** `mp4dump`, `mp4info` for structural validation.

## Success Criteria
1.  **Hardware Enforcement:** Screen recording is blocked on physical device.
2.  **Compliance:** Output files pass `mp4dump` validation without errors.
3.  **Performance:** Encryption adds < 50ms overhead per segment (target).
