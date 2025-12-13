import AVFoundation
import SwiftUI

/// View for displaying live RTMP streams with NTDF decryption
struct LiveStreamView: View {
    @StateObject private var viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss

    let streamURL: String
    let streamName: String
    let ntdfToken: String

    /// Initialize with stream details and NTDF token for decryption
    /// - Parameters:
    ///   - streamURL: RTMP URL (e.g., rtmp://100.arkavo.net:1935)
    ///   - streamName: Stream name/key (e.g., live/creator)
    ///   - ntdfToken: NTDF token for KAS authentication and key rewrap
    init(streamURL: String, streamName: String, ntdfToken: String) {
        self.streamURL = streamURL
        self.streamName = streamName
        self.ntdfToken = ntdfToken
        _viewModel = StateObject(wrappedValue: LiveStreamViewModel())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video display layer - always present so it's ready when frames arrive
            LiveStreamDisplayView(viewModel: viewModel)
                .ignoresSafeArea()
                .opacity(viewModel.isPlaying ? 1 : 0)

            // Overlay UI
            VStack {
                // Top bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()

                    // Live indicator
                    if viewModel.isPlaying {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.8))
                        .clipShape(Capsule())
                    }
                }
                .padding()

                Spacer()

                // Status/error display
                if let error = viewModel.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await viewModel.connect(url: streamURL, streamName: streamName)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding()
                } else if viewModel.isConnecting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text("Connecting to stream...")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                // Bottom info bar
                if viewModel.isPlaying {
                    HStack {
                        // Stream info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(streamName)
                                .font(.headline)
                                .foregroundStyle(.white)
                            if let metadata = viewModel.metadata {
                                HStack(spacing: 8) {
                                    if let width = metadata.width, let height = metadata.height {
                                        Text("\(width)x\(height)")
                                    }
                                    if let fps = metadata.framerate {
                                        Text("\(Int(fps)) fps")
                                    }
                                    if metadata.isEncrypted {
                                        Image(systemName: "lock.fill")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        Spacer()

                        // Stats
                        VStack(alignment: .trailing) {
                            Text("\(viewModel.framesReceived) frames")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding()
                    .background(.black.opacity(0.5))
                }
            }
        }
        .task {
            await viewModel.connect(url: streamURL, streamName: streamName, ntdfToken: ntdfToken)
        }
        .onDisappear {
            Task {
                await viewModel.disconnect()
            }
        }
    }
}

/// UIViewRepresentable for AVSampleBufferDisplayLayer
struct LiveStreamDisplayView: UIViewRepresentable {
    @ObservedObject var viewModel: LiveStreamViewModel

    func makeUIView(context: Context) -> LiveStreamUIView {
        let now = Date()
        print("📺 [LiveStreamDisplayView] Creating UIView at \(now)")
        let view = LiveStreamUIView()
        viewModel.displayLayer = view.displayLayer
        viewModel.audioRenderer = view.audioRenderer
        viewModel.synchronizer = view.synchronizer
        print("📺 [LiveStreamDisplayView] Renderers assigned at \(Date()), took \(Date().timeIntervalSince(now))s")
        return view
    }

    func updateUIView(_ uiView: LiveStreamUIView, context: Context) {
        // Ensure renderers are always set (in case of view recreation)
        if viewModel.displayLayer !== uiView.displayLayer {
            print("📺 [LiveStreamDisplayView] Re-assigning renderers")
            viewModel.displayLayer = uiView.displayLayer
            viewModel.audioRenderer = uiView.audioRenderer
            viewModel.synchronizer = uiView.synchronizer
        }
    }
}

/// UIView that hosts AVSampleBufferDisplayLayer and audio renderer
class LiveStreamUIView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()
    let audioRenderer = AVSampleBufferAudioRenderer()
    let synchronizer = AVSampleBufferRenderSynchronizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        print("📺 [LiveStreamUIView] Setting up displayLayer and audioRenderer")
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(displayLayer)

        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
            print("📺 [LiveStreamUIView] ✅ Audio session configured for playback")
        } catch {
            print("📺 [LiveStreamUIView] ⚠️ Failed to configure audio session: \(error)")
        }

        // Add renderers to synchronizer for coordinated playback
        // Note: On iOS 18+, use sampleBufferRenderer for video (must match enqueue target)
        synchronizer.addRenderer(displayLayer.sampleBufferRenderer)
        synchronizer.addRenderer(audioRenderer)

        // Ensure audio is not muted
        audioRenderer.volume = 1.0
        audioRenderer.isMuted = false

        print("📺 [LiveStreamUIView] Setup complete - video and audio synchronized, volume=\(audioRenderer.volume)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
        print("📺 [LiveStreamUIView] layoutSubviews: frame=\(bounds)")
    }
}

/// Stream metadata for UI display
struct LiveStreamMetadata {
    var width: Int?
    var height: Int?
    var framerate: Double?
    var isEncrypted: Bool = false
}

#Preview {
    LiveStreamView(streamURL: "rtmp://localhost:1935", streamName: "live/test", ntdfToken: "preview-token")
}
