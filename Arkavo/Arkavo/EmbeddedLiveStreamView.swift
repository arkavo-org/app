import ArkavoSocial
import AVFoundation
import SwiftUI

/// A live stream player view designed for embedding in the video feed
struct EmbeddedLiveStreamView: View {
    let stream: LiveStream
    let isActive: Bool
    let onStreamEnded: (() -> Void)?

    @StateObject private var viewModel = LiveStreamViewModel()
    @State private var showEndedOverlay = false

    init(stream: LiveStream, isActive: Bool, onStreamEnded: (() -> Void)? = nil) {
        self.stream = stream
        self.isActive = isActive
        self.onStreamEnded = onStreamEnded
    }

    /// Get the NTDF token from keychain for encrypted stream playback
    private var ntdfToken: String? {
        KeychainManager.getAuthenticationToken()
    }

    var body: some View {
        ZStack {
            Color.black

            // Video display layer
            if viewModel.isPlaying {
                LiveStreamDisplayView(viewModel: viewModel)
            }

            // Connecting state
            if viewModel.isConnecting {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Connecting to live stream...")
                        .font(.body)
                        .foregroundStyle(.white)
                }
            }

            // Error state
            if let error = viewModel.errorMessage, !showEndedOverlay {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        connectToStream()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }

            // Stream ended overlay
            if showEndedOverlay {
                StreamEndedOverlay(
                    streamTitle: stream.title,
                    onDismiss: {
                        showEndedOverlay = false
                        onStreamEnded?()
                    }
                )
            }

            // Stream info overlay (bottom)
            if viewModel.isPlaying {
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let metadata = viewModel.metadata {
                                HStack(spacing: 8) {
                                    if let width = metadata.width, let height = metadata.height {
                                        Text("\(width)x\(height)")
                                    }
                                    if let fps = metadata.framerate {
                                        Text("\(Int(fps)) fps")
                                    }
                                    if metadata.isEncrypted {
                                        HStack(spacing: 4) {
                                            Image(systemName: "lock.fill")
                                            Text("Encrypted")
                                        }
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        Spacer()
                        Text("\(viewModel.framesReceived) frames")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5))
                }
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                connectToStream()
            } else {
                disconnectFromStream()
            }
        }
        .onAppear {
            if isActive {
                connectToStream()
            }
        }
        .onDisappear {
            disconnectFromStream()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveStreamStopped)) { notification in
            if let stoppedKey = notification.userInfo?["streamKey"] as? String,
               stoppedKey == stream.streamKey
            {
                showEndedOverlay = true
            }
        }
    }

    private func connectToStream() {
        showEndedOverlay = false
        Task {
            await viewModel.connect(url: stream.rtmpURL, streamName: stream.streamName, ntdfToken: ntdfToken)
        }
    }

    private func disconnectFromStream() {
        Task {
            await viewModel.disconnect()
        }
    }
}

// MARK: - Stream Ended Overlay

struct StreamEndedOverlay: View {
    let streamTitle: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)

            VStack(spacing: 20) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.8))

                Text("Stream Ended")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(streamTitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    EmbeddedLiveStreamView(
        stream: LiveStream(
            streamKey: "live/test",
            rtmpURL: "rtmp://localhost:1935",
            streamName: "live/test",
            creatorPublicID: Data(),
            manifestHeader: "",
            title: "Test Stream"
        ),
        isActive: true
    )
}
