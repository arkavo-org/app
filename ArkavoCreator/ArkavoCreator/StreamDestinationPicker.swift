import SwiftUI
import ArkavoKit
import ArkavoStreaming

/// A sheet that allows users to quickly select a streaming destination and go live.
/// For Twitch (authenticated), shows a two-step flow: destination + stream info editing.
struct StreamDestinationPicker: View {
    @Bindable var streamViewModel: StreamViewModel
    @ObservedObject var youtubeClient: YouTubeClient
    @ObservedObject var twitchClient: TwitchAuthClient
    var onStartStream: (RTMPPublisher.Destination, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var showStreamInfo = false

    private var arkavoAuthState: ArkavoAuthState { ArkavoAuthState.shared }

    /// Whether the stream info step is available
    private var hasStreamInfoStep: Bool {
        (streamViewModel.selectedPlatform == .twitch && twitchClient.isAuthenticated) ||
        (streamViewModel.selectedPlatform == .youtube && youtubeClient.isAuthenticated)
    }

    var body: some View {
        Group {
            if showStreamInfo {
                StreamInfoFormView(
                    platform: streamViewModel.selectedPlatform,
                    twitchClient: twitchClient,
                    youtubeClient: youtubeClient,
                    onBack: { showStreamInfo = false },
                    onStartStream: {
                        await startStream()
                    }
                )
                .padding(24)
                .frame(width: 480, height: 620)
                .background(.ultraThinMaterial)
            } else {
                destinationStep
            }
        }
    }

    // MARK: - Step 1: Destination Selection

    private var destinationStep: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Go Live")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Platform Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Destination")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(StreamViewModel.StreamPlatform.allCases.filter {
                        ($0 != .arkavo || FeatureFlags.arkavoStreaming) &&
                        ($0 != .youtube || FeatureFlags.youtube)
                    }) { platform in
                        PlatformCard(
                            platform: platform,
                            isSelected: streamViewModel.selectedPlatforms.contains(platform),
                            action: {
                                // Toggle multi-select
                                if streamViewModel.selectedPlatforms.contains(platform) {
                                    // Don't allow deselecting the last platform
                                    if streamViewModel.selectedPlatforms.count > 1 {
                                        streamViewModel.selectedPlatforms.remove(platform)
                                    }
                                } else {
                                    streamViewModel.selectedPlatforms.insert(platform)
                                }
                                streamViewModel.loadStreamKey()
                            }
                        )
                    }
                }

                if streamViewModel.selectedPlatforms.count > 1 {
                    Text("Simulcast: \(streamViewModel.estimatedTotalBitrate) estimated upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Stream Key / Auth Section — per selected platform
            ForEach(Array(streamViewModel.selectedPlatforms).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { platform in
                if platform == .twitch && !twitchClient.isAuthenticated {
                    twitchConnectSection
                } else if platform == .youtube && !youtubeClient.isAuthenticated {
                    youtubeConnectSection
                } else if platform.requiresStreamKey {
                    streamKeySection(for: platform)
                }
            }

            // Custom RTMP URL (if custom platform)
            if streamViewModel.selectedPlatform == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RTMP URL")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    TextField("rtmp://your-server.com/live", text: $streamViewModel.customRTMPURL)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.background.opacity(0.5))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            // Error message
            if let error = streamViewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Spacer()

            // Action Button: "Next" for Twitch (to stream info), "Start Streaming" for others
            if hasStreamInfoStep {
                Button {
                    showStreamInfo = true
                } label: {
                    HStack {
                        Text("Next: Edit Stream Info")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        canStartStream
                            ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(!canStartStream)
            } else {
                Button {
                    Task { await startStream() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("Start Streaming")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        canStartStream
                            ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(!canStartStream || isLoading)
            }
        }
        .padding(24)
        .frame(width: 400, height: 450)
        .background(.ultraThinMaterial)
    }

    // MARK: - Twitch Connect (unauthenticated)

    private var twitchConnectSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Connect your Twitch account to go live")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    do {
                        try await twitchClient.authenticateWithSystemBrowser()
                        await fetchTwitchStreamKey()
                    } catch {
                        debugLog("Twitch OAuth error: \(error)")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Connect to Twitch")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    // MARK: - YouTube Connect (unauthenticated)

    private var youtubeConnectSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Connect your YouTube account to go live")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    do {
                        try await youtubeClient.authenticateWithLocalServer()
                    } catch {
                        debugLog("YouTube OAuth error: \(error)")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Connect to YouTube")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Stream Key Input (per platform)

    private func streamKeySection(for platform: StreamViewModel.StreamPlatform) -> some View {
        let keyBinding = Binding<String>(
            get: { streamViewModel.platformConfigs[platform]?.streamKey ?? "" },
            set: { streamViewModel.platformConfigs[platform, default: StreamViewModel.PlatformConfig()].streamKey = $0 }
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(platform.rawValue) Stream Key")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack {
                SecureField("Enter your stream key", text: keyBinding)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(.background.opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )

                if platform == .twitch && twitchClient.isAuthenticated {
                    Button {
                        Task { await fetchTwitchStreamKey() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Fetch stream key from Twitch")
                }

                if platform == .youtube && youtubeClient.isAuthenticated {
                    Button {
                        Task { await fetchYouTubeStreamKey() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Fetch stream key from YouTube")
                }
            }

            if platform == .twitch && keyBinding.wrappedValue.isEmpty {
                if let username = twitchClient.username {
                    Link(destination: URL(string: "https://dashboard.twitch.tv/u/\(username.lowercased())/settings/stream") ?? URL(string: "https://dashboard.twitch.tv")!) {
                        Label("Copy stream key from Twitch Dashboard", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var canStartStream: Bool {
        // Check all selected platforms have what they need
        for platform in streamViewModel.selectedPlatforms {
            if platform == .twitch && !twitchClient.isAuthenticated { return false }
            if platform.requiresStreamKey {
                let key = streamViewModel.platformConfigs[platform]?.streamKey ?? ""
                if key.isEmpty { return false }
            }
            if platform == .custom && streamViewModel.customRTMPURL.isEmpty { return false }
        }
        return !streamViewModel.selectedPlatforms.isEmpty
    }

    private func startStream() async {
        isLoading = true
        defer { isLoading = false }

        streamViewModel.saveStreamKey()

        // Build destination for primary platform (RecordView handles multi-destination)
        let primary = streamViewModel.selectedPlatform
        let destination = RTMPPublisher.Destination(
            url: primary == .custom ? streamViewModel.customRTMPURL : primary.rtmpURL,
            platform: primary.rawValue.lowercased()
        )
        let key = streamViewModel.platformConfigs[primary]?.streamKey ?? ""

        await onStartStream(destination, key)

        if streamViewModel.error == nil {
            dismiss()
        }
    }

    private func fetchTwitchStreamKey() async {
        do {
            if let key = try await twitchClient.fetchStreamKey() {
                debugLog("[StreamDestinationPicker] Fetched Twitch stream key")
                streamViewModel.platformConfigs[.twitch, default: StreamViewModel.PlatformConfig()].streamKey = key
                streamViewModel.saveStreamKey()
            } else {
                streamViewModel.error = "Could not fetch stream key — copy it from the Twitch Dashboard"
            }
        } catch {
            streamViewModel.error = "Could not fetch Twitch stream key: \(error.localizedDescription)"
        }
    }

    private func fetchYouTubeStreamKey() async {
        do {
            if let key = try await youtubeClient.fetchStreamKey() {
                debugLog("[StreamDestinationPicker] Fetched YouTube stream key")
                await MainActor.run {
                    streamViewModel.platformConfigs[.youtube, default: StreamViewModel.PlatformConfig()].streamKey = key
                    streamViewModel.saveStreamKey()
                }
            }
        } catch {
            await MainActor.run {
                streamViewModel.error = "Could not fetch YouTube stream key: \(error.localizedDescription)"
            }
        }
    }
}

/// A selectable card for each streaming platform
private struct PlatformCard: View {
    let platform: StreamViewModel.StreamPlatform
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: platform.icon)
                    .font(.title2)
                Text(platform.rawValue)
                    .font(.caption)
                if isDisabled {
                    Text("Login required")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
