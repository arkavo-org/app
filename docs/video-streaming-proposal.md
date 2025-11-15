# Video Streaming Architecture Proposal

## Problem Statement

Current remote camera implementation uses **JPEG frame streaming** which is inefficient:

- Individual JPEG compression per frame (no temporal compression)
- High bandwidth (~750KB - 3MB/sec)
- Artificially limited to 15 FPS
- CPU-intensive compression
- Higher latency

## Proposed Solution: H.264/H.265 Video Streaming

Replace JPEG streaming with proper video encoding using VideoToolbox.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ iOS Device (RemoteCameraStreamer)                           │
├─────────────────────────────────────────────────────────────┤
│ ARKitCaptureManager                                         │
│   └─ Captures CVPixelBuffer (30 FPS)                        │
│                                                              │
│ VideoStreamEncoder (NEW)                                    │
│   ├─ VTCompressionSession (H.264/H.265)                     │
│   ├─ Hardware acceleration (VideoToolbox)                   │
│   ├─ Adaptive bitrate (2-5 Mbps)                            │
│   └─ Outputs: H.264 NAL units                               │
│                                                              │
│ NetworkStreamer                                             │
│   ├─ Packetizes H.264 NAL units                             │
│   ├─ Sends via TCP or UDP (configurable)                    │
│   └─ Metadata as separate JSON stream                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ Network (TCP/UDP)
                            │
┌─────────────────────────────────────────────────────────────┐
│ macOS (RemoteCameraServer)                                  │
├─────────────────────────────────────────────────────────────┤
│ NetworkReceiver                                             │
│   └─ Receives H.264 NAL units                               │
│                                                              │
│ VideoStreamDecoder (NEW)                                    │
│   ├─ VTDecompressionSession (H.264/H.265)                   │
│   ├─ Hardware acceleration (VideoToolbox)                   │
│   └─ Outputs: CVPixelBuffer                                 │
│                                                              │
│ RecordingSession                                            │
│   └─ Composites decoded frames                              │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: VideoStreamEncoder (iOS)

Create `Arkavo/Arkavo/VideoStreamEncoder.swift`:

```swift
import VideoToolbox
import CoreMedia

/// Lightweight H.264/H.265 encoder for streaming
/// Uses VideoToolbox VTCompressionSession (hardware accelerated)
final class VideoStreamEncoder {
    private var compressionSession: VTCompressionSession?

    struct Config {
        let width: Int = 1920
        let height: Int = 1080
        let frameRate: Int32 = 30
        let bitrate: Int = 3_000_000  // 3 Mbps default
        let codec: CMVideoCodecType = kCMVideoCodecType_H264
        let keyFrameInterval: Int = 60  // I-frame every 2 seconds
    }

    typealias OutputHandler = (Data, Bool, CMTime) -> Void
    //                          ↑     ↑     ↑
    //                          │     │     └─ Timestamp
    //                          │     └─ Is keyframe (I-frame)
    //                          └─ H.264 NAL unit data

    func encode(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // VTCompressionSessionEncodeFrame()
        // Hardware-accelerated encoding
        // Outputs NAL units via callback
    }
}
```

### Phase 2: VideoStreamDecoder (macOS)

Create `ArkavoRecorder/Sources/ArkavoRecorder/VideoStreamDecoder.swift`:

```swift
import VideoToolbox
import CoreMedia

/// Lightweight H.264/H.265 decoder for streaming
/// Uses VideoToolbox VTDecompressionSession (hardware accelerated)
final class VideoStreamDecoder {
    private var decompressionSession: VTDecompressionSession?

    typealias OutputHandler = (CVPixelBuffer, CMTime) -> Void

    func decode(_ h264Data: Data, isKeyFrame: Bool, timestamp: CMTime) {
        // VTDecompressionSessionDecodeFrame()
        // Hardware-accelerated decoding
        // Outputs CVPixelBuffer via callback
    }
}
```

### Phase 3: Update Protocol

Modify `RemoteCameraMessage` to support video NAL units:

```swift
public enum RemoteCameraMessage: Codable {
    case handshake(HandshakePayload)
    case videoNALU(VideoNALUPayload)  // NEW
    case metadata(CameraMetadataEvent)
    case audio(AudioPayload)

    public struct VideoNALUPayload: Codable {
        let sourceID: String
        let timestamp: Double
        let isKeyFrame: Bool
        let naluData: Data  // H.264 NAL unit (compressed!)
    }
}
```

### Phase 4: Integration

Update `RemoteCameraStreamer.swift`:

```swift
// OLD (JPEG)
private func makeFramePayload(buffer: CVPixelBuffer, timestamp: CMTime) -> RemoteCameraMessage.FramePayload? {
    let jpeg = ciContext.jpegRepresentation(...)  // ❌ Inefficient
    return RemoteCameraMessage.FramePayload(imageData: jpeg)
}

// NEW (H.264)
private var videoEncoder: VideoStreamEncoder?

private func encodeAndSendFrame(buffer: CVPixelBuffer, timestamp: CMTime) {
    videoEncoder?.encode(buffer, timestamp: timestamp) { naluData, isKeyFrame, timestamp in
        let payload = RemoteCameraMessage.VideoNALUPayload(
            sourceID: sourceID,
            timestamp: CMTimeGetSeconds(timestamp),
            isKeyFrame: isKeyFrame,
            naluData: naluData  // ✅ Much smaller!
        )
        send(message: .videoNALU(payload))
    }
}
```

## Benefits

### Bandwidth Reduction
- JPEG: 750KB - 3MB/sec @ 15 FPS
- H.264: 250KB - 625KB/sec @ 30 FPS
- **Savings: 50-80% reduction**

### Latency Improvement
- Hardware encoding/decoding (VideoToolbox)
- Lower per-frame overhead
- Can use UDP for lower latency (optional)

### Frame Rate
- Current: 15 FPS (artificially limited)
- Proposed: 30 FPS (full ARKit rate)

### Quality
- I-frames + P-frames = better temporal compression
- Consistent quality across motion
- Adaptive bitrate possible

## Migration Strategy

### Clean Break - No Backwards Compatibility

Remove JPEG frame streaming entirely and replace with H.264 video encoding:

```swift
enum RemoteCameraMessage {
    case handshake(HandshakePayload)
    case videoNALU(VideoNALUPayload)  // H.264 only
    case metadata(CameraMetadataEvent)
    case audio(AudioPayload)
}
```

Benefits:
- Simpler codebase (no dual code paths)
- Immediate performance improvements
- Cleaner architecture

## Performance Targets

| Metric | Before (JPEG) | After (H.264) | Improvement |
|--------|---------------|---------------|-------------|
| Bandwidth | 750KB - 3MB/s | 250KB - 625KB/s | **50-80% reduction** |
| FPS | 15 (throttled) | 30 (full rate) | **2x faster** |
| Latency | ~100-200ms | ~50-100ms | **50% lower** |
| CPU Usage | High (software) | Low (hardware) | **HW accelerated** |
| Quality | Fixed 60% JPEG | Adaptive H.264 | **Better & adaptive** |

## References

- [VideoToolbox Programming Guide](https://developer.apple.com/documentation/videotoolbox)
- [VTCompressionSession](https://developer.apple.com/documentation/videotoolbox/vtcompressionsession)
- [VTDecompressionSession](https://developer.apple.com/documentation/videotoolbox/vtdecompressionsession)
- Existing: `ArkavoRecorder/Sources/ArkavoRecorder/VideoEncoder.swift` (uses AVAssetWriter)

## Next Steps

1. ✅ Document current JPEG approach (DONE)
2. ✅ Design VideoStreamEncoder API (DONE)
3. ✅ Remove legacy JPEG constants (DONE)
4. ⏳ Implement VideoStreamEncoder with VTCompressionSession
5. ⏳ Implement VideoStreamDecoder with VTDecompressionSession
6. ⏳ Update RemoteCameraMessage protocol (add videoNALU, remove frame)
7. ⏳ Replace JPEG encoding in RemoteCameraStreamer
8. ⏳ Update RemoteCameraServer to decode H.264
9. ⏳ Performance testing and validation
10. ⏳ Remove old JPEG code entirely
