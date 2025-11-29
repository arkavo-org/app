import ArkavoKit
import AVFoundation
import SwiftUI

struct RecordView: View {
    @State private var viewModel = RecordViewModel()
    @ObservedObject private var previewStore = CameraPreviewStore.shared
    @State private var recordingMode: RecordingMode = .camera
    
    // Animation state
    @State private var pulsing: Bool = false

    var body: some View {
        ZStack {
            // Ambient Background
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Mode Picker Header
                modePickerContainer
                
                // Main Content
                if recordingMode == .avatar {
                    AvatarRecordView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        cameraRecordingView
                            .padding(24)
                    }
                }
            }
        }
        .navigationTitle("Record")
        .onAppear {
            viewModel.refreshCameraDevices()
            viewModel.bindPreviewStore(previewStore)
            try? viewModel.activatePreviewPipeline()
        }
    }

    private var modePickerContainer: some View {
        HStack {
            Picker("Recording Mode", selection: $recordingMode) {
                ForEach(RecordingMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.1)), alignment: .bottom)
    }

    private var cameraRecordingView: some View {
        VStack(spacing: 24) {
            if !viewModel.isRecording {
                setupCard
            } else {
                statusCard
            }
            
            // Error message
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .frame(minWidth: 500)
        .onChange(of: viewModel.selectedCameraIDs) { _, _ in viewModel.refreshCameraPreview() }
        .onChange(of: viewModel.enableCamera) { _, isEnabled in
            if isEnabled { viewModel.refreshCameraDevices() }
            else {
                viewModel.selectedCameraIDs.removeAll()
                viewModel.refreshCameraPreview()
            }
        }
        .onChange(of: viewModel.remoteBridgeEnabled) { _, _ in try? viewModel.activatePreviewPipeline() }
    }

    // MARK: - Cards

    private var setupCard: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 4) {
                Text("Studio Recording")
                    .font(.title2.bold())
                Text("Capture screen, camera, and audio.")
                    .foregroundStyle(.secondary)
            }
            
            // Title Input
            TextField("Recording Title", text: $viewModel.title)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding()
                .background(.background.opacity(0.5))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
            
            // Preview Panel
            CameraPreviewPanel(
                title: "Camera Preview",
                image: previewStore.image(for: viewModel.currentPreviewSourceID),
                sourceLabel: viewModel.currentPreviewSourceID,
                placeholderText: "Connect an iPhone/iPad with Arkavo Remote Camera"
            )
            
            // Toggles Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ToggleCard(title: "Camera", icon: "camera", isOn: $viewModel.enableCamera)
                ToggleCard(title: "Microphone", icon: "mic", isOn: $viewModel.enableMicrophone)
                ToggleCard(title: "Watermark", icon: "checkmark.shield", isOn: $viewModel.watermarkEnabled)
                ToggleCard(title: "Remote Cam", icon: "iphone", isOn: $viewModel.remoteBridgeEnabled)
            }

            if viewModel.enableCamera {
                cameraSourcesSection
            }
            
            if viewModel.remoteBridgeEnabled {
                remoteBridgeSection
            }
            
            // Start Button
            Button(action: {
                Task { await viewModel.startRecording() }
            }) {
                HStack {
                    Image(systemName: "record.circle.fill")
                    Text("Start Recording")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 10)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.2), lineWidth: 1))
    }

    private var statusCard: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.isPaused ? Color.orange : Color.red)
                            .frame(width: 12, height: 12)
                            .opacity(viewModel.isPaused ? 1.0 : (pulsing ? 1.0 : 0.3))
                        
                        Text(viewModel.isPaused ? "PAUSED" : "RECORDING")
                            .font(.title2.bold())
                            .foregroundColor(viewModel.isPaused ? .orange : .red)
                    }
                    
                    Text(viewModel.formattedDuration())
                        .font(.system(size: 32, weight: .light, design: .monospaced))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        if viewModel.isPaused {
                            Task { viewModel.resumeRecording() }
                        } else {
                            viewModel.pauseRecording()
                        }
                    }) {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        Task { await viewModel.stopRecording() }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if viewModel.enableMicrophone {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio Level").font(.caption).foregroundStyle(.secondary)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(levelColor(for: viewModel.audioLevelPercentage()))
                                .frame(width: geometry.size.width * viewModel.audioLevelPercentage())
                                .animation(.linear(duration: 0.1), value: viewModel.audioLevelPercentage())
                        }
                    }
                    .frame(height: 6)
                }
            }
            
            CameraPreviewPanel(
                title: "Monitor",
                image: previewStore.image(for: viewModel.currentPreviewSourceID),
                sourceLabel: viewModel.currentPreviewSourceID,
                placeholderText: "Preview Active"
            )
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .red.opacity(0.1), radius: 20, x: 0, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    // MARK: - Components

    private func levelColor(for level: Double) -> Color {
        if level < 0.5 { .green } else if level < 0.8 { .yellow } else { .red }
    }
}

struct ToggleCard: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isOn ? .accentColor : .secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isOn ? Color.accentColor.opacity(0.1) : Color.clear)
            .background(.regularMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
#Preview {
    NavigationStack {
        RecordView()
    }
}
