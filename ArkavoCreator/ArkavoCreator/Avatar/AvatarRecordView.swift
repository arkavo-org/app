//
//  AvatarRecordView.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Metal
import SwiftUI

/// Main view for avatar recording mode
struct AvatarRecordView: View {
    @StateObject private var viewModel = AvatarViewModel()
    @StateObject private var lipSync = LipSyncController()
    @State private var vrmURL = ""
    @State private var renderer: VRMAvatarRenderer?
    @State private var showError = false

    var body: some View {
        HSplitView {
            // Sidebar: Controls
            VStack(alignment: .leading, spacing: 20) {
                // Recording Mode Selector
                sectionHeader("Recording Mode")
                Picker("Mode", selection: $viewModel.recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("RecordingModePicker")

                if viewModel.recordingMode == .avatar {
                    Divider()

                    // VRM Download Section
                    sectionHeader("Download VRM Model")
                    VStack(spacing: 12) {
                        TextField("VRM URL", text: $vrmURL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("VRMURLField")

                        Button {
                            Task {
                                await viewModel.downloadModel(from: vrmURL)
                                vrmURL = ""
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Download")
                            }
                        }
                        .disabled(vrmURL.isEmpty || viewModel.isLoading)
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    // Model Selection
                    sectionHeader("Select Avatar")
                    if viewModel.downloadedModels.isEmpty {
                        Text("No models downloaded yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        List(selection: $viewModel.selectedModelURL) {
                            ForEach(viewModel.downloadedModels, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        viewModel.deleteModel(url)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .tag(url)
                            }
                        }
                        .frame(height: 150)
                    }

                    Divider()

                    // Avatar Settings
                    sectionHeader("Avatar Settings")

                    Toggle("Enable Lip Sync", isOn: $viewModel.isLipSyncEnabled)
                        .onChange(of: viewModel.isLipSyncEnabled) { _, newValue in
                            if newValue {
                                startLipSync()
                            } else {
                                stopLipSync()
                            }
                        }

                    ColorPicker("Background", selection: $viewModel.backgroundColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avatar Scale: \(viewModel.avatarScale, specifier: "%.1f")")
                            .font(.caption)
                        Slider(value: $viewModel.avatarScale, in: 0.5 ... 2.0)
                    }

                    if lipSync.isRecording {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mouth: \(Int(lipSync.currentMouthWeight * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: lipSync.currentMouthWeight)
                                .progressViewStyle(.linear)
                        }
                    }
                }

                Spacer()

                // Load Model Button
                if viewModel.recordingMode == .avatar, viewModel.selectedModelURL != nil {
                    Button {
                        loadSelectedModel()
                    } label: {
                        Label("Load Avatar", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(minWidth: 300, maxWidth: 350)

            // Main Preview Area
            VStack {
                if viewModel.recordingMode == .avatar {
                    if let renderer {
                        AvatarPreviewView(
                            renderer: renderer,
                            backgroundColor: viewModel.backgroundColor,
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholderView
                    }
                } else {
                    cameraPlaceholder
                }
            }
        }
        .onChange(of: lipSync.currentMouthWeight) { _, newValue in
            renderer?.setMouthOpenWeight(newValue)
        }
        .onChange(of: viewModel.selectedModelURL) { _, _ in
            // Auto-load when selection changes
            if viewModel.selectedModelURL != nil {
                loadSelectedModel()
            }
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

    // MARK: - Subviews

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

            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Camera Mode")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Camera recording coming in Phase 3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helper Methods

    private func initializeRenderer() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            viewModel.error = "Metal not available on this system"
            showError = true
            return
        }

        renderer = VRMAvatarRenderer(device: device)
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

                // Start lip sync if enabled
                if viewModel.isLipSyncEnabled {
                    startLipSync()
                }
            } catch {
                viewModel.error = "Failed to load model: \(error.localizedDescription)"
                showError = true
            }

            viewModel.isLoading = false
        }
    }

    private func startLipSync() {
        do {
            try lipSync.startCapture()
        } catch {
            viewModel.error = "Failed to start lip sync: \(error.localizedDescription)"
            viewModel.isLipSyncEnabled = false
            showError = true
        }
    }

    private func stopLipSync() {
        lipSync.stopCapture()
        renderer?.setMouthOpenWeight(0.0)
    }
}

// MARK: - Preview

#Preview {
    AvatarRecordView()
        .frame(width: 1024, height: 768)
}
