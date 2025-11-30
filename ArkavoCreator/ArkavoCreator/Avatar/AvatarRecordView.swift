import Metal
import SwiftUI

/// Minimal avatar preview shell that reflects remote face metadata.
/// Controls are now in InspectorPanel - this view is just the preview.
struct AvatarRecordView: View {
    @ObservedObject var viewModel: AvatarViewModel
    @State private var renderer: VRMAvatarRenderer?
    @State private var showError = false

    /// User preference to show body tracking overlay
    @AppStorage("showBodyTracking") private var showBodyTracking = false
    /// User preference to show face tracking overlay
    @AppStorage("showFaceTracking") private var showFaceTracking = false

    var isTransparent: Bool = false

    var body: some View {
        previewPane
            .alert("Error", isPresented: $showError, presenting: viewModel.error) { _ in
                Button("OK") {
                    viewModel.error = nil
                }
            } message: { error in
                Text(error)
            }
            .onAppear {
                initializeRenderer()
                renderer?.resume()
                viewModel.activate()
            }
            .onDisappear {
                renderer?.pause()
                viewModel.deactivate()
            }
    }

    private var previewPane: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let renderer {
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
            if !isTransparent {
                VStack(alignment: .trailing, spacing: 8) {
                    // Body tracking skeleton visualization
                    if showBodyTracking {
                        SkeletonDebugView(skeleton: viewModel.latestBodySkeleton)
                    }

                    // Face tracking status indicator
                    if showFaceTracking {
                        faceTrackingIndicator
                    }
                }
                .padding(16)
            }
        }
    }

    /// Face tracking status indicator
    private var faceTrackingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "face.smiling")
                .font(.caption)
            Text(viewModel.faceTrackingStatus)
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.secondary)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
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

    private func initializeRenderer() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            viewModel.error = "Metal not available on this system"
            showError = true
            return
        }

        renderer = VRMAvatarRenderer(device: device)
        viewModel.attachRenderer(renderer)
    }
}

#Preview {
    AvatarRecordView(viewModel: AvatarViewModel())
        .frame(width: 800, height: 600)
}
