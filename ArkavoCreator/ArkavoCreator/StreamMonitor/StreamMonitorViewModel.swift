import AppKit
import CoreGraphics
import CoreMedia
import Foundation

/// Statistics about the stream output.
struct StreamStatistics {
    var duration: TimeInterval = 0
    var fps: Double = 0
    var bitrate: Double = 0 // bits per second
    var droppedFrames: Int = 0
    var framesSent: Int = 0

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedBitrate: String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else if bitrate >= 1000 {
            return String(format: "%.0f kbps", bitrate / 1000)
        }
        return String(format: "%.0f bps", bitrate)
    }
}

/// View model for the stream monitor window.
/// Receives composed frames from RecordingSession and exposes them for display.
@MainActor
final class StreamMonitorViewModel: ObservableObject {
    static let shared = StreamMonitorViewModel()

    @Published private(set) var latestFrameImage: NSImage?
    @Published private(set) var streamStats: StreamStatistics?
    @Published private(set) var isLive: Bool = false

    // Frame rate tracking
    private var frameCount: Int = 0
    private var lastFPSUpdate: Date = .init()
    private var lastFPS: Double = 0

    // Duration tracking
    private var startTime: Date?

    private init() {}

    /// Receives a composed frame from the compositor.
    /// Called by RecordingSession after composition, before encoding.
    /// Frame is pre-converted to CGImage to avoid Sendable issues.
    func receiveFrame(_ cgImage: CGImage, width: Int, height: Int, timestamp _: CMTime) {
        // Create NSImage from CGImage
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        latestFrameImage = nsImage

        // Update FPS tracking
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)

        if elapsed >= 1.0 {
            lastFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSUpdate = now

            // Update stats
            updateStats()
        }
    }

    /// Starts tracking stream statistics.
    func startMonitoring() {
        startTime = Date()
        frameCount = 0
        lastFPSUpdate = Date()
        lastFPS = 0
        streamStats = StreamStatistics()
    }

    /// Stops monitoring and clears state.
    func stopMonitoring() {
        startTime = nil
        streamStats = nil
        latestFrameImage = nil
        isLive = false
        StreamMonitorWindow.shared.updateTitle(isLive: false)
    }

    /// Updates the live streaming state.
    func setLive(_ live: Bool, bitrate: Double = 0, droppedFrames: Int = 0, framesSent: Int = 0) {
        isLive = live
        StreamMonitorWindow.shared.updateTitle(isLive: live)

        if var stats = streamStats {
            stats.bitrate = bitrate
            stats.droppedFrames = droppedFrames
            stats.framesSent = framesSent
            streamStats = stats
        }
    }

    private func updateStats() {
        guard var stats = streamStats else { return }

        stats.fps = lastFPS

        if let start = startTime {
            stats.duration = Date().timeIntervalSince(start)
        }

        streamStats = stats
    }
}
