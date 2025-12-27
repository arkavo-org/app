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
    @ObservedObject private var previewStore = CameraPreviewStore.shared
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
                        visualSource: studioState.visualSource,
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
            if studioState.visualSource == .face {
                viewModel.bindPreviewStore(previewStore)
                try? viewModel.activatePreviewPipeline()
            } else if studioState.visualSource == .avatar {
                // Avatar mode needs remote camera bridge for face tracking metadata
                try? viewModel.activatePreviewPipeline()
            }
            // Load saved stream key for current platform
            streamViewModel.loadStreamKey()
        }
        .onChange(of: studioState.visualSource) { _, _ in syncViewModelState() }
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
                        .foregroundStyle(.primary.opacity(0.7))
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
                                .foregroundStyle(.primary.opacity(0.7))
                            Text("Desktop Preview")
                                .font(.title3)
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                    }
                } else if !studioState.isAudioOnly {
                    // Empty stage placeholder when no screen share
                    stagePlaceholderView
                }

                // Layer 2: Visual source overlay
                if studioState.visualSource == .avatar {
                    // VTuber-style: Large transparent overlay with drop shadow
                    let avatarWidth = geometry.size.width * 0.4
                    let avatarHeight = avatarWidth * (16 / 9)  // Taller aspect for waist-up

                    AvatarRecordView(viewModel: avatarViewModel, isTransparent: true)
                        .frame(width: avatarWidth, height: avatarHeight)
                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
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

                } else if studioState.visualSource == .face {
                    // Traditional PIP: Boxed camera feed (or floating head when enabled)
                    let pipWidth = geometry.size.width * 0.25
                    let pipHeight = pipWidth * (9 / 16)

                    facePIPView
                        .frame(width: pipWidth, height: pipHeight)
                        // Skip cornerRadius when floating head is enabled (person shape is the border)
                        .cornerRadius(viewModel.floatingHeadEnabled ? 0 : 12)
                        .shadow(radius: viewModel.floatingHeadEnabled ? 5 : 10)
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
    private var facePIPView: some View {
        if let image = previewStore.image(for: viewModel.currentPreviewSourceID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                // Use clear background when floating head is enabled to show transparency
                .background(viewModel.floatingHeadEnabled ? Color.clear : Color.black)
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

    private var audioOnlyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 80))
                .foregroundStyle(.primary.opacity(0.7))
                .opacity(pulsing ? 1.0 : 0.5)
            Text("Audio Recording")
                .font(.title2)
                .foregroundStyle(.primary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    private var stagePlaceholderView: some View {
        VStack(spacing: 16) {
            // Show available screens as icons
            HStack(spacing: 12) {
                ForEach(viewModel.availableScreens) { screen in
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 36))
                                .foregroundStyle(.primary.opacity(0.5))

                            // Primary indicator
                            if screen.isPrimary {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)
                                    .offset(x: 4, y: -4)
                            }
                        }
                        Text(screen.name)
                            .font(.caption2)
                            .foregroundStyle(.primary.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }

            Text("Select a Screen Below")
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.7))
            Text("Or record with just your camera")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Studio Control Bar

    private var studioControlBar: some View {
        HStack(spacing: 16) {
            // Left: Visual Source Toggle (Face/Avatar - both can be off for audio-only)
            HStack(spacing: 4) {
                ForEach(VisualSource.allCases) { source in
                    let isSelected = studioState.visualSource == source
                    Button {
                        studioState.toggleVisualSource(source)
                    } label: {
                        Image(systemName: source.icon)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                            .background(.regularMaterial)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isSelected ? "Disable \(source.rawValue)" : "Enable \(source.rawValue)")
                    .accessibilityIdentifier("Source_\(source.rawValue)")
                }
            }

            // Screen Selection
            HStack(spacing: 4) {
                ForEach(viewModel.availableScreens) { screen in
                    let isSelected = enableScreen && viewModel.selectedScreenID == screen.displayID
                    Button {
                        if isSelected {
                            // Deselect (turn off screen share)
                            enableScreen = false
                        } else {
                            // Select this screen
                            viewModel.selectScreen(screen)
                            enableScreen = true
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: isSelected ? "rectangle.inset.filled.on.rectangle" : "desktopcomputer")
                                .font(.system(size: 14))
                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                .padding(8)
                                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                                .background(.regularMaterial)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                )

                            // Primary screen indicator (star badge)
                            if screen.isPrimary {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 5))
                                            .foregroundColor(.black)
                                    )
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Screen_\(screen.id)")
                    .help(screen.isPrimary ? "\(screen.name) (Primary)" : screen.name)
                }
            }

            // Mic Toggle + Audio Meter
            HStack(spacing: 8) {
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

                // Audio Level Meter (green gradient)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
                    Task {
                        // Set up avatar texture provider before recording starts
                        if studioState.enableAvatar {
                            viewModel.avatarTextureProvider = avatarViewModel.getTextureProvider()
                        }
                        await viewModel.startRecording()
                    }
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
        // Derive camera/desktop state from visual source and screen toggle
        viewModel.enableCamera = studioState.enableCamera
        viewModel.enableAvatar = studioState.enableAvatar
        viewModel.enableDesktop = enableScreen

        if studioState.visualSource == .face {
            viewModel.bindPreviewStore(previewStore)
            // Refresh camera list and activate preview pipeline
            viewModel.refreshCameraDevices()
            try? viewModel.activatePreviewPipeline()
        } else if studioState.visualSource == .avatar {
            // Avatar mode needs remote camera bridge for face tracking metadata
            try? viewModel.activatePreviewPipeline()
        } else {
            // Audio-only mode - ensure camera preview is stopped
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

            // Check if this is Arkavo (NTDF-encrypted streaming)
            if streamViewModel.selectedPlatform == .arkavo {
                guard let kasURL = URL(string: "https://100.arkavo.net") else {
                    streamViewModel.error = "Invalid KAS URL"
                    return
                }
                try await session.startNTDFStreaming(
                    kasURL: kasURL,
                    rtmpURL: destination.url,
                    streamKey: "live/creator"
                )
            } else {
                try await session.startStreaming(to: destination, streamKey: streamKey)
            }
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
