import ArkavoKit
import SwiftUI
import UniformTypeIdentifiers

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
            case .muse:
                MuseInspectorContent(onLoadModel: onLoadAvatarModel)
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

            // Section: Background removal
            Divider()
            sectionHeader("Background")

            Toggle(isOn: $viewModel.floatingHeadEnabled) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.minus")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Floating Head")
                        Text("Remove background from camera")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)

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

    @State private var showExportSheet = false
    @State private var exportName = ""
    @State private var lastExportedURL: URL?
    @State private var showExportSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section: VRMA Recording
            sectionHeader("Motion Capture")

            VRMARecordingControls(
                viewModel: viewModel,
                onRecordingStopped: { url in
                    lastExportedURL = url
                    showExportSuccess = url != nil
                }
            )

            Divider()

            // Section: Tracking
            sectionHeader("Tracking")

            // Tracking Mode Selection
            Picker("Mode", selection: $viewModel.trackingMode) {
                ForEach(AvatarTrackingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.trackingMode) { _, newMode in
                viewModel.setTrackingMode(newMode)
            }

            // Face Tracking Enable/Disable
            Toggle(isOn: $viewModel.faceTrackingEnabled) {
                HStack {
                    Image(systemName: "face.smiling")
                    Text("Face Tracking")
                }
            }
            .toggleStyle(.switch)

            // Debug Overlays
            HStack(spacing: 8) {
                // Body Tracking Overlay Toggle
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

                // Face Tracking Overlay Toggle
                Button {
                    showFaceTracking.toggle()
                } label: {
                    Image(systemName: "waveform")
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
                .help("Toggle Face Debug Overlay")
            }

            #if DEBUG
            // Pipeline Diagnostics (DEBUG only)
            Divider()
            sectionHeader("Pipeline Diagnostics")

            HStack {
                Circle()
                    .fill(viewModel.diagnosticsRecorder.isCapturing ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(viewModel.diagnosticsRecorder.isCapturing ? "Capturing" : "Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.diagnosticsRecorder.captureCount) events")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                if let url = viewModel.exportDiagnostics(name: "pipeline_capture") {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Diagnostics")
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.diagnosticsRecorder.captureCount == 0)
            .help("Export captured pipeline data to ~/Documents/Diagnostics/")
            #endif

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

            Divider()

            // Section: Background
            sectionHeader("Background")

            Picker("Type", selection: $viewModel.backgroundType) {
                ForEach(AvatarBackgroundType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.backgroundType {
            case .solidColor:
                ColorPicker("Color", selection: $viewModel.backgroundColor)
            case .image:
                Button("Select Image...") {
                    selectBackgroundImage()
                }
                .buttonStyle(.bordered)
                if let url = viewModel.backgroundImageURL {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.backgroundImageURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .video:
                Button("Select Video...") {
                    selectBackgroundVideo()
                }
                .buttonStyle(.bordered)
                if let url = viewModel.backgroundVideoURL {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.backgroundVideoURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .alert("Export Successful", isPresented: $showExportSuccess) {
            Button("Show in Finder") {
                if let url = lastExportedURL {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let url = lastExportedURL {
                Text("Saved to:\n\(url.lastPathComponent)")
            }
        }
    }

    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic]
        panel.message = "Select background image"
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            viewModel.backgroundImageURL = panel.url
        }
    }

    private func selectBackgroundVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Select background video"
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            viewModel.backgroundVideoURL = panel.url
        }
    }
}

// MARK: - VRMA Recording Controls

private struct VRMARecordingControls: View {
    @ObservedObject var viewModel: AvatarViewModel
    var onRecordingStopped: (URL?) -> Void

    @State private var showNameSheet = false
    @State private var recordingName = "animation"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recording status and controls
            HStack(spacing: 12) {
                // Record/Stop button
                Button {
                    if viewModel.isVRMARecording {
                        showNameSheet = true
                    } else {
                        viewModel.startVRMARecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.isVRMARecording ? Color.red : Color.red.opacity(0.8))
                            .frame(width: 44, height: 44)

                        if viewModel.isVRMARecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 16, height: 16)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 18, height: 18)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(viewModel.isVRMARecording ? "Stop Recording" : "Start Recording")
                .disabled(!viewModel.isModelLoaded)

                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    if viewModel.isVRMARecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .opacity(pulsingOpacity)
                            Text("Recording")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                        }

                        Text(formatDuration(viewModel.vrmaRecordingDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ready to Record")
                            .font(.subheadline)
                            .foregroundStyle(viewModel.isModelLoaded ? .primary : .secondary)

                        if !viewModel.isModelLoaded {
                            Text("Load a model first")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Cancel button (only when recording)
                if viewModel.isVRMARecording {
                    Button {
                        viewModel.cancelVRMARecording()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Recording")
                }
            }

            // Frame counter (when recording)
            if viewModel.isVRMARecording {
                HStack {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.vrmaFrameCount) frames")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("30 fps")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .sheet(isPresented: $showNameSheet) {
            VRMAExportSheet(
                name: $recordingName,
                duration: viewModel.vrmaRecordingDuration,
                frameCount: viewModel.vrmaFrameCount,
                onExport: {
                    Task {
                        let url = await viewModel.stopVRMARecording(name: recordingName)
                        onRecordingStopped(url)
                    }
                    showNameSheet = false
                },
                onCancel: {
                    viewModel.cancelVRMARecording()
                    showNameSheet = false
                }
            )
        }
    }

    private var pulsingOpacity: Double {
        let time = Date().timeIntervalSinceReferenceDate
        return 0.5 + 0.5 * sin(time * 3)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - VRMA Export Sheet

private struct VRMAExportSheet: View {
    @Binding var name: String
    let duration: TimeInterval
    let frameCount: Int
    var onExport: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Recording")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Animation name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                VStack {
                    Text(formatDuration(duration))
                        .font(.title2.monospacedDigit())
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack {
                    Text("\(frameCount)")
                        .font(.title2.monospacedDigit())
                    Text("Frames")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Discard", role: .destructive) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

// MARK: - Muse AI Avatar Content

struct MuseInspectorContent: View {
    var onLoadModel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Muse AI Avatar")

            Text("AI-driven avatar with procedural animation, lip sync, and chat reactions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Load VRM Model", action: onLoadModel)
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
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
