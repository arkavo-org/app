import ArkavoKit
import AVFoundation
import SwiftUI

struct RecordView: View {
    @State private var viewModel = RecordViewModel()
    @ObservedObject private var previewStore = CameraPreviewStore.shared
    @State private var recordingMode: RecordingMode = .camera

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker at top
            modePicker

            // Show appropriate view based on mode
            if recordingMode == .avatar {
                AvatarRecordView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cameraRecordingView
            }
        }
        .navigationTitle("Record")
    }

    private var modePicker: some View {
        Picker("Recording Mode", selection: $recordingMode) {
            ForEach(RecordingMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    private var cameraRecordingView: some View {
        VStack(spacing: 24) {
            // Title section
            if !viewModel.isRecording {
                titleSection
            }

            Spacer()

            // Status display when recording
            if viewModel.isRecording {
                recordingStatusSection
            } else {
                setupPromptSection
            }

            Spacer()

            // Main control button
            controlButton

            // Error message
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Processing indicator
            if viewModel.isProcessing {
                ProgressView("Finishing recording...")
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            viewModel.refreshCameraDevices()
            viewModel.bindPreviewStore(previewStore)
            try? viewModel.activatePreviewPipeline()
        }
        .onChange(of: viewModel.selectedCameraIDs) { _, _ in
            viewModel.refreshCameraPreview()
        }
        .onChange(of: viewModel.enableCamera) { _, isEnabled in
            if isEnabled {
                viewModel.refreshCameraDevices()
            } else {
                viewModel.selectedCameraIDs.removeAll()
                viewModel.refreshCameraPreview()
            }
        }
        .onChange(of: viewModel.remoteBridgeEnabled) { _, _ in
            try? viewModel.activatePreviewPipeline()
        }
    }

    // MARK: - View Components

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text("Recording Title")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Enter title", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
                .accessibilityLabel("Recording title")
                .accessibilityHint("Enter a title for your recording")
        }
    }

    private var setupPromptSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Ready to Record")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Screen + Camera + Microphone")
                .font(.subheadline)
                .foregroundColor(.secondary)

            CameraPreviewPanel(
                title: "Camera Preview",
                image: previewStore.image(for: viewModel.currentPreviewSourceID),
                sourceLabel: viewModel.currentPreviewSourceID,
                placeholderText: "Connect an iPhone/iPad with Arkavo Remote Camera"
            )

            // Quick settings
            VStack(spacing: 12) {
                Toggle("Enable Camera", isOn: $viewModel.enableCamera)
                    .accessibilityLabel("Enable camera")
                    .accessibilityHint("Toggle camera recording in picture-in-picture mode")
                Toggle("Enable Microphone", isOn: $viewModel.enableMicrophone)
                    .accessibilityLabel("Enable microphone")
                    .accessibilityHint("Toggle microphone audio recording")

                if viewModel.enableCamera {
                    Picker("Camera Position", selection: $viewModel.pipPosition) {
                        ForEach(PiPPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .accessibilityLabel("Camera position")
                    .accessibilityHint("Select where the camera overlay appears on screen")

                    cameraSourcesSection
                    remoteCameraSourcesSection
                }

                Divider()

                // Watermark settings
                Toggle("Arkavo Watermark", isOn: $viewModel.watermarkEnabled)
                    .accessibilityLabel("Enable Arkavo watermark")
                    .accessibilityHint("Toggle watermark overlay on recording")

                if viewModel.watermarkEnabled {
                    Picker("Watermark Position", selection: $viewModel.watermarkPosition) {
                        ForEach(WatermarkPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .accessibilityLabel("Watermark position")
                    .accessibilityHint("Select where the watermark appears on screen")

                    VStack(spacing: 4) {
                        HStack {
                            Text("Opacity")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(viewModel.watermarkOpacity * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.watermarkOpacity, in: 0.2 ... 1.0)
                            .accessibilityLabel("Watermark opacity")
                            .accessibilityValue("\(Int(viewModel.watermarkOpacity * 100)) percent")
                            .accessibilityHint("Adjust watermark transparency")
                    }
                }

                remoteBridgeSection
            }
            .frame(maxWidth: 300)
        }
    }

    private var recordingStatusSection: some View {
        VStack(spacing: 20) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isPaused ? Color.orange : Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(viewModel.isPaused ? 1.0 : (pulsing ? 1.0 : 0.3))

                Text(viewModel.isPaused ? "PAUSED" : "RECORDING")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.isPaused ? .orange : .red)
            }

            // Duration
            Text(viewModel.formattedDuration())
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.primary)

            // Audio level indicator
            if viewModel.enableMicrophone {
                VStack(spacing: 4) {
                    Text("Microphone Level")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))

                            // Level bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(levelColor(for: viewModel.audioLevelPercentage()))
                                .frame(width: geometry.size.width * viewModel.audioLevelPercentage())
                        }
                    }
                    .frame(height: 8)
                }
                .frame(maxWidth: 300)
            }

            CameraPreviewPanel(
                title: "Camera Preview",
                image: previewStore.image(for: viewModel.currentPreviewSourceID),
                sourceLabel: viewModel.currentPreviewSourceID,
                placeholderText: "Connect an iPhone/iPad with Arkavo Remote Camera"
            )

            // Pause/Resume button
            Button(action: {
                if viewModel.isPaused {
                    Task {
                        viewModel.resumeRecording()
                    }
                } else {
                    viewModel.pauseRecording()
                }
            }) {
                Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(viewModel.isPaused ? "Resume recording" : "Pause recording")
            .accessibilityHint(viewModel.isPaused ? "Resume the paused recording" : "Temporarily pause the recording")
        }
    }

    private var controlButton: some View {
        Button(action: {
            Task {
                if viewModel.isRecording {
                    await viewModel.stopRecording()
                } else {
                    await viewModel.startRecording()
                }
            }
        }) {
            Label(
                viewModel.isRecording ? "Stop Recording" : "Start Recording",
                systemImage: viewModel.isRecording ? "stop.circle.fill" : "record.circle.fill",
            )
            .font(.title3)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? .red : .blue)
        .disabled(viewModel.isProcessing)
        .accessibilityLabel(viewModel.isRecording ? "Stop Recording" : "Start Recording")
        .accessibilityHint(viewModel.isRecording ? "End the current recording session and save the video" : "Begin recording screen, camera, and microphone")
    }

    // MARK: - Helpers

    @State private var pulsing = false

    private var pulseAnimation: Animation {
        Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }

    private func levelColor(for level: Double) -> Color {
        if level < 0.5 {
            .green
        } else if level < 0.8 {
            .yellow
        } else {
            .red
        }
    }
}

