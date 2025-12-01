import SwiftUI
import ArkavoKit
import ArkavoStreaming

/// A sheet that allows users to quickly select a streaming destination and go live
struct StreamDestinationPicker: View {
    @Bindable var streamViewModel: StreamViewModel
    @ObservedObject var youtubeClient: YouTubeClient
    var onStartStream: (RTMPPublisher.Destination, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false

    var body: some View {
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
                    ForEach(StreamViewModel.StreamPlatform.allCases) { platform in
                        PlatformCard(
                            platform: platform,
                            isSelected: streamViewModel.selectedPlatform == platform,
                            action: {
                                streamViewModel.selectedPlatform = platform
                                streamViewModel.loadStreamKey()
                            }
                        )
                    }
                }
            }

            // Stream Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Stream Key")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack {
                    SecureField("Enter your stream key", text: $streamViewModel.streamKey)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.background.opacity(0.5))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )

                    if streamViewModel.selectedPlatform == .youtube {
                        Button {
                            Task {
                                if youtubeClient.isAuthenticated {
                                    await fetchYouTubeStreamKey()
                                } else {
                                    // Need to authenticate first
                                    print("[StreamDestinationPicker] YouTube not authenticated, starting auth flow...")
                                    do {
                                        try await youtubeClient.authenticateWithLocalServer()
                                        // After auth, fetch the stream key
                                        await fetchYouTubeStreamKey()
                                    } catch {
                                        await MainActor.run {
                                            streamViewModel.error = "YouTube login failed: \(error.localizedDescription)"
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: youtubeClient.isAuthenticated ? "arrow.clockwise" : "person.crop.circle.badge.plus")
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(youtubeClient.isAuthenticated ? "Fetch stream key from YouTube" : "Login to YouTube to fetch stream key")
                    }
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

            // Go Live Button
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
        .padding(24)
        .frame(width: 400, height: 450)
        .background(.ultraThinMaterial)
    }

    private var canStartStream: Bool {
        !streamViewModel.streamKey.isEmpty &&
        (streamViewModel.selectedPlatform != .custom || !streamViewModel.customRTMPURL.isEmpty)
    }

    private func startStream() async {
        isLoading = true
        defer { isLoading = false }

        // Save the stream key
        streamViewModel.saveStreamKey()

        // Create destination
        let destination = RTMPPublisher.Destination(
            url: streamViewModel.effectiveRTMPURL,
            platform: streamViewModel.selectedPlatform.rawValue.lowercased()
        )

        // Start streaming
        await onStartStream(destination, streamViewModel.streamKey)

        // Dismiss if successful
        if streamViewModel.error == nil {
            dismiss()
        }
    }

    private func fetchYouTubeStreamKey() async {
        do {
            if let key = try await youtubeClient.fetchStreamKey() {
                print("[StreamDestinationPicker] Fetched YouTube stream key: \(key.prefix(8))...")
                await MainActor.run {
                    streamViewModel.streamKey = key
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

// MARK: - Preview
#Preview {
    StreamDestinationPicker(
        streamViewModel: StreamViewModel(),
        youtubeClient: YouTubeClient(clientId: "", clientSecret: ""),
        onStartStream: { _, _ in }
    )
}

/// A selectable card for each streaming platform
private struct PlatformCard: View {
    let platform: StreamViewModel.StreamPlatform
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: platform.icon)
                    .font(.title2)
                Text(platform.rawValue)
                    .font(.caption)
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
        }
        .buttonStyle(.plain)
    }
}
