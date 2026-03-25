import SwiftUI
import ArkavoKit
import ArkavoStreaming

@Observable
@MainActor
final class StreamViewModel {

    // MARK: - Stream Configuration

    enum StreamPlatform: String, CaseIterable, Identifiable, Hashable {
        case arkavo = "Arkavo"
        case twitch = "Twitch"
        case youtube = "YouTube"
        case custom = "Custom RTMP"

        var id: String { rawValue }

        var rtmpURL: String {
            switch self {
            case .arkavo: "rtmp://100.arkavo.net:1935"
            case .twitch: "rtmp://live.twitch.tv/app"
            case .youtube: "rtmp://a.rtmp.youtube.com/live2"
            case .custom: ""
            }
        }

        var requiresStreamKey: Bool {
            self != .arkavo
        }

        var icon: String {
            switch self {
            case .arkavo: "lock.shield"
            case .twitch: "tv"
            case .youtube: "play.rectangle"
            case .custom: "server.rack"
            }
        }

        var isEncrypted: Bool { self == .arkavo }
    }

    // MARK: - Per-Platform Config

    struct PlatformConfig {
        var streamKey: String = ""
        var broadcastId: String?
        var transitionTask: Task<Void, Never>?
        var error: String?
        var isLive: Bool = false
    }

    // MARK: - State

    var selectedPlatforms: Set<StreamPlatform> = [.twitch]
    var platformConfigs: [StreamPlatform: PlatformConfig] = [:]
    var customRTMPURL: String = ""
    var title: String = ""
    var isBandwidthTest: Bool = false

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
    var youtubeClient: YouTubeClient?
    private var recordingState = RecordingState.shared

    // MARK: - Backward Compatibility

    /// Primary platform (first selected, for single-platform code paths)
    var selectedPlatform: StreamPlatform {
        get { selectedPlatforms.first ?? .twitch }
        set {
            selectedPlatforms = [newValue]
        }
    }

    /// Stream key for the primary platform
    var streamKey: String {
        get { platformConfigs[selectedPlatform]?.streamKey ?? "" }
        set { platformConfigs[selectedPlatform, default: PlatformConfig()].streamKey = newValue }
    }

    /// YouTube broadcast ID (from primary or YouTube-specific config)
    var youtubeBroadcastId: String? {
        get { platformConfigs[.youtube]?.broadcastId }
        set { platformConfigs[.youtube, default: PlatformConfig()].broadcastId = newValue }
    }

    var youtubeTransitionTask: Task<Void, Never>? {
        get { platformConfigs[.youtube]?.transitionTask }
        set { platformConfigs[.youtube, default: PlatformConfig()].transitionTask = newValue }
    }

    // MARK: - Computed Properties

    var canStartStreaming: Bool {
        guard !isStreaming, !isConnecting else { return false }
        // All selected platforms must have valid keys (or not require one)
        for platform in selectedPlatforms {
            if platform.requiresStreamKey {
                let key = platformConfigs[platform]?.streamKey ?? ""
                if key.isEmpty { return false }
            }
            if platform == .custom && customRTMPURL.isEmpty { return false }
        }
        return !selectedPlatforms.isEmpty
    }

    var effectiveRTMPURL: String {
        selectedPlatform == .custom ? customRTMPURL : selectedPlatform.rtmpURL
    }

    /// Estimated total upload bitrate for all selected platforms
    var estimatedTotalBitrate: String {
        let perStream = Double(videoBitrate) + 128_000 // video + audio
        let total = perStream * Double(selectedPlatforms.count)
        if total < 1_000_000 {
            return String(format: "%.0f Kbps", total / 1000)
        }
        return String(format: "%.1f Mbps", total / 1_000_000)
    }

