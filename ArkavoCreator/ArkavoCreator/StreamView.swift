import SwiftUI
import ArkavoKit

struct StreamView: View {
    @State private var viewModel = StreamViewModel()
    @StateObject private var twitchClient = TwitchAuthClient(
        clientId: Secrets.twitchClientId,
        clientSecret: Secrets.twitchClientSecret
    )
    @StateObject private var webViewPresenter = WebViewPresenter()
    @ObservedObject private var previewStore = CameraPreviewStore.shared

    // Animation states
    @State private var pulsing: Bool = false
    @State private var showAdvancedSettings: Bool = false

    var body: some View {
        ZStack {
            // Ambient Background
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    if !viewModel.isStreaming {
                        quickStreamSetup
                    } else {
                        streamingStatusSection
                    }
                    
                    // Main Preview Area
                    CameraPreviewPanel(
                        title: "Stream Preview",
                        image: previewStore.image(for: viewModel.previewSourceID),
                        sourceLabel: viewModel.previewSourceID,
                        placeholderText: "Start your camera to see preview"
                    )
                    
                    if let error = viewModel.error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .navigationTitle("Stream")
        .onAppear { viewModel.loadStreamKey() }
        .onChange(of: viewModel.selectedPlatform) { _, _ in viewModel.loadStreamKey() }
        .onChange(of: viewModel.streamKey) { _, newValue in
            if !newValue.isEmpty { viewModel.saveStreamKey() }
        }
        .onChange(of: viewModel.customRTMPURL) { _, newValue in
            if !newValue.isEmpty && viewModel.selectedPlatform == .custom { viewModel.saveStreamKey() }
        }
    }

    // MARK: - View Components

    private var quickStreamSetup: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Ready to Stream?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("Broadcast to your audience in seconds.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            // Main Glass Card
            VStack(spacing: 24) {
                // Title Input
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stream Title", systemImage: "pencil.line")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    TextField("What are you streaming today?", text: $viewModel.title)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding()
                        .background(.background.opacity(0.5))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
                }
                
                // Platform Selector
                VStack(alignment: .leading, spacing: 12) {
                    Label("Destination", systemImage: "network")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(StreamViewModel.StreamPlatform.allCases) { platform in
                            PlatformButton(
                                platform: platform,
                                isSelected: viewModel.selectedPlatform == platform,
                                action: { viewModel.selectedPlatform = platform }
                            )
                        }
                    }
                }
                
                Divider().overlay(.white.opacity(0.2))
                
                // Action Button
                Button(action: {
                    Task { await viewModel.startStreaming() }
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Go Live Now")
                    }
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStartStreaming)
                
                // Advanced Settings Toggle
                Button(action: { withAnimation { showAdvancedSettings.toggle() } }) {
                    HStack {
                        Text("Advanced Settings")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showAdvancedSettings ? 180 : 0))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                if showAdvancedSettings {
                    advancedSettingsContent
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .frame(maxWidth: 600)
    }

    private var advancedSettingsContent: some View {
        VStack(spacing: 16) {
            if viewModel.selectedPlatform == .twitch {
                twitchAuthSection
            }
            
            if viewModel.selectedPlatform == .custom {
                VStack(alignment: .leading) {
                    Text("RTMP URL").font(.caption).foregroundStyle(.secondary)
                    TextField("rtmp://...", text: $viewModel.customRTMPURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            VStack(alignment: .leading) {
                HStack {
                    Text("Stream Key").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Help") { openStreamKeyHelp() }.buttonStyle(.link).font(.caption)
                }
                SecureField("Enter key", text: $viewModel.streamKey)
                    .textFieldStyle(.roundedBorder)
            }
            
            if viewModel.selectedPlatform == .twitch {
                Toggle("Bandwidth Test Mode", isOn: $viewModel.isBandwidthTest)
                    .toggleStyle(.switch)
            }
        }
        .padding(.top, 8)
    }
    
    private var twitchAuthSection: some View {
        Group {
            if twitchClient.isAuthenticated, let username = twitchClient.username {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(username).bold()
                    Spacer()
                    Button("Logout") { twitchClient.logout() }.controlSize(.small)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button("Login with Twitch") {
                    webViewPresenter.present(
                        url: twitchClient.authorizationURL,
                        handleCallback: { url in
                            Task {
                                try? await twitchClient.handleCallback(url)
                                webViewPresenter.dismiss()
                            }
                        }
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var streamingStatusSection: some View {
        VStack(spacing: 24) {
            // Live Status Card
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .opacity(pulsing ? 1.0 : 0.3)
                        Text("LIVE")
                            .font(.title2.bold())
                            .foregroundStyle(.red)
                    }
                    
                    Text(viewModel.title.isEmpty ? "Untitled Stream" : viewModel.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task { await viewModel.stopStreaming() }
                }) {
                    Text("End Stream")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .red.opacity(0.1), radius: 20, x: 0, y: 10)

            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StreamStatCard(label: "Duration", value: viewModel.formattedDuration, icon: "clock.fill")
                StreamStatCard(label: "Bitrate", value: viewModel.formattedBitrate, icon: "waveform.path")
                StreamStatCard(label: "FPS", value: String(format: "%.1f", viewModel.fps), icon: "speedometer")
                StreamStatCard(label: "Frames", value: "\(viewModel.framesSent)", icon: "film")
                StreamStatCard(label: "Data", value: formatBytes(viewModel.bytesSent), icon: "arrow.up.circle.fill")
            }
        }
        .frame(maxWidth: 800)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func openStreamKeyHelp() {
        let urlString: String
        switch viewModel.selectedPlatform {
        case .twitch: urlString = "https://dashboard.twitch.tv/settings/stream"
        case .youtube: urlString = "https://studio.youtube.com/channel/UC/livestreaming/stream"
        case .custom: return
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}

struct PlatformButton: View {
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
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .background(.regularMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StreamStatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
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
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        StreamView()
    }
}
