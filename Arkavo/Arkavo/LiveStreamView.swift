import AVFoundation
import SwiftUI

/// View for displaying live RTMP streams with NTDF decryption
struct LiveStreamView: View {
    @StateObject private var viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss

    let streamURL: String
    let streamName: String

    init(streamURL: String, streamName: String) {
        self.streamURL = streamURL
        self.streamName = streamName
        _viewModel = StateObject(wrappedValue: LiveStreamViewModel())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video display layer
            if viewModel.isPlaying {
                LiveStreamDisplayView(viewModel: viewModel)
                    .ignoresSafeArea()
            }

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
            await viewModel.connect(url: streamURL, streamName: streamName)
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
        let view = LiveStreamUIView()
        viewModel.displayLayer = view.displayLayer
        return view
    }

    func updateUIView(_ uiView: LiveStreamUIView, context: Context) {
        // Updates handled via displayLayer reference
    }
}

/// UIView that hosts AVSampleBufferDisplayLayer
class LiveStreamUIView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(displayLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
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
    LiveStreamView(streamURL: "rtmp://localhost:1935", streamName: "live/test")
}