extension RecordView {
    private var cameraSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Camera Sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    viewModel.refreshCameraDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh connected cameras")
            }

            if viewModel.availableCameras.isEmpty {
                Text("No cameras detected. Connect an iPhone via Continuity Camera, USB-C, or Wi-Fi to get started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(viewModel.availableCameras) { camera in
                    Toggle(isOn: Binding(
                        get: { viewModel.isCameraSelected(camera) },
                        set: { viewModel.toggleCameraSelection(camera, isSelected: $0) }
                    )) {
                        HStack {
                            Text(camera.displayName)
                            Spacer()
                            Text(viewModel.cameraTransportLabel(for: camera))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!viewModel.canSelectMoreCameras(for: camera))
                }

                if viewModel.selectedCameraIDs.count > 1 {
                    Picker("Layout", selection: $viewModel.cameraLayout) {
                        ForEach(MultiCameraLayout.allCases) { layout in
                            Text(layout.rawValue).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var remoteCameraSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Remote iOS Cameras")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if viewModel.remoteCameraSources.isEmpty {
                Text("Waiting for Arkavo on iPhone/iPad to connect.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.remoteCameraSources, id: \.self) { source in
                    Toggle(isOn: Binding(
                        get: { viewModel.isRemoteCameraSelected(source) },
                        set: { viewModel.toggleRemoteCameraSelection(source, isSelected: $0) }
                    )) {
                        HStack {
                            Text(source)
                                .lineLimit(1)
                            Spacer()
                            Text("Remote")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!viewModel.isRemoteCameraSelected(source) && viewModel.selectedCameraIDs.count >= MultiCameraLayout.maxSupportedSources)
                }
            }
        }
    }

    private var remoteBridgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.remoteBridgeEnabled ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(viewModel.remoteBridgeEnabled ? "Accepting Remote Cameras" : "Remote Cameras Disabled")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    if viewModel.remoteBridgeEnabled {
                        Text("\(viewModel.remoteCameraSources.count) connected")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: {
                    viewModel.remoteBridgeEnabled.toggle()
                }) {
                    Text(viewModel.remoteBridgeEnabled ? "Disable" : "Enable")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(viewModel.remoteBridgeEnabled ? "Disable remote cameras" : "Enable remote cameras")
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            if viewModel.remoteBridgeEnabled {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Connect from iPhone/iPad")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)

                        HStack {
                            Text("Host:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(viewModel.suggestedHostname)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                        }

                        HStack {
                            Text("Port:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(viewModel.actualPort > 0 ? "\(viewModel.actualPort)" : "auto")
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            if viewModel.actualPort > 0 {
                                Text("(auto-assigned)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quick Connect Options:")
                                    .font(.caption)
                                    .fontWeight(.medium)

                                Text("1. Auto-discovery: Open Arkavo app on iPhone")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("2. QR Code: Scan with iPhone camera →")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("3. Manual: Enter host & port in Arkavo app")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if viewModel.actualPort > 0,
                               let qrImage = QRCodeGenerator.generateQRCode(from: viewModel.connectionInfo, size: CGSize(width: 120, height: 120)) {
                                VStack(spacing: 4) {
                                    Image(nsImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: 120, height: 120)
                                        .background(Color.white)
                                        .cornerRadius(8)

                                    Text("Scan to connect")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(8)
                } label: {
                    Text("Connection Info & QR Code")
                        .font(.caption2)
                }
            }
        }
    }
}

// Start pulsing animation when view appears
extension RecordView {
    private var recordingIndicatorView: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .opacity(pulsing ? 1.0 : 0.3)
            .onAppear {
                withAnimation(pulseAnimation) {
                    pulsing = true
                }
            }
    }
}

#Preview {
    NavigationStack {
        RecordView()
    }
}
