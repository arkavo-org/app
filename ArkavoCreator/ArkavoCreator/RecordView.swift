import ArkavoKit
import ArkavoStreaming
import AVFoundation
import SwiftUI

struct RecordView: View {
    // MARK: - Properties

    @ObservedObject var youtubeClient: YouTubeClient

    // MARK: - Private State

    @State private var viewModel = RecordViewModel()
    @State private var streamViewModel = StreamViewModel()
    @StateObject private var avatarViewModel = AvatarViewModel()
    @State private var enableScreen: Bool = false
    @State private var showStreamSetup: Bool = false
    @State private var showInspector: Bool = false
    @State private var pulsing: Bool = false
    @State private var pipOffset: CGSize = .zero
    @State private var lastPipOffset: CGSize = .zero

    // Shared state (not part of init)
    private var previewStore: CameraPreviewStore { CameraPreviewStore.shared }
    private var studioState: StudioState { StudioState.shared }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Studio Header
            studioHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.1)), alignment: .bottom)

            // MARK: - Main Stage + Inspector
            HStack(spacing: 0) {
                ZStack {
                    // Ambient Background
                    LinearGradient(
                        colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    stageCompositionView
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    InspectorPanel(
                        persona: studioState.persona,
                        recordViewModel: viewModel,
                        avatarViewModel: avatarViewModel,
                        isVisible: $showInspector,
                        onLoadAvatarModel: {
                            Task { await avatarViewModel.loadSelectedModel() }
                        }
                    )
                    .transition(.move(edge: .trailing))
                }
            }

            // MARK: - Bottom Control Bar
            studioControlBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.1)), alignment: .top)
        }
        .navigationTitle("Studio")
        .onAppear {
            syncViewModelState()
            if studioState.persona == .face {
                viewModel.bindPreviewStore(previewStore)
                try? viewModel.activatePreviewPipeline()
            }
            // Load saved stream key for current platform
            streamViewModel.loadStreamKey()
        }
        .onChange(of: studioState.persona) { _, _ in syncViewModelState() }
        .onChange(of: enableScreen) { _, _ in syncViewModelState() }
        .sheet(isPresented: $showStreamSetup) {
            StreamDestinationPicker(
                streamViewModel: streamViewModel,
                youtubeClient: youtubeClient,
                onStartStream: { destination, streamKey in
                    Task { await startStreaming(destination: destination, streamKey: streamKey) }
                }
            )
        }
    }

    // MARK: - Studio Header

    private var studioHeader: some View {
        HStack(spacing: 16) {
            Spacer()

            // Center: Stream Status (when streaming)
            if streamViewModel.isStreaming {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(pulsing ? 1.0 : 0.5)
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                    Text(streamViewModel.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulsing = true
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Stage Composition View

    private var stageCompositionView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // Layer 1: Main stage background / Screen Share
                if enableScreen {
                    if let desktopImage = viewModel.desktopPreviewImage {
                        Image(nsImage: desktopImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Desktop Preview")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                    }
                } else if !studioState.isAudioOnly {
                    // Empty stage placeholder when no screen share
                    Color.black.opacity(0.3)
                }

                // Layer 2: Presenter PIP (Face/Avatar always in corner)
                if !studioState.isAudioOnly {
                    let pipWidth = geometry.size.width * 0.25
                    let pipHeight = pipWidth * (9 / 16)

                    presenterView
                        .frame(width: pipWidth, height: pipHeight)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .offset(x: -20, y: -20)
                        .offset(pipOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    pipOffset = CGSize(
                                        width: lastPipOffset.width + value.translation.width,
                                        height: lastPipOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastPipOffset = pipOffset
                                }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                // Audio-only mode visualization
                if studioState.isAudioOnly {
                    audioOnlyView
                }
            }
        }
    }

    @ViewBuilder
    private var presenterView: some View {
        if studioState.persona == .avatar {
            AvatarRecordView(viewModel: avatarViewModel, isTransparent: false)
                .background(Color.black)
        } else if studioState.persona == .face {
            if let image = previewStore.image(for: viewModel.currentPreviewSourceID) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .background(Color.black)
            } else {
                ZStack {
                    Color.black
                    VStack {
                        Image(systemName: "video.slash")
                        Text("No Camera")
                    }
                    .foregroundStyle(.gray)
                }
            }
        }
    }

    private var audioOnlyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
                .opacity(pulsing ? 1.0 : 0.5)
            Text("Audio Recording")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    // MARK: - Studio Control Bar

    private var studioControlBar: some View {
        HStack(spacing: 16) {
            // Left: Persona Selector (segmented)
            HStack(spacing: 4) {
                ForEach(Persona.allCases) { persona in
                    Button {
                        studioState.persona = persona
                    } label: {
                        Image(systemName: persona.icon)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(studioState.persona == persona ? Color.accentColor.opacity(0.3) : Color.clear)
                            .background(.regularMaterial)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(studioState.persona == persona ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(persona.rawValue)
                    .accessibilityIdentifier("Persona_\(persona.rawValue)")
                }
            }

            // Stage Toggles
            HStack(spacing: 8) {
                // Screen Toggle
                Button {
                    enableScreen.toggle()
                } label: {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14))
                        .padding(8)
                        .background(enableScreen ? Color.accentColor.opacity(0.2) : Color.clear)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(enableScreen ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Toggle_Screen")
                .help("Toggle Screen Share")

                // Mic Toggle
                Button {
                    viewModel.enableMicrophone.toggle()
                } label: {
                    Image(systemName: viewModel.enableMicrophone ? "mic.fill" : "mic.slash")
                        .font(.system(size: 14))
                        .padding(8)
                        .background(viewModel.enableMicrophone ? Color.accentColor.opacity(0.2) : Color.clear)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(viewModel.enableMicrophone ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Toggle_Mic")
                .help("Toggle Microphone")

                // Audio Level Meter
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule()
                        .fill(levelColor(for: viewModel.audioLevelPercentage()))
                        .frame(width: 40 * viewModel.audioLevelPercentage())
                        .animation(.linear(duration: 0.1), value: viewModel.audioLevelPercentage())
                }
                .frame(width: 40, height: 6)
                .opacity(viewModel.enableMicrophone ? 1.0 : 0.3)
            }

            Spacer()

            // Center: Dual Action Buttons (REC + LIVE)
            HStack(spacing: 12) {
                recordingActionButton
                streamingActionButton
            }

            Spacer()

            // Right: Recording Duration + Settings
            HStack(spacing: 12) {
                // Recording Duration
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRecording ? .red : .clear)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRecording ? viewModel.formattedDuration() : "00:00")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(viewModel.isRecording ? .primary : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .opacity(viewModel.isRecording ? 1.0 : 0.5)

                // Inspector Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showInspector.toggle()
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .padding(8)
                        .foregroundStyle(showInspector ? .primary : .secondary)
                        .background(showInspector ? Color.accentColor.opacity(0.2) : Color.clear)
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Toggle Inspector (⌘I)")
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private var recordingActionButton: some View {
        // Fixed-width container to prevent layout shifts
        HStack(spacing: 8) {
            if !viewModel.isRecording {
                // Start Recording button
                Button {
                    Task { await viewModel.startRecording() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle.fill")
                        Text("REC")
                    }
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(viewModel.canStartRecording ? Color.red : Color.gray)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessing || !viewModel.canStartRecording)
                .accessibilityIdentifier("Btn_Record")
            } else {
                // Pause/Resume button
                Button {
                    if viewModel.isPaused { viewModel.resumeRecording() }
                    else { viewModel.pauseRecording() }
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.body)
                        .frame(width: 16, height: 16)
                        .padding(8)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Stop button
                Button {
                    Task { await viewModel.stopRecording() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.body)
                        .frame(width: 16, height: 16)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Btn_Stop")
            }
        }
        .frame(width: 110)
    }

    private var streamingActionButton: some View {
        Button {
            if streamViewModel.isStreaming {
                Task { await stopStreaming() }
            } else {
                showStreamSetup = true
            }
        } label: {
            HStack(spacing: 6) {
                // Live indicator dot (always present for consistent width)
                Circle()
                    .fill(streamViewModel.isStreaming ? .white : .clear)
                    .frame(width: 8, height: 8)
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text(streamViewModel.isStreaming ? "END" : "LIVE")
            }
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                streamViewModel.isStreaming
                    ? AnyShapeStyle(Color.red)
                    : AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(streamViewModel.isConnecting)
        .accessibilityIdentifier("Btn_GoLive")
        .frame(width: 120)
    }

    // MARK: - Helpers

    private func syncViewModelState() {
        // Derive camera/desktop state from persona and screen toggle
        viewModel.enableCamera = studioState.enableCamera
        viewModel.enableDesktop = enableScreen

        if studioState.persona == .face {
            viewModel.bindPreviewStore(previewStore)
            // Refresh camera list and activate preview pipeline
            viewModel.refreshCameraDevices()
            try? viewModel.activatePreviewPipeline()
        } else {
            // Not in face mode - ensure camera preview is stopped
            viewModel.refreshCameraPreview()
        }

        if enableScreen {
            viewModel.refreshDesktopPreview()
        }
    }

    private func levelColor(for level: Double) -> Color {
        if level < 0.5 { .green } else if level < 0.8 { .yellow } else { .red }
    }

    // MARK: - Streaming

    private func startStreaming(destination: RTMPPublisher.Destination, streamKey: String) async {
        // Ensure we have an active session (either from recording or create one for streaming)
        if RecordingState.shared.recordingSession == nil {
            // Start a preview-mode session for streaming without recording
            await viewModel.startPreviewSession()
        }

        do {
            guard let session = RecordingState.shared.recordingSession else {
                streamViewModel.error = "Failed to create streaming session"
                return
            }
            try await session.startStreaming(to: destination, streamKey: streamKey)
            streamViewModel.isStreaming = true
        } catch {
            streamViewModel.error = error.localizedDescription
        }
    }

    private func stopStreaming() async {
        await streamViewModel.stopStreaming()
    }
}

// Preview requires YouTubeClient to be accessible
// #Preview {
//     NavigationStack {
//         RecordView(youtubeClient: YouTubeClient(clientId: "test", clientSecret: "test"))
//     }
// }
