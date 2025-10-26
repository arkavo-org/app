import SwiftUI
import ArkavoRecorder

struct StreamView: View {
    @State private var viewModel = StreamViewModel()
    @StateObject private var twitchClient = TwitchAuthClient(clientId: Secrets.twitchClientId)
    @StateObject private var webViewPresenter = WebViewPresenter()

    var body: some View {
        VStack(spacing: 24) {
            if !viewModel.isStreaming {
                setupSection
            } else {
                streamingStatusSection
            }

            Spacer()

            controlButton

            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if viewModel.isConnecting {
                ProgressView("Connecting to stream...")
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle("Stream")
        .onAppear {
            viewModel.loadStreamKey()
        }
        .onChange(of: viewModel.selectedPlatform) { _, _ in
            viewModel.loadStreamKey()
        }
        .onChange(of: viewModel.streamKey) { _, newValue in
            if !newValue.isEmpty {
                viewModel.saveStreamKey()
            }
        }
        .onChange(of: viewModel.customRTMPURL) { _, newValue in
            if !newValue.isEmpty && viewModel.selectedPlatform == .custom {
                viewModel.saveStreamKey()
            }
        }
    }

    // MARK: - View Components

    private var setupSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Live Streaming")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Stream to Twitch, YouTube, or custom RTMP server")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                // Platform selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platform")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Platform", selection: $viewModel.selectedPlatform) {
                        ForEach(StreamViewModel.StreamPlatform.allCases) { platform in
                            Label(platform.rawValue, systemImage: platform.icon)
                                .tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Twitch OAuth Login
                if viewModel.selectedPlatform == .twitch {
                    if twitchClient.isAuthenticated, let username = twitchClient.username {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Logged in as \(username)")
                                .font(.subheadline)
                            Spacer()
                            Button("Logout") {
                                twitchClient.logout()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Button(action: {
                            webViewPresenter.present(
                                url: twitchClient.authorizationURL,
                                handleCallback: { url in
                                    Task {
                                        do {
                                            try await twitchClient.handleCallback(url)
                                            webViewPresenter.dismiss()
                                        } catch {
                                            print("Twitch OAuth error: \(error)")
                                        }
                                    }
                                }
                            )
                        }) {
                            Label("Login with Twitch", systemImage: "person.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Custom RTMP URL (only for custom platform)
                if viewModel.selectedPlatform == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RTMP Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("rtmp://your-server.com/live", text: $viewModel.customRTMPURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Stream key
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Stream Key")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            openStreamKeyHelp()
                        }) {
                            Label("Where to find", systemImage: "questionmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        SecureField("Enter your stream key", text: $viewModel.streamKey)
                            .textFieldStyle(.roundedBorder)

                        if !viewModel.streamKey.isEmpty {
                            Button(action: {
                                viewModel.clearStreamKey()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear saved stream key")
                        }
                    }

                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)

                        Text("Never share your stream key. It's securely stored in your Keychain.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                // Stream title (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stream Title (Optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Going live!", text: $viewModel.title)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(maxWidth: 400)
        }
    }

    private var streamingStatusSection: some View {
        VStack(spacing: 24) {
            // Live indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(pulsing ? 1.0 : 0.3)

                Text("LIVE")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }

            // Stream info
            if !viewModel.title.isEmpty {
                Text(viewModel.title)
                    .font(.headline)
            }

            Text(viewModel.selectedPlatform.rawValue)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Statistics
            VStack(spacing: 16) {
                HStack(spacing: 32) {
                    StreamStatCard(
                        label: "Duration",
                        value: viewModel.formattedDuration,
                        icon: "clock.fill"
                    )

                    StreamStatCard(
                        label: "Bitrate",
                        value: viewModel.formattedBitrate,
                        icon: "waveform.path"
                    )

                    StreamStatCard(
                        label: "FPS",
                        value: String(format: "%.1f", viewModel.fps),
                        icon: "speedometer"
                    )
                }

                HStack(spacing: 32) {
                    StreamStatCard(
                        label: "Frames Sent",
                        value: "\(viewModel.framesSent)",
                        icon: "film"
                    )

                    StreamStatCard(
                        label: "Data Sent",
                        value: formatBytes(viewModel.bytesSent),
                        icon: "arrow.up.circle.fill"
                    )
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var controlButton: some View {
        Button(action: {
            Task {
                if viewModel.isStreaming {
                    await viewModel.stopStreaming()
                } else {
                    await viewModel.startStreaming()
                }
            }
        }) {
            HStack {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                Text(viewModel.isStreaming ? "Stop Stream" : "Start Stream")
                    .font(.headline)
            }
            .frame(maxWidth: 300)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isStreaming ? .red : .blue)
        .disabled(!viewModel.canStartStreaming && !viewModel.isStreaming)
    }

    // MARK: - Animation State

    @State private var pulsing: Bool = false

    private var pulsingAnimation: some View {
        Color.clear
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }

    // MARK: - Helper Functions

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func openStreamKeyHelp() {
        let urlString: String
        switch viewModel.selectedPlatform {
        case .twitch:
            urlString = "https://dashboard.twitch.tv/settings/stream"
        case .youtube:
            urlString = "https://studio.youtube.com/channel/UC/livestreaming/stream"
        case .custom:
            return // No help URL for custom
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Stream Stat Card Component

struct StreamStatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 100)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StreamView()
    }
}
