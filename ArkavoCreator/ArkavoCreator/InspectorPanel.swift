import ArkavoKit
import SwiftUI

/// Context-aware right panel showing source-specific settings
struct InspectorPanel: View {
    let visualSource: VisualSource?
    @Bindable var recordViewModel: RecordViewModel
    @ObservedObject var avatarViewModel: AvatarViewModel
    @Binding var isVisible: Bool
    var onLoadAvatarModel: () -> Void

    var body: some View {
        ScrollView {
            switch visualSource {
            case .face:
                FaceInspectorContent(viewModel: recordViewModel)
            case .avatar:
                AvatarInspectorContent(
                    viewModel: avatarViewModel,
                    onLoadModel: onLoadAvatarModel
                )
            case nil:
                // Audio-only mode
                AudioInspectorContent(viewModel: recordViewModel)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Face Persona Content

struct FaceInspectorContent: View {
    @Bindable var viewModel: RecordViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section: Camera Selection
            sectionHeader("Camera")

            if viewModel.availableCameras.isEmpty {
                Text("No cameras available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.availableCameras, id: \.id) { camera in
                        CameraToggleRow(
                            camera: camera,
                            isSelected: viewModel.isCameraSelected(camera),
                            canSelect: viewModel.canSelectMoreCameras(for: camera),
                            transportLabel: viewModel.cameraTransportLabel(for: camera),
                            onToggle: { isSelected in
                                viewModel.toggleCameraSelection(camera, isSelected: isSelected)
                            }
                        )
                    }
                }
            }

            // Remote cameras (if any)
            if !viewModel.remoteCameraSources.isEmpty {
                Divider()
                sectionHeader("Remote Cameras")
                VStack(spacing: 8) {
                    ForEach(viewModel.remoteCameraSources, id: \.self) { sourceID in
                        RemoteCameraRow(
                            sourceID: sourceID,
                            isSelected: viewModel.isRemoteCameraSelected(sourceID),
                            onToggle: { isSelected in
                                viewModel.toggleRemoteCameraSelection(sourceID, isSelected: isSelected)
                            }
                        )
                    }
                }
            }

            // Section: Multi-Camera Layout (if multiple selected)
            if viewModel.selectedCameraIDs.count > 1 {
                Divider()
                sectionHeader("Layout")
                Picker("Layout", selection: $viewModel.cameraLayout) {
                    ForEach(MultiCameraLayout.allCases, id: \.self) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Avatar Persona Content

struct AvatarInspectorContent: View {
    @ObservedObject var viewModel: AvatarViewModel
    @AppStorage("showBodyTracking") private var showBodyTracking = false
    @AppStorage("showFaceTracking") private var showFaceTracking = false
    var onLoadModel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section: Tracking Overlays
            sectionHeader("Tracking")

            HStack(spacing: 8) {
                // Body Tracking Toggle
                Button {
                    showBodyTracking.toggle()
                } label: {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(showBodyTracking ? Color.accentColor.opacity(0.3) : Color.clear)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(showBodyTracking ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle Body Tracking Overlay")

                // Face Tracking Toggle
                Button {
                    showFaceTracking.toggle()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(showFaceTracking ? Color.accentColor.opacity(0.3) : Color.clear)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(showFaceTracking ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle Face Tracking Overlay")
            }

            Divider()

            // Section: Select Avatar
            sectionHeader("Avatar")

            if viewModel.downloadedModels.isEmpty {
                Text("No avatars available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.downloadedModels, id: \.self) { url in
                        AvatarRow(
                            url: url,
                            isSelected: viewModel.selectedModelURL == url,
                            isLoaded: viewModel.isModelLoaded && viewModel.selectedModelURL == url,
                            onSelect: {
                                viewModel.selectedModelURL = url
                                onLoadModel()
                            }
                        )
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}

private struct AvatarRow: View {
    let url: URL
    let isSelected: Bool
    let isLoaded: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isLoaded ? "checkmark.circle.fill" : (isSelected ? "circle.inset.filled" : "circle"))
                    .foregroundStyle(isLoaded ? .green : (isSelected ? .accentColor : .secondary))

                Text(url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Audio Persona Content

struct AudioInspectorContent: View {
    @Bindable var viewModel: RecordViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section: Microphone
            sectionHeader("Microphone")
            HStack(spacing: 8) {
                Image(systemName: viewModel.enableMicrophone ? "mic.fill" : "mic.slash")
                    .foregroundStyle(viewModel.enableMicrophone ? .green : .secondary)
                Text(viewModel.enableMicrophone ? "Active" : "Muted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Section: Audio Level
            sectionHeader("Audio Level")
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                    Capsule()
                        .fill(levelColor(for: viewModel.audioLevelPercentage()))
                        .frame(width: max(0, 252 * viewModel.audioLevelPercentage()))
                        .animation(.linear(duration: 0.1), value: viewModel.audioLevelPercentage())
                }
                .frame(height: 8)

                Text(String(format: "%.0f%%", viewModel.audioLevelPercentage() * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func levelColor(for level: Double) -> Color {
        if level < 0.5 { .green } else if level < 0.8 { .yellow } else { .red }
    }
}

// MARK: - Helper Views

private struct CameraToggleRow: View {
    let camera: CameraInfo
    let isSelected: Bool
    let canSelect: Bool
    let transportLabel: String
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(camera.name)
                        .lineLimit(1)
                    Text(transportLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect && !isSelected)
        .opacity(canSelect || isSelected ? 1.0 : 0.5)
    }
}

private struct RemoteCameraRow: View {
    let sourceID: String
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote: \(sourceID.prefix(8))...")
                        .lineLimit(1)
                    Text("Network Camera")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Helpers

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.headline)
        .foregroundStyle(.primary)
}
