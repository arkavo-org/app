# FairPlay CBCS Reference Test

This directory contains reference SAMPLE-AES (CBCS) encrypted fMP4 content generated
with Apple's `mediafilesegmenter` for validating FairPlay playback.

## Contents

```
FairPlayTest/
├── README.md                    # This file
├── REFERENCE_ANALYSIS.md        # Detailed analysis of fMP4 structure
├── fps_key.bin                  # 32-byte key file (key + IV)
├── FairPlayReferenceTest.swift  # Test harness code
└── reference/                   # Generated fMP4 content
    ├── fileSequence0.mp4        # Init segment (moov)
    ├── fileSequence*.m4s        # Media segments (moof+mdat)
    ├── prog_index.m3u8          # HLS playlist with SAMPLE-AES
    └── iframe_index.m3u8        # I-frame playlist
```

## Test Key Configuration

Using Apple's test key from `FairPlayStreamingTestContentv1.0`:

| Field | Value |
|-------|-------|
| Asset ID | `twelve` |
| Key | `0x3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C` (16 bytes) |
| IV | `0xD5FBD6B82ED93E4EF98AE40931EE33B7` (16 bytes) |
| Key URI | `skd://twelve` |

## Phase 0 Status

### Completed

- [x] Generated reference fMP4 with `mediafilesegmenter`
- [x] Analyzed init segment structure (encv, sinf, schm=cbcs, tenc)
- [x] Analyzed media segment structure (moof, senc, saiz, saio)
- [x] Documented key file format (32 bytes = key + IV)
- [x] Verified server has FairPlay support (`--features fairplay`)
- [x] Created test harness code

### Pending - Device Testing Required

- [ ] Configure arkavo-rs with test FairPlay certificate
- [ ] Serve reference content via HTTP
- [ ] Test playback on physical iOS device
- [ ] Verify hardware enforcement (screen recording = black)

## Running the Test

### 1. Start Local HTTP Server

```bash
cd /Users/paul/Projects/arkavo/app/FairPlayTest
python3 -m http.server 8080 -d reference/
```

Playlist URL: `http://localhost:8080/prog_index.m3u8`

### 2. Configure Server

The arkavo-rs server must be configured with:
- FairPlay certificate (`FairPlayCertificate.der`)
- ASc file (FPS Application Secret)
- Private key

These files come from Apple's FairPlay Streaming license.

### 3. Test on Device

FairPlay requires a physical iOS/macOS device (not simulator).

The test will:
1. Load playlist with `skd://twelve` key URI
2. Trigger AVContentKeySession delegate
3. Generate SPC with device attestation
4. Exchange SPC for CKC from server
5. Play content with hardware decryption

### 4. Verify Hardware Enforcement

Success criteria:
- Video plays normally
- Screen recording produces **black video** (hardware enforcement active)

## Key Technical Findings

### Init Segment (`fileSequence0.mp4`)

```
encv
└── sinf
    ├── frma (original_format=avc1)
    ├── schm (scheme_type=cbcs, version=65536)
    └── schi/tenc
        ├── default_crypt_byte_block = 1
        ├── default_skip_byte_block = 9
        ├── default_constant_IV_size = 16
        └── default_constant_IV = d5fbd6b82ed93e4ef98ae40931ee33b7
```

### Media Segment Structure

```
moof
└── traf
    ├── tfhd (track info)
    ├── tfdt (decode time)
    ├── senc (subsample encryption)
    │   └── per-sample: [clear_bytes, encrypted_bytes] pairs
    ├── saiz (sample aux info sizes)
    ├── saio (sample aux info offsets)
    └── trun (sample timing)
mdat
    └── encrypted sample data
```

### senc Subsample Format

Each sample in senc contains:
- `subsample_count: uint16`
- For each subsample:
  - `bytes_of_clear_data: uint16`
  - `bytes_of_protected_data: uint32`

Example from first sample: 8 subsamples with varying clear bytes (35, 12, etc.)
corresponding to NAL header + slice header lengths.

## See Also

- [REFERENCE_ANALYSIS.md](REFERENCE_ANALYSIS.md) - Detailed fMP4 structure analysis
- [../docs/FAIRPLAY-FMP4-CBCS-PLAN.md](../docs/FAIRPLAY-FMP4-CBCS-PLAN.md) - Implementation plan
- [../docs/FAIRPLAY-TEST-PLAN.md](../docs/FAIRPLAY-TEST-PLAN.md) - Testing strategy