    private var videoBitrate: Int {
        // Match the auto-detected bitrate from VideoEncoder
        let cores = ProcessInfo.processInfo.activeProcessorCount
        if cores >= 8 { return 4_500_000 }
        if cores >= 4 { return 3_000_000 }
        return 1_500_000
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

    var previewSourceID: String? {
        recordingState.getRecordingSession()?.cameraSourceIdentifiers.first
    }

    // MARK: - Actions

    func startStreaming() async {
        guard canStartStreaming else { return }

        if let validationError = validateInputs() {
            error = validationError
            return
        }

        guard let session = recordingState.getRecordingSession() else {
            error = "No active recording session. Please start recording first."
            return
        }

        error = nil
        isConnecting = true

        do {
            // Handle Arkavo NTDF separately (not part of simulcast)
            if selectedPlatforms.contains(.arkavo) {
                guard let kasURL = URL(string: "https://100.arkavo.net") else {
                    self.error = "Invalid KAS URL"
                    isConnecting = false
                    return
                }
                try await session.startNTDFStreaming(
                    kasURL: kasURL,
                    rtmpURL: StreamPlatform.arkavo.rtmpURL,
                    streamKey: "live/creator"
                )
            }

            // Build RTMP destinations for non-Arkavo platforms
            let rtmpPlatforms = selectedPlatforms.filter { !$0.isEncrypted }
            if !rtmpPlatforms.isEmpty {
                // YouTube: create broadcast before RTMP
                if rtmpPlatforms.contains(.youtube), let ytClient = youtubeClient {
                    let broadcastId = try await ytClient.createAndBindBroadcast(title: title)
                    platformConfigs[.youtube, default: PlatformConfig()].broadcastId = broadcastId
                    debugLog("[StreamViewModel] Created YouTube broadcast: \(broadcastId)")
                }

                var destinations: [(id: String, destination: RTMPPublisher.Destination, streamKey: String)] = []
                for platform in rtmpPlatforms {
                    let config = platformConfigs[platform] ?? PlatformConfig()
                    let url = platform == .custom ? customRTMPURL : platform.rtmpURL
                    let dest = RTMPPublisher.Destination(url: url, platform: platform.rawValue.lowercased())
                    var key = config.streamKey
                    if platform == .twitch && isBandwidthTest {
                        key += "?bandwidthtest=true"
                    }
                    destinations.append((id: platform.rawValue.lowercased(), destination: dest, streamKey: key))
                }

                try await session.startStreaming(destinations: destinations)
            }

            isStreaming = true
            isConnecting = false
            startStatisticsTimer()

        } catch {
            self.error = error.localizedDescription
            isConnecting = false
            isStreaming = false
        }
    }

    func stopStreaming() async {
        guard let session = recordingState.getRecordingSession(), isStreaming else { return }

        // Cancel YouTube transition task and end broadcast
        platformConfigs[.youtube]?.transitionTask?.cancel()
        platformConfigs[.youtube]?.transitionTask = nil
        if let ytClient = youtubeClient, let broadcastId = platformConfigs[.youtube]?.broadcastId {
            try? await ytClient.endBroadcast(broadcastId: broadcastId)
            platformConfigs[.youtube]?.broadcastId = nil
            debugLog("[StreamViewModel] Ended YouTube broadcast")
        }

        await session.stopStreaming()

        isStreaming = false
        isConnecting = false
        stopStatisticsTimer()
        bitrate = 0
        fps = 0
        framesSent = 0
        bytesSent = 0
        duration = 0

        // Clear per-platform live state
        for platform in platformConfigs.keys {
            platformConfigs[platform]?.isLive = false
            platformConfigs[platform]?.error = nil
        }
    }

    func startStatisticsPolling() {
        startStatisticsTimer()
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

        if duration > 0 {
            fps = Double(framesSent) / duration
        }
    }

    // MARK: - Stream Key Management

    func loadStreamKey() {
        // Load keys for all selected platforms
        for platform in selectedPlatforms {
            var config = platformConfigs[platform] ?? PlatformConfig()
            config.streamKey = ""
            if let savedKey = KeychainManager.getStreamKey(for: platform.rawValue) {
                if !savedKey.hasPrefix("http://") && !savedKey.hasPrefix("https://") {
                    config.streamKey = savedKey
                    debugLog("[StreamViewModel] Loaded stream key for \(platform.rawValue)")
                } else {
                    KeychainManager.deleteStreamKey(for: platform.rawValue)
                }
            }
            platformConfigs[platform] = config
        }

        if selectedPlatforms.contains(.custom) {
            customRTMPURL = KeychainManager.getCustomRTMPURL() ?? ""
        }
    }

    func saveStreamKey() {
        for platform in selectedPlatforms {
            let key = platformConfigs[platform]?.streamKey ?? ""
            if !key.isEmpty && !key.hasPrefix("http://") && !key.hasPrefix("https://") {
                try? KeychainManager.saveStreamKey(key, for: platform.rawValue)
                debugLog("[StreamViewModel] Saved stream key for \(platform.rawValue)")
            }
        }

        if selectedPlatforms.contains(.custom) && !customRTMPURL.isEmpty {
            try? KeychainManager.saveCustomRTMPURL(customRTMPURL)
        }
    }

    func clearStreamKey() {
        for platform in selectedPlatforms {
            KeychainManager.deleteStreamKey(for: platform.rawValue)
            platformConfigs[platform]?.streamKey = ""
        }

        if selectedPlatforms.contains(.custom) {
            KeychainManager.deleteCustomRTMPURL()
            customRTMPURL = ""
        }
    }

    // MARK: - Input Validation

    private func validateInputs() -> String? {
        for platform in selectedPlatforms {
            if platform.requiresStreamKey {
                let key = platformConfigs[platform]?.streamKey ?? ""
                if let error = validateStreamKey(key, platform: platform) {
                    return "[\(platform.rawValue)] \(error)"
                }
            }
            if platform == .custom {
                if let error = validateRTMPURL(customRTMPURL) {
                    return error
                }
            }
        }

        if let error = validateTitle(title) {
            return error
        }
        return nil
    }

    private func validateStreamKey(_ key: String, platform: StreamPlatform) -> String? {
        if platform == .arkavo { return nil }
        if key.trimmingCharacters(in: .whitespaces).isEmpty { return "Stream key cannot be empty" }
        if key.count < 10 { return "Stream key is too short (minimum 10 characters)" }
        if key.count > 200 { return "Stream key is too long (maximum 200 characters)" }
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        if key.rangeOfCharacter(from: validChars.inverted) != nil {
            return "Stream key contains invalid characters"
        }
        return nil
    }

    private func validateRTMPURL(_ urlString: String) -> String? {
        if urlString.trimmingCharacters(in: .whitespaces).isEmpty { return "RTMP URL cannot be empty" }
        guard let url = URL(string: urlString) else { return "Invalid RTMP URL format" }
        guard let scheme = url.scheme?.lowercased(), scheme == "rtmp" || scheme == "rtmps" else {
            return "RTMP URL must use rtmp:// or rtmps://"
        }
        guard let host = url.host, !host.isEmpty else { return "RTMP URL must include a host" }
        if urlString.count > 500 { return "RTMP URL is too long" }
        return nil
    }

    private func validateTitle(_ title: String) -> String? {
        if title.isEmpty { return nil }
        if title.count > 200 { return "Stream title is too long (maximum 200 characters)" }
        if title.rangeOfCharacter(from: .controlCharacters) != nil { return "Stream title contains invalid characters" }
        return nil
    }
}
