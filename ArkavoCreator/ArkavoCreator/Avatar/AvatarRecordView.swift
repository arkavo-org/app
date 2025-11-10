import Metal
import SwiftUI

/// Minimal avatar preview shell that reflects remote face metadata.
struct AvatarRecordView: View {
    @StateObject private var viewModel = AvatarViewModel()
    @State private var vrmURL = ""
    @State private var renderer: VRMAvatarRenderer?
    @State private var showError = false

    var body: some View {
        HSplitView {
            controlsPane
                .padding()
                .frame(minWidth: 300, maxWidth: 350)

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
            initializeRenderer()
        }
    }

    private var controlsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Download VRM Model")
            downloadSection

            Divider()
            sectionHeader("Select Avatar")
            avatarList

            Divider()
            sectionHeader("Avatar Settings")
            faceTrackingStatusView
            ColorPicker("Background", selection: $viewModel.backgroundColor)
            Slider(value: $viewModel.avatarScale, in: 0.5 ... 2.0) {
                Text("Avatar Scale")
            }
            .help("Adjust avatar scale")

            if viewModel.selectedModelURL != nil {
                Button {
                    loadSelectedModel()
                } label: {
                    Label("Load Avatar", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

    private var downloadSection: some View {
        VStack(spacing: 12) {
            TextField("VRM URL", text: $vrmURL)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await viewModel.downloadModel(from: vrmURL)
                    vrmURL = ""
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Download")
                }
            }
            .disabled(vrmURL.isEmpty || viewModel.isLoading)
            .buttonStyle(.borderedProminent)
        }
    }

    private var avatarList: some View {
        Group {
            if viewModel.downloadedModels.isEmpty {
                Text("No models downloaded yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                List(selection: $viewModel.selectedModelURL) {
                    ForEach(viewModel.downloadedModels, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .tag(url)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var faceTrackingStatusView: some View {
        HStack(spacing: 8) {
            Image(systemName: "face.smiling")
                .foregroundStyle(.secondary)
            Text(viewModel.faceTrackingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewPane: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let renderer {
                    AvatarPreviewView(
                        renderer: renderer,
                        backgroundColor: viewModel.backgroundColor
                    )
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Debug: Skeleton visualization overlay
            SkeletonDebugView(skeleton: viewModel.latestBodySkeleton)
                .padding(16)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
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

    private func loadSelectedModel() {
        guard let url = viewModel.selectedModelURL,
              let renderer
        else {
            return
        }

        Task {
            viewModel.isLoading = true
            viewModel.error = nil

            do {
                try await renderer.loadModel(from: url)
            } catch {
                viewModel.error = "Failed to load model: \(error.localizedDescription)"
                showError = true
            }

            viewModel.isLoading = false
        }
    }
}

#Preview {
    AvatarRecordView()
        .frame(width: 1024, height: 768)
}
