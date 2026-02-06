import AVKit
import Metal
import SwiftUI

/// Minimal avatar preview shell that reflects remote face metadata.
/// Controls are now in InspectorPanel - this view is just the preview.
struct AvatarRecordView: View {
    @ObservedObject var viewModel: AvatarViewModel
    @State private var showError = false

    /// User preference to show body tracking overlay
    @AppStorage("showBodyTracking") private var showBodyTracking = false
    /// User preference to show face tracking overlay
    @AppStorage("showFaceTracking") private var showFaceTracking = false

    var isTransparent: Bool = false

    var body: some View {
        ZStack {
            // Background layer (only when not transparent PiP mode)
            if !isTransparent {
                backgroundView
            }

            // Avatar layer
            previewPane
        }
            .alert("Error", isPresented: $showError, presenting: viewModel.error) { _ in
                Button("OK") {
                    viewModel.error = nil
                }
            } message: { error in
                Text(error)
            }
            .onAppear {
                initializeRendererIfNeeded()
                viewModel.renderer?.resume()
                viewModel.activate()
                // Apply current tracking mode's camera position (deferred to avoid publishing during view update)
                Task { @MainActor in
                    viewModel.setTrackingMode(viewModel.trackingMode)
                }
                // Auto-load last selected model
                Task {
                    await viewModel.autoLoadIfNeeded()
                }
            }
            .onDisappear {
                viewModel.renderer?.pause()
                viewModel.deactivate()
            }
    }

    private var previewPane: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let renderer = viewModel.renderer {
                    AvatarPreviewView(
                        renderer: renderer,
                        backgroundColor: isTransparent ? .clear : viewModel.backgroundColor
                    )
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tracking overlays (controlled via Inspector)
            VStack(alignment: .trailing, spacing: 8) {
                // Body tracking skeleton visualization
                if showBodyTracking {
                    SkeletonDebugView(skeleton: viewModel.latestBodySkeleton)
                }

                // Face tracking blend shape visualization
                if showFaceTracking {
                    FaceDebugView(blendShapes: viewModel.latestFaceBlendShapes)
                }
            }
            .padding(16)
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Select and load a VRM model")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch viewModel.backgroundType {
        case .solidColor:
            viewModel.backgroundColor
                .ignoresSafeArea()
        case .image:
            if let url = viewModel.backgroundImageURL,
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                viewModel.backgroundColor
                    .ignoresSafeArea()
            }
        case .video:
            if let url = viewModel.backgroundVideoURL {
                VideoBackgroundView(url: url)
                    .ignoresSafeArea()
            } else {
                viewModel.backgroundColor
                    .ignoresSafeArea()
            }
        }
    }

    /// Initialize renderer in the view model if not already created
    private func initializeRendererIfNeeded() {
        guard viewModel.renderer == nil else { return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            viewModel.error = "Metal not available on this system"
            showError = true
            return
        }

        viewModel.attachRenderer(VRMAvatarRenderer(device: device))
    }
}

// MARK: - Video Background View

/// Looping video player for background
struct VideoBackgroundView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true

        let player = AVQueuePlayer()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        containerView.layer?.addSublayer(playerLayer)

        // Set up looper
        let playerItem = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: player, templateItem: playerItem)
        context.coordinator.looper = looper

        player.play()
        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.playerLayer?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var player: AVQueuePlayer?
        var playerLayer: AVPlayerLayer?
        var looper: AVPlayerLooper?
    }
}

#Preview {
    AvatarRecordView(viewModel: AvatarViewModel())
        .frame(width: 800, height: 600)
}
