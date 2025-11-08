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

        // Validate inputs before streaming
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

    // MARK: - Input Validation

    /// Validates stream key, RTMP URL, and title
    /// - Returns: Error message if validation fails, nil if all inputs are valid
    private func validateInputs() -> String? {
        // Validate stream key
        if let error = validateStreamKey(streamKey) {
            return error
        }

        // Validate custom RTMP URL if custom platform
        if selectedPlatform == .custom {
            if let error = validateRTMPURL(customRTMPURL) {
                return error
            }
        }

        // Validate stream title
        if let error = validateTitle(title) {
            return error
        }

        return nil
    }

    /// Validates stream key format and length
    private func validateStreamKey(_ key: String) -> String? {
        // Check if empty
        if key.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Stream key cannot be empty"
        }

        // Check minimum length (most platforms require at least 10 characters)
        if key.count < 10 {
            return "Stream key is too short (minimum 10 characters)"
        }

        // Check maximum length (reasonable limit for stream keys)
        if key.count > 200 {
            return "Stream key is too long (maximum 200 characters)"
        }

        // Check for valid characters (alphanumeric, hyphens, underscores)
        let validCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        if key.rangeOfCharacter(from: validCharacterSet.inverted) != nil {
            return "Stream key contains invalid characters (only letters, numbers, hyphens, and underscores allowed)"
        }

        return nil
    }

    /// Validates RTMP URL format and protocol
    private func validateRTMPURL(_ urlString: String) -> String? {
        // Check if empty
        if urlString.trimmingCharacters(in: .whitespaces).isEmpty {
            return "RTMP URL cannot be empty"
        }

        // Check if valid URL
        guard let url = URL(string: urlString) else {
            return "Invalid RTMP URL format"
        }

        // Check protocol
        guard let scheme = url.scheme?.lowercased() else {
            return "RTMP URL must specify a protocol (rtmp:// or rtmps://)"
        }

        guard scheme == "rtmp" || scheme == "rtmps" else {
            return "RTMP URL must use rtmp:// or rtmps:// protocol"
        }

        // Check host
        guard let host = url.host, !host.isEmpty else {
            return "RTMP URL must include a valid host"
        }

        // Check overall length
        if urlString.count > 500 {
            return "RTMP URL is too long (maximum 500 characters)"
        }

        return nil
    }

    /// Validates stream title length and characters
    private func validateTitle(_ title: String) -> String? {
        // Allow empty title (optional field)
        if title.isEmpty {
            return nil
        }

        // Check maximum length
        if title.count > 200 {
            return "Stream title is too long (maximum 200 characters)"
        }

        // Check for control characters
        if title.rangeOfCharacter(from: .controlCharacters) != nil {
            return "Stream title contains invalid control characters"
        }

        return nil
    }
}
