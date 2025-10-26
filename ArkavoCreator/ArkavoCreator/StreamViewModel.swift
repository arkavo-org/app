import SwiftUI
import ArkavoRecorder
import ArkavoStreaming
import ArkavoSocial

@Observable
@MainActor
final class StreamViewModel {

    // MARK: - Stream Configuration

    enum StreamPlatform: String, CaseIterable, Identifiable {
        case twitch = "Twitch"
        case youtube = "YouTube"
        case custom = "Custom RTMP"

        var id: String { rawValue }

        var rtmpURL: String {
            switch self {
            case .twitch:
                return "rtmp://live.twitch.tv/app"
            case .youtube:
                return "rtmp://a.rtmp.youtube.com/live2"
            case .custom:
                return ""
            }
        }

        var requiresStreamKey: Bool {
            true
        }

        var icon: String {
            switch self {
            case .twitch:
                return "tv"
            case .youtube:
                return "play.rectangle"
            case .custom:
                return "server.rack"
            }
        }
    }

    // MARK: - State

    var selectedPlatform: StreamPlatform = .twitch
    var customRTMPURL: String = ""
    var streamKey: String = ""
    var title: String = ""

    var isStreaming: Bool = false
    var isConnecting: Bool = false
    var error: String?

    // Stream statistics
    var bitrate: Double = 0
    var fps: Double = 0
    var framesSent: UInt64 = 0
    var bytesSent: UInt64 = 0
    var duration: TimeInterval = 0

    // MARK: - Dependencies

    private var statisticsTimer: Timer?
    var twitchClient: TwitchAuthClient?
    private var recordingState = RecordingState.shared

    // MARK: - Computed Properties

    var canStartStreaming: Bool {
        !streamKey.isEmpty && !isStreaming && !isConnecting &&
        (selectedPlatform != .custom || !customRTMPURL.isEmpty)
    }

    var effectiveRTMPURL: String {
        selectedPlatform == .custom ? customRTMPURL : selectedPlatform.rtmpURL
    }

    var formattedBitrate: String {
        if bitrate < 1000 {
            return String(format: "%.0f bps", bitrate)
        } else if bitrate < 1_000_000 {
            return String(format: "%.1f Kbps", bitrate / 1000)
        } else {
            return String(format: "%.2f Mbps", bitrate / 1_000_000)
        }
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Actions

    func startStreaming() async {
        guard canStartStreaming else { return }
        guard let session = recordingState.getRecordingSession() else {
            error = "No active recording session. Please start recording first."
            return
        }

        error = nil
        isConnecting = true

        do {
            // Create RTMP destination
            let destination = RTMPPublisher.Destination(
                url: effectiveRTMPURL,
                platform: selectedPlatform.rawValue.lowercased()
            )

            // Connect and start streaming
            try await session.startStreaming(to: destination, streamKey: streamKey)

            isStreaming = true
            isConnecting = false

            // Start statistics polling
            startStatisticsTimer()

        } catch {
            self.error = error.localizedDescription
            isConnecting = false
            isStreaming = false
        }
    }

    func stopStreaming() async {
        guard let session = recordingState.getRecordingSession(), isStreaming else { return }

        await session.stopStreaming()

        isStreaming = false
        isConnecting = false

        // Stop statistics polling
        stopStatisticsTimer()

        // Reset statistics
        bitrate = 0
        fps = 0
        framesSent = 0
        bytesSent = 0
        duration = 0
    }

    // MARK: - Private Methods

    private func startStatisticsTimer() {
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateStatistics()
            }
        }
    }

    private func stopStatisticsTimer() {
        statisticsTimer?.invalidate()
        statisticsTimer = nil
    }

    @MainActor
    private func updateStatistics() async {
        guard let session = recordingState.getRecordingSession(),
              let stats = await session.streamStatistics else {
            return
        }

        bitrate = stats.bitrate
        framesSent = stats.framesSent
        bytesSent = stats.bytesSent
        duration = stats.duration

        // Calculate FPS from frames sent over duration
        if duration > 0 {
            fps = Double(framesSent) / duration
        }
    }

    // MARK: - Stream Key Management

    func loadStreamKey() {
        // Load stream key from Keychain
        if let savedKey = KeychainManager.getStreamKey(for: selectedPlatform.rawValue) {
            streamKey = savedKey
        }

        // Load custom RTMP URL if custom platform
        if selectedPlatform == .custom {
            if let savedURL = KeychainManager.getCustomRTMPURL() {
                customRTMPURL = savedURL
            }
        }
    }

    func saveStreamKey() {
        // Save stream key to Keychain
        if !streamKey.isEmpty {
            try? KeychainManager.saveStreamKey(streamKey, for: selectedPlatform.rawValue)
        }

        // Save custom RTMP URL if custom platform
        if selectedPlatform == .custom && !customRTMPURL.isEmpty {
            try? KeychainManager.saveCustomRTMPURL(customRTMPURL)
        }
    }

    func clearStreamKey() {
        KeychainManager.deleteStreamKey(for: selectedPlatform.rawValue)
        streamKey = ""

        if selectedPlatform == .custom {
            KeychainManager.deleteCustomRTMPURL()
            customRTMPURL = ""
        }
    }
}
