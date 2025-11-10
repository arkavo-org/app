import Foundation

/// Shared constants for remote camera functionality
public enum RemoteCameraConstants {
    // MARK: - Network Discovery

    /// Bonjour service type for remote camera discovery
    public static let serviceType = "_arkavo-remote._tcp."

    /// Default port for remote camera server
    public static let defaultPort: UInt16 = 5757

    /// Maximum receive buffer size (1 MB)
    public static let maxReceiveBufferSize = 1_048_576

    // MARK: - Timeouts & Intervals

    /// Discovery timeout in seconds (10 seconds)
    public static let discoveryTimeout: TimeInterval = 10.0

    /// Service resolution timeout in seconds (5 seconds)
    public static let serviceResolutionTimeout: TimeInterval = 5.0

    /// Discovery polling interval in nanoseconds (0.5 seconds)
    public static let discoveryPollingInterval: UInt64 = 500_000_000

    /// Auto mode switch delay in nanoseconds (0.5 seconds)
    public static let modeDetectionNoDetectionThreshold = 60

    /// Auto mode switch delay in nanoseconds (0.5 seconds)
    public static let modeDetectionFrameThreshold: Int = 60

    /// Logging interval for no detection (frames)
    public static let noDetectionLoggingInterval: Int = 30

    // MARK: - Video Encoding

    /// Feature flag: Use H.264 video encoding instead of JPEG frames
    /// TODO: Implement VideoStreamEncoder using VideoToolbox
    public static let useVideoEncoding: Bool = false  // Currently JPEG, will migrate to H.264

    /// Target frame rate for remote camera streaming
    /// - JPEG mode: 15 FPS (throttled for bandwidth)
    /// - H.264 mode: 30 FPS (full ARKit rate)
    public static let targetFrameRate: Double = 15.0

    /// Frame interval for throttling (1/15 seconds ≈ 66ms)
    public static let frameInterval: CFTimeInterval = 1.0 / targetFrameRate

    // MARK: - JPEG Encoding (Legacy - to be replaced by H.264)

    /// JPEG compression quality (0.0 - 1.0)
    /// NOTE: This is inefficient. See docs/video-streaming-proposal.md for H.264 migration plan
    public static let jpegCompressionQuality: Double = 0.6

    // MARK: - H.264 Video Streaming (Future)

    /// H.264 video bitrate (3 Mbps default)
    /// Much more efficient than JPEG: 250-625 KB/s vs 750KB-3MB/s
    public static let h264Bitrate: Int = 3_000_000

    /// H.264 keyframe interval (I-frame every 2 seconds at 30 FPS)
    public static let h264KeyFrameInterval: Int = 60

    // MARK: - Common

    /// Video timescale for CMTime (600 units per second)
    public static let videoTimescale: CMTimeScale = 600
}
