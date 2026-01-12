# FairPlay CBCS Reference Analysis

## Phase 0 Status

### Completed
- [x] Created reference fMP4 with `mediafilesegmenter` using SAMPLE-AES
- [x] Analyzed init segment structure (encv, sinf, schm=cbcs, tenc)
- [x] Analyzed media segment structure (moof, senc, saiz, saio)
- [x] Documented key file format (32 bytes = key + IV)
- [x] Verified server has FairPlay support (`--features fairplay`)

### Pending - Device Testing Required
- [ ] Configure server with test FairPlay certificate
- [ ] Serve reference content via HTTP
- [ ] Test playback on physical iOS device
- [ ] Verify hardware enforcement (screen recording = black)

## Device Testing Setup

### 1. Start arkavo-rs Server with FairPlay

```bash
cd /Users/paul/Projects/arkavo/arkavo-rs

# Set FairPlay credentials path
export FAIRPLAY_CREDENTIALS_PATH="./vendor/FairPlay_Streaming_Server_SDK_26/Development/Key_Server_Module/credentials"

# Build with FairPlay feature
cargo build --release --features fairplay

# Run server
./target/release/arkavo-rs
```

### 2. Serve Reference Content

```bash
cd /Users/paul/Projects/arkavo/app/FairPlayTest
python3 -m http.server 8080 -d reference/
```

Content URL: `http://<your-mac-ip>:8080/prog_index.m3u8`

### 3. Server API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/media/v1/session/start` | POST | Start playback session |
| `/media/v1/key-request` | POST | FairPlay SPC->CKC exchange |
| `/media/v1/certificate` | GET | Get FairPlay certificate |

### 4. Key Request Payload

```json
{
  "sessionId": "<from session/start>",
  "userId": "test-user",
  "assetId": "twelve",
  "spcData": "<base64-encoded SPC>",
  "tdfManifest": "<base64-encoded manifest with wrapped DEK>"
}
```

### 5. Test with ArkavoCreator

Use the existing `TDFContentKeyDelegate` which handles:
1. Session start
2. Certificate fetch
3. SPC generation
4. CKC exchange

---

Generated from Apple's test content using `mediafilesegmenter` with SAMPLE-AES encryption.

## Source
- **Input video:** `FairPlayStreamingTestContentv1.0/Gear4_16x9_1280x720_30hz.mov`
- **Test key:** `0x3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C3C` (16 bytes)
- **Test IV:** `0xD5FBD6B82ED93E4EF98AE40931EE33B7` (16 bytes)
- **Asset ID:** `twelve`
- **Key file format:** 32 bytes (key + IV concatenated)

## Command Used
```bash
mediafilesegmenter --format iso \
  --streaming-key-delivery \
  --stream-encrypt \
  --encrypt-key-file fps_key.bin \
  --encrypt-key-url "skd://twelve" \
  --video-only \
  --index-file prog_index.m3u8 \
  -f ./reference/ \
  Gear4_16x9_1280x720_30hz.mov
```

## Playlist Format
```m3u8
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://twelve",KEYFORMAT="com.apple.streamingkeydelivery",KEYFORMATVERSIONS="1"
#EXT-X-MAP:URI="fileSequence0.mp4"
```

## Init Segment Structure (fileSequence0.mp4)

```
ftyp (major_brand=iso5)
  compatible: isom, iso5, hlsf
moov
  mvhd (timescale=600)
  trak
    tkhd (id=1, width=1280, height=720)
    mdia
      mdhd (timescale=2997)
      hdlr (type=vide)
      minf
        vmhd
        dinf/dref
        stbl
          stsd
            encv (encrypted video)
              sinf
                frma (original_format=avc1)
                schm (scheme_type=cbcs, version=65536)
                schi
                  tenc (version=1)
                    default_isProtected = 1
                    default_Per_Sample_IV_Size = 0
                    default_KID = 00000000-0000-0000-0000-000000000000
                    default_crypt_byte_block = 1
                    default_skip_byte_block = 9
                    default_constant_IV_size = 16
                    default_constant_IV = d5fbd6b82ed93e4ef98ae40931ee33b7
              avcC (profile=Main, level=31, NALU_length=4)
          stts, stsc, stsz, stco (empty for fMP4)
  mvex
    trex (track_id=1)
```

### Key Observations - Init Segment
1. **Scheme type is `cbcs`** (not `cenc`)
2. **1:9 pattern**: crypt_byte_block=1, skip_byte_block=9
3. **Constant IV**: 16 bytes, same for all samples (no per-sample IV)
4. **KID is all zeros** - key lookup via skd:// URI, not KID
5. **encv wraps avc1** with sinf/tenc for encryption info
6. No pssh box in init segment (key delivery via EXT-X-KEY)

## Media Segment Structure (fileSequence1.m4s)

```
moof
  mfhd (sequence_number=1)
  traf
    tfhd (track_id=1, flags=0x20038)
      default_sample_duration = 100
      default_sample_size = 57169
      default_sample_flags = 0x10000
    tfdt (version=1, base_media_decode_time)
    senc (flags=0x02 = use_subsample_encryption)
      sample_info_count = 90
      [per-sample subsample data]
    saiz
      default_sample_info_size = 50
      sample_count = 90
    saio
      entry_count = 1
      offset = [calculated]
    trun (version=1, flags=0xe01)
      sample_count, data_offset, per-sample info
mdat
  [encrypted sample data]
```

### Key Observations - Media Segment
1. **Multiple moof/mdat pairs** per segment file (not just one)
2. **senc flags=0x02** means subsample encryption data present
3. **saiz default_sample_info_size=50** bytes per sample
4. **saio** provides offset to senc data within traf
5. **tfhd flags=0x20038** includes default-base-is-moof flag

## senc Box Subsample Structure

Each sample entry in senc:
```
subsample_count: uint16
for each subsample:
  bytes_of_clear_data: uint16
  bytes_of_protected_data: uint32
```

Example from first sample:
- 8 subsamples
- Subsample 0: 35 clear, 9418 encrypted
- Subsample 1: 12 clear, 6553 encrypted
- etc.

**Total per sample = 2 + (6 * subsample_count) bytes**

For 8 subsamples: 2 + (6 * 8) = 50 bytes (matches saiz default_sample_info_size)

## Important Implementation Notes

### 1. Clear Bytes per NAL
The clear bytes values (35, 12, etc.) represent **NAL header + slice header** that must remain unencrypted.
- Values vary per NAL unit (slice headers have variable length)
- Apple's segmenter parses the slice header to determine exact clear bytes
- Conservative fallback: 64 bytes

### 2. saio Offset Calculation
The saio offset points to the senc sample data (after senc box header).
- Offset is relative to moof box start (when tfhd has default-base-is-moof flag)
- Must be calculated after sizing all boxes (two-pass)

### 3. No Per-Sample IV
With constant IV (CBCS mode):
- senc does NOT contain per-sample IVs
- Only subsample clear/encrypted byte counts
- IV is in tenc box (init segment)

### 4. Key Delivery
- Primary: EXT-X-KEY tag with skd:// URI
- KID in tenc can be zeros (lookup by asset ID, not KID)
- No pssh box required for HLS playback
