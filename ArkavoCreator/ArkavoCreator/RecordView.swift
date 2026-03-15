import ArkavoKit
import ArkavoStreaming
import AVFoundation
import SwiftUI

struct RecordView: View {
    // MARK: - Properties

    @ObservedObject var youtubeClient: YouTubeClient
    @ObservedObject var twitchClient: TwitchAuthClient

    // MARK: - Private State

    @State private var viewModel = RecordViewModel()
    @State private var streamViewModel = StreamViewModel()
    @StateObject private var avatarViewModel = AvatarViewModel()
    @StateObject private var museAvatarViewModel = MuseAvatarViewModel()
    @State private var enableScreen: Bool = false
    @State private var showStreamSetup: Bool = false
    @State private var showInspector: Bool = false
    @State private var showChat: Bool = false
    @State private var chatViewModel = ChatPanelViewModel()
    @State private var pulsing: Bool = false
    @State private var pipOffset: CGSize = .zero
    @State private var lastPipOffset: CGSize = .zero
    // Scene state restoration
    @State private var preSceneMicEnabled: Bool = true
    @State private var preSceneVisualSource: VisualSource? = .face

    // Shared state (not part of init)
    @ObservedObject private var previewStore = CameraPreviewStore.shared
    private var studioState: StudioState { StudioState.shared }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Studio Header (thin separator only)
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)

            // MARK: - Main Stage + Inspector
            HStack(spacing: 0) {
                // Chat Panel (left side)
                if showChat {
                    ChatPanelView(viewModel: chatViewModel, isVisible: $showChat)
                        .transition(.move(edge: .leading))
                }

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

                    // Scene overlay (topmost layer)
                    if studioState.isSceneOverlayActive {
                        SceneOverlayView(scene: studioState.activeScene)
                    }
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
            } else if studioState.visualSource == .avatar || studioState.visualSource == .muse {
                // Avatar/Muse mode needs remote camera bridge for face tracking metadata
                try? viewModel.activatePreviewPipeline()
            }
            // Load saved stream key for current platform
            streamViewModel.loadStreamKey()
        }
        .onChange(of: studioState.visualSource) { _, _ in syncViewModelState() }
        .onChange(of: enableScreen) { _, _ in syncViewModelState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            Task { await viewModel.cleanup() }
        }
        .sheet(isPresented: $showStreamSetup) {
            StreamDestinationPicker(
                streamViewModel: streamViewModel,
                youtubeClient: youtubeClient,
                twitchClient: twitchClient,
                onStartStream: { destination, streamKey in
                    Task { await startStreaming(destination: destination, streamKey: streamKey) }
                }
            )
        }
    }

    // MARK: - Studio Header

    private var studioHeader: some View {
        // Minimal header — stream status is shown in the bottom control bar
        HStack(spacing: 16) {
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
                } else if !studioState.isAudioOnly && studioState.visualSource != .avatar && studioState.visualSource != .muse {
                    // Empty stage placeholder when no screen share (but not in avatar/muse mode)
                    stagePlaceholderView
                }

                // Layer 2: Visual source overlay
                if studioState.visualSource == .avatar || studioState.visualSource == .muse {
                    if enableScreen {
                        // PiP mode over screen: Transparent overlay with drop shadow
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
                    } else {
                        // Full stage mode: Avatar fills the entire stage with background
                        AvatarRecordView(viewModel: avatarViewModel, isTransparent: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

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

                // Audio-only mode visualization (only when mic is on and no screen share)
                if studioState.isAudioOnly && !enableScreen && viewModel.enableMicrophone {
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
                ForEach(VisualSource.availableSources) { source in
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

            audioAndSceneControls

            Spacer()

            // Center: Dual Action Buttons (REC + LIVE)
            HStack(spacing: 12) {
                recordingActionButton
                streamingActionButton
            }

            Spacer()

            // Right: Recording Duration + Settings
            HStack(spacing: 12) {
                // Duration (recording or streaming)
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRecording ? .red : (streamViewModel.isStreaming ? .purple : .clear))
                        .frame(width: 8, height: 8)
                    Text(activeDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .opacity(isActive ? 1.0 : 0.5)

                // Chat Toggle (Twitch only)
                if streamViewModel.selectedPlatform == .twitch {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showChat.toggle()
                        }
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 14))
                            .padding(8)
                            .foregroundStyle(showChat ? .primary : .secondary)
                            .background(showChat ? Color.accentColor.opacity(0.2) : Color.clear)
                            .background(.regularMaterial)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Chat Panel")
                }

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

    private var audioAndSceneControls: some View {
        HStack(spacing: 8) {
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

            // Desktop Audio Toggle
            Button {
                viewModel.toggleDesktopAudio()
            } label: {
                Image(systemName: viewModel.enableDesktopAudio ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 14))
                    .padding(8)
                    .background(viewModel.enableDesktopAudio ? Color.accentColor.opacity(0.2) : Color.clear)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.enableDesktopAudio ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Toggle_DesktopAudio")
            .help("Toggle Desktop Audio")

            // Scene Picker
            Menu {
                ForEach(ScenePreset.allCases) { scene in
                    Button {
                        switchScene(to: scene)
                    } label: {
                        Label(scene.rawValue, systemImage: scene.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: studioState.activeScene.icon)
                        .font(.system(size: 14))
                    if studioState.isSceneOverlayActive {
                        Text(studioState.activeScene.rawValue)
                            .font(.caption.weight(.medium))
                    }
                }
                .padding(8)
                .background(studioState.isSceneOverlayActive ? Color.orange.opacity(0.3) : Color.clear)
                .background(.regularMaterial)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(studioState.isSceneOverlayActive ? Color.orange : Color.clear, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Scene Presets")
        }
    }

    private var recordingActionButton: some View {
        // Fixed-width container to prevent layout shifts
        HStack(spacing: 8) {
            if !viewModel.isRecording {
                // Start Recording button — gray/subtle when idle (save to disk)
                Button {
                    Task {
                        // Set up avatar texture provider before recording starts
                        if studioState.enableAvatar {
                            viewModel.avatarTextureProvider = avatarViewModel.getTextureProvider()
                        }
                        if studioState.enableMuse {
                            viewModel.museTextureProvider = museAvatarViewModel.getTextureProvider()
                            if let audioSource = museAvatarViewModel.getAudioSource() {
                                viewModel.recordingSession?.addMuseAudioSource(audioSource)
                            }
                        }
                        await viewModel.startRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.canStartRecording ? Color.red : Color.gray)
                            .frame(width: 10, height: 10)
                        Text("REC")
                    }
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .foregroundColor(viewModel.canStartRecording ? .primary : .secondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
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
        viewModel.enableAvatar = studioState.enableAvatar || studioState.enableMuse
        viewModel.enableDesktop = enableScreen

        if studioState.visualSource == .face {
            viewModel.bindPreviewStore(previewStore)
            // Refresh camera list and activate preview pipeline
            viewModel.refreshCameraDevices()
            try? viewModel.activatePreviewPipeline()
        } else if studioState.visualSource == .avatar || studioState.visualSource == .muse {
            // Avatar/Muse mode needs remote camera bridge for face tracking metadata
            try? viewModel.activatePreviewPipeline()
        } else {
            // Audio-only mode - ensure camera preview is stopped
            viewModel.refreshCameraPreview()
        }

        if enableScreen {
            viewModel.refreshDesktopPreview()
        }
    }

    private var isActive: Bool {
        viewModel.isRecording || streamViewModel.isStreaming
    }

    private var activeDuration: String {
        if viewModel.isRecording {
            return viewModel.formattedDuration()
        } else if streamViewModel.isStreaming {
            return streamViewModel.formattedDuration
        }
        return "00:00"
    }

    private func levelColor(for level: Double) -> Color {
        if level < 0.5 { .green } else if level < 0.8 { .yellow } else { .red }
    }

    // MARK: - Scene Switching

    private func switchScene(to scene: ScenePreset) {
        let currentScene = studioState.activeScene

        if scene != .live && currentScene == .live {
            // Leaving live — save current state
            preSceneMicEnabled = viewModel.enableMicrophone
            preSceneVisualSource = studioState.visualSource
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            studioState.activeScene = scene
        }

        if scene == .live {
            // Returning to live — restore saved state
            viewModel.enableMicrophone = preSceneMicEnabled
            if let source = preSceneVisualSource {
                if studioState.visualSource != source {
                    studioState.visualSource = source
                }
            }
        } else {
            // Non-live scene — apply scene settings
            if scene.muteMic {
                viewModel.enableMicrophone = false
            }
        }

        // Update compositor scene overlay so it renders into the stream
        updateSceneOverlay(scene)
    }

    private func updateSceneOverlay(_ scene: ScenePreset) {
        guard let session = viewModel.recordingSession ?? RecordingState.shared.recordingSession else { return }

        if scene == .live {
            session.sceneOverlayText = nil
            session.sceneOverlayIcon = nil
            session.sceneOverlayGradientColors = nil
        } else {
            session.sceneOverlayText = scene.overlayText
            session.sceneOverlayIcon = scene.icon
            // Map scene gradient colors to CGColors
            switch scene {
            case .startingSoon:
                session.sceneOverlayGradientColors = (
                    start: CGColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 0.85),
                    end: CGColor(red: 0.5, green: 0.0, blue: 0.8, alpha: 0.85)
                )
            case .brb:
                session.sceneOverlayGradientColors = (
                    start: CGColor(red: 0.9, green: 0.5, blue: 0.0, alpha: 0.85),
                    end: CGColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 0.85)
                )
            case .ending:
                session.sceneOverlayGradientColors = (
                    start: CGColor(red: 0.3, green: 0.0, blue: 0.5, alpha: 0.85),
                    end: CGColor(red: 0.5, green: 0.0, blue: 0.8, alpha: 0.85)
                )
            default:
                session.sceneOverlayGradientColors = nil
            }
        }
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
            streamViewModel.startStatisticsPolling()

            // Auto-connect Twitch chat
            if streamViewModel.selectedPlatform == .twitch {
                chatViewModel.connect(twitchClient: twitchClient)
                withAnimation { showChat = true }
            }
        } catch {
            streamViewModel.error = error.localizedDescription
        }
    }

    private func stopStreaming() async {
        chatViewModel.disconnect()
        showChat = false
        await streamViewModel.stopStreaming()
    }
}

// Preview requires YouTubeClient to be accessible
// #Preview {
//     NavigationStack {
//         RecordView(youtubeClient: YouTubeClient(clientId: "test", clientSecret: "test"))
//     }
// }
