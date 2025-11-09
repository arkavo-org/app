import ArkavoRecorder
import ArkavoSocial
import AVFoundation
import CryptoKit
import FlatBuffers
import SwiftData
import SwiftUI

// MARK: - Main View

struct VideoCreateView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: VideoRecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var videoDescription: String = ""

    init(feedViewModel _: VideoFeedViewModel) {
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeViewModel())
    }

    var body: some View {
        ModernRecordingInterface(
            viewModel: viewModel,
            videoDescription: $videoDescription,
            onComplete: { _ in
                // Simply dismiss the view when complete
                sharedState.showCreateView = false
            },
        )
        .alert("Recording Error", isPresented: $showError) {
            Button("OK") {
                sharedState.showCreateView = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showError = newValue != nil
        }
    }

    @MainActor
    private func exportVideo(
        asset: AVURLAsset,
        toURL: URL,
        settings _: [String: Any],
        originalTransform _: CGAffineTransform
    ) async throws -> Data {
        guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.compressionFailed("Failed to get video track")
        }

        // Create composition with portrait dimensions
        let composition = AVMutableComposition()
        composition.naturalSize = CGSize(width: 1080, height: 1920)

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid,
        ) else {
            throw VideoError.compressionFailed("Failed to create composition track")
        }

        // Insert the video track
        try await compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.load(.duration)),
            of: assetTrack,
            at: .zero,
        )

        // Create video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.renderSize = CGSize(width: 1080, height: 1920)
        videoComposition.renderScale = 1.0

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)

        // Calculate correct transform
        var transform = CGAffineTransform.identity

        // First translate to center the video
        transform = transform.translatedBy(x: 1080, y: 0)

        // Then rotate 90 degrees clockwise
        transform = transform.rotated(by: .pi / 2)

        // Set the transform for the entire duration
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Configure export session
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality, // Changed to highest quality
        ) else {
            throw VideoError.exportSessionCreationFailed("Failed to create export session")
        }

        exporter.outputURL = toURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true

        // Perform export
        try await exporter.export(to: toURL, as: .mp4)

        // Load and return data
        return try Data(contentsOf: toURL)
    }

    // Helper function to determine the correct render size
    private func determineRenderSize(
        naturalSize: CGSize,
        transform: CGAffineTransform
    ) -> CGSize {
        // If the transform suggests a 90 or 270-degree rotation, swap width and height
        if abs(transform.a) < 0.1 {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }

    // Helper function to determine the correct transform
    private func determineCorrectedTransform(
        originalTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        var correctedTransform = originalTransform

        // Check if the original transform suggests a 90 or 270-degree rotation
        if abs(correctedTransform.a) < 0.1 {
            // Adjust the translation to center the video
            correctedTransform.tx = renderSize.height
            correctedTransform.ty = 0
        }

        // Ensure no unintended scaling
        correctedTransform.a = 1.0 // Scale X
        correctedTransform.d = 1.0 // Scale Y

        // Apply the rotation based on the original transform
        if originalTransform.b == 1.0, originalTransform.c == -1.0 {
            // 90-degree rotation (portrait)
            correctedTransform = correctedTransform.rotated(by: .pi / 2)
        } else if originalTransform.b == -1.0, originalTransform.c == 1.0 {
            // 270-degree rotation (portrait upside down)
            correctedTransform = correctedTransform.rotated(by: -.pi / 2)
        }

        return correctedTransform
    }

    //         correctedTransform.tx += renderSize.width * 0.2 // Adjust the multiplier to control the shift amount
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Preview View Wrapper

struct PreviewViewWrapper: UIViewRepresentable {
    @ObservedObject var viewModel: VideoRecordingViewModel

    func makeUIView(context _: Context) -> UIView {
        let previewView = UIView()
        previewView.backgroundColor = .black

        Task {
            await viewModel.setup(previewView: previewView)
        }

        return previewView
    }

    func updateUIView(_: UIView, context _: Context) {
        // No updates needed
    }
}

// MARK: - Modern Recording Interface

struct ModernRecordingInterface: View {
    @ObservedObject var viewModel: VideoRecordingViewModel
    @Binding var videoDescription: String
    let onComplete: (UploadResult?) async -> Void

    var body: some View {
        ZStack {
            // Camera Preview
            PreviewViewWrapper(viewModel: viewModel)
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.3),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                    .ignoresSafeArea()
                }

            VStack {
                TextField("Add a description...", text: $videoDescription)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .background(.ultraThinMaterial)

                StreamingCard(streamer: viewModel.remoteStreamer)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 32) {
                    ProgressBar(progress: viewModel.recordingProgress)
                        .frame(height: 3)
                        .padding(.horizontal)

                    ZStack {
                        RecordingControl(
                            viewModel: viewModel,
                            description: videoDescription,
                            onComplete: onComplete,
                        )

                        HStack {
                            FlipCameraButton {
                                viewModel.flipCamera()
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - Supporting Views

struct FlipCameraButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.rotate")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

struct StreamingCard: View {
    @ObservedObject var streamer: RemoteCameraStreamer
    @State private var showDeveloperMode = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var longPressTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Main smart button
            Button(action: handleTap) {
                VStack(spacing: 12) {
                    // Icon that changes based on state
                    ZStack {
                        Image(systemName: iconName)
                            .font(.system(size: 48))
                            .foregroundStyle(iconColor)
                            .symbolEffect(.pulse, isActive: isAnimating)

                        if showProgress {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        }
                    }

                    // Title that adapts to connection state
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Subtitle with mode info when streaming
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .buttonStyle(.plain)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(borderColor, lineWidth: 2)
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 3.0)
                    .onEnded { _ in
                        showDeveloperMode = true
                    }
            )

            // Developer mode (expandable)
            if showDeveloperMode {
                DeveloperModeView(streamer: streamer, onClose: {
                    withAnimation {
                        showDeveloperMode = false
                    }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .alert("Connection Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: streamer.connectionState) { _, newState in
            if case .failed(let error) = newState {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    // MARK: - Actions

    private func handleTap() {
        switch streamer.connectionState {
        case .idle, .failed:
            Task {
                await streamer.smartConnect()
            }
        case .streaming:
            Task {
                await streamer.smartDisconnect()
            }
        case .discovering, .connecting:
            // Do nothing during transitional states
            break
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch streamer.connectionState {
        case .idle:
            return "play.circle.fill"
        case .discovering:
            return "wifi.circle"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .streaming:
            return "video.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch streamer.connectionState {
        case .idle:
            return .blue
        case .discovering, .connecting:
            return .orange
        case .streaming:
            return .green
        case .failed:
            return .red
        }
    }

    private var title: String {
        switch streamer.connectionState {
        case .idle:
            return "Stream to ArkavoCreator"
        case .discovering:
            return "Finding Mac..."
        case .connecting(let macName):
            return "Connecting to \(macName)..."
        case .streaming:
            return "Streaming Active"
        case .failed:
            return "Connection Failed"
        }
    }

    private var subtitle: String? {
        switch streamer.connectionState {
        case .idle:
            return "Tap to connect automatically"
        case .streaming:
            if let mode = streamer.autoDetectedMode {
                return "\(mode == .face ? "Face" : "Body") Tracking"
            }
            return nil
        case .failed(let error):
            return error.recoverySuggestion
        default:
            return nil
        }
    }

    private var showProgress: Bool {
        switch streamer.connectionState {
        case .discovering, .connecting:
            return true
        default:
            return false
        }
    }

    private var isAnimating: Bool {
        switch streamer.connectionState {
        case .streaming:
            return true
        default:
            return false
        }
    }

    private var buttonBackground: some View {
        Group {
            switch streamer.connectionState {
            case .idle:
                Color.blue.opacity(0.1)
            case .streaming:
                Color.green.opacity(0.2)
            case .failed:
                Color.red.opacity(0.2)
            default:
                Color.clear
            }
        }
    }

    private var borderColor: Color {
        switch streamer.connectionState {
        case .streaming:
            return .green
        case .failed:
            return .red
        default:
            return .clear
        }
    }
}

// MARK: - Developer Mode View

struct DeveloperModeView: View {
    @ObservedObject var streamer: RemoteCameraStreamer
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Developer Mode")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Manual host entry
            VStack(alignment: .leading, spacing: 6) {
                Text("Manual Connection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Mac Hostname or IP", text: $streamer.host)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Port", text: Binding(
                        get: { streamer.port },
                        set: { newValue in
                            let digits = newValue.filter { $0.isNumber }
                            streamer.port = String(digits.prefix(5))
                        }
                    ))
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                }
            }

            // Mode picker
            VStack(alignment: .leading, spacing: 6) {
                Text("ARKit Mode")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: $streamer.mode) {
                    Text("Face").tag(ARKitCaptureManager.Mode.face)
                    Text("Body").tag(ARKitCaptureManager.Mode.body)
                }
                .pickerStyle(.segmented)
            }

            // Discovered servers
            if !streamer.discoveredServers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discovered Servers")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(streamer.discoveredServers) { server in
                        Button {
                            streamer.selectServer(server)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("\(server.host):\(server.port)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if streamer.host == server.host, streamer.port == "\(server.port)" {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // Manual toggle button
            Button {
                streamer.toggleStreaming()
            } label: {
                Label(
                    streamer.state == .streaming ? "Stop Manual Stream" : "Start Manual Stream",
                    systemImage: "play.fill"
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // NFC button
            #if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
            Button {
                streamer.scanWithNFC()
            } label: {
                Label("Scan via NFC", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #endif

            // Debug info
            VStack(alignment: .leading, spacing: 4) {
                Text("Debug Info")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Text("State: \(String(describing: streamer.state))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Status: \(streamer.statusMessage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RecordingControl: View {
    @ObservedObject var viewModel: VideoRecordingViewModel
    let description: String
    let onComplete: (UploadResult?) async -> Void

    var body: some View {
        Group {
            switch viewModel.recordingState {
            case .initial:
                ProgressView()
                    .tint(.white)

            case .setupComplete:
                ModernRecordButton(isRecording: false) {
                    Task {
                        await viewModel.startRecording()
                    }
                }

            case .recording:
                ModernRecordButton(isRecording: true) {
                    Task {
                        await viewModel.stopRecording(description: description)
                    }
                }

            case .processing, .uploading:
                ProcessingView(state: viewModel.recordingState)

            case .complete:
                // Automatically trigger completion
                ProgressView()
                    .tint(.white)
                    .onAppear {
                        Task {
                            await onComplete(nil)
                        }
                    }

            case .error:
                EmptyView()
            }
        }
    }
}

struct ModernRecordButton: View {
    var isRecording: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 84, height: 84)

                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 84, height: 84)
                    .opacity(isRecording ? 1 : 0)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 40)
                    .fill(.red)
                    .frame(width: isRecording ? 36 : 72,
                           height: isRecording ? 36 : 72)
            }
            .animation(.spring(response: 0.3), value: isRecording)
        }
    }
}

struct ProcessingView: View {
    let state: RecordingState

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text(state == .processing ? "Processing..." : "Uploading...")
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SendButton: View {
    enum SendState {
        case ready
        case processing
        case sending
        case complete
    }

    let state: SendState
    let action: () -> Void

    @State private var isPressed = false
    @State private var showText = true
    @State private var iconOffset: CGFloat = 0

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                isPressed = true
                showText = false
            }

            // Small delay before triggering the action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                action()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.body)
                    .offset(x: iconOffset)
                    .opacity(state == .processing ? 0 : 1)

                if showText, state == .ready {
                    Text("Send")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else if state == .processing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                        .transition(.opacity)
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(.white.opacity(0.2))
                    },
            )
        }
        .disabled(state != .ready)
        .onChange(of: state) { oldValue, newValue in
            if oldValue == .sending, newValue == .complete {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    iconOffset = 30
                }
            }
        }
    }
}

struct ProgressBar: View {
    var progress: CGFloat

    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.15))
                    .overlay {
                        // Subtle shine effect
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.1),
                                        .clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom,
                                ),
                            )
                    }

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1, green: 0, blue: 0.3), // Bright pink-red
                                Color(red: 1, green: 0.2, blue: 0), // Orange-red
                                Color.red, // Standard red
                            ],
                            startPoint: .leading,
                            endPoint: .trailing,
                        ),
                    )
                    .frame(width: geometry.size.width * progress)
                    .overlay {
                        // Animated shine effect
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.4),
                                        .clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing,
                                ),
                            )
                            .frame(width: 20)
                            .offset(x: isAnimating ? geometry.size.width : -20)
                            .opacity(progress > 0 ? 1 : 0)
                    }
                    .mask {
                        RoundedRectangle(cornerRadius: 2)
                    }
            }
            .onChange(of: progress) { oldValue, newValue in
                if oldValue == 0, newValue > 0 {
                    // Start animation when recording begins
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                } else if newValue == 0 {
                    // Stop animation when recording ends
                    isAnimating = false
                }
            }
        }
        .shadow(color: .red.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Recording States

enum RecordingState: Equatable {
    case initial
    case setupComplete
    case recording
    case processing
    case uploading
    case complete(UploadResult)
    case error(String)

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial),
             (.setupComplete, .setupComplete),
             (.recording, .recording),
             (.processing, .processing),
             (.uploading, .uploading):
            true
        case let (.complete(lhsResult), .complete(rhsResult)):
            lhsResult.id == rhsResult.id
        case let (.error(lhsError), .error(rhsError)):
            lhsError == rhsError
        default:
            false
        }
    }
}

// MARK: - View Model

@MainActor
final class VideoRecordingViewModel: ViewModel, ObservableObject {
    // MARK: - Properties

    let client: ArkavoClient
   let account: Account
   let profile: Profile
    let remoteStreamer = RemoteCameraStreamer()

    @Published private(set) var recordingState: RecordingState = .initial
    @Published private(set) var recordingProgress: CGFloat = 0
    @Published private(set) var previewLayer: CALayer?
    @Published private(set) var errorMessage: String?

    private var recordingManager: VideoRecordingManager?
    private let processingManager = HLSProcessingManager()
    private var progressTimer: Timer?

    // MARK: - Initialization

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
    }

    // MARK: - Setup

    func setup(previewView: UIView) async {
        do {
            recordingManager = try await VideoRecordingManager()
            recordingState = .setupComplete
            previewLayer = recordingManager?.startPreview(in: previewView)
        } catch {
            print("❌ Recording setup failed with error: \(error.localizedDescription)")
            recordingState = .error(error.localizedDescription)
        }
    }

    // MARK: - Recording Controls

    @MainActor
    func startRecording() async {
        guard let recordingManager else { return }

        do {
            recordingState = .recording
            startProgressTimer()

            let videoURL = try await recordingManager.startRecording()
            print("📹 Started recording to: \(videoURL)")
        } catch {
            print("❌ Recording start failed with error: \(error.localizedDescription)")
            recordingState = .error(error.localizedDescription)
        }
    }

    @MainActor
    func stopRecording(description: String) async {
        guard let recordingManager else { return }

        do {
            progressTimer?.invalidate()
            try await recordingManager.stopRecording()

            // Process the video
            recordingState = .processing
            guard let videoURL = recordingManager.currentVideoURL else {
                throw VideoError.processingFailed("No video URL available")
            }

            let processedVideo = try await processingManager.processVideo(at: videoURL)

            // Upload the video
            recordingState = .uploading

            // First create the result
            let result = UploadResult(
                id: processedVideo.directory.lastPathComponent,
                playbackURL: videoURL.absoluteString,
            )

            // Handle all the processing and uploading
            try await handleRecordingComplete(result, description: description)

            // Only transition to complete state after everything is done
            await MainActor.run {
                recordingState = .complete(result)
            }
        } catch {
            print("❌ Recording stop failed with error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            recordingState = .error(error.localizedDescription)
        }
    }

    func flipCamera() {
        // Implementation for camera flip functionality
        // This would interact with the AVCaptureDevice to switch between front and back cameras
    }

    func createThoughtWithPolicy(videoData: Data, metadata: Thought.Metadata) async throws -> Thought {
        // Start with a new builder for metadata
        var builder = FlatBufferBuilder(initialSize: 512)
        print("Starting FlatBuffer construction...")

        // 1. Create rating
        let rating = Arkavo_Rating.createRating(
            &builder,
            violent: .mild,
            sexual: .none_,
            profane: .none_,
            substance: .none_,
            hate: .none_,
            harm: .none_,
            mature: .none_,
            bully: .none_,
        )
        print("📊 Rating created at offset: \(rating.o)")

        // 2. Create purpose
        let purpose = Arkavo_Purpose.createPurpose(
            &builder,
            educational: 0.2,
            entertainment: 0.8,
            news: 0.0,
            promotional: 0.0,
            personal: 0.0,
            opinion: 0.0,
            transactional: 0.0,
            harmful: 0.0,
            confidence: 0.9,
        )
        print("🎯 Purpose created at offset: \(purpose.o)")

        // 3. Create format info
        let versionString = builder.create(string: "H.265")
        let profileString = builder.create(string: "HEVC")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
            &builder,
            type: .plain,
            versionOffset: versionString,
            profileOffset: profileString,
        )
        print("📄 Format info created at offset: \(formatInfo.o)")

        // 4. Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: .video,
            dataEncoding: .binary,
            formatOffset: formatInfo,
        )
        print("📦 Content format created at offset: \(contentFormat.o)")

        let thoughtUUID = UUID()
        let thoughtPublicID = VideoRecordingViewModel.generatePublicID(from: thoughtUUID)
        // 5. Create vectors
        let idVector = builder.createVector(bytes: thoughtPublicID)
        print("🔑 ID vector created, size: \(metadata.creatorPublicID.base58EncodedString)")
        let creatorVector = builder.createVector(bytes: metadata.creatorPublicID)
        print("🔑 ID vector created, size: \(metadata.creatorPublicID.base58EncodedString)")
        let relatedVector = builder.createVector(bytes: metadata.streamPublicID)
        print("🔗 Related vector created, size: \(metadata.streamPublicID.base58EncodedString)")

        let topicsVector = builder.createVector([UInt32]())
        print("📝 Topics vector created")

        // 6. Start metadata creation
        let start = Arkavo_Metadata.startMetadata(&builder)

        // Add all fields
        Arkavo_Metadata.add(created: Int64(Date().timeIntervalSince1970), &builder)
        Arkavo_Metadata.addVectorOf(id: idVector, &builder)
        Arkavo_Metadata.addVectorOf(related: relatedVector, &builder)
        Arkavo_Metadata.addVectorOf(creator: creatorVector, &builder)
        Arkavo_Metadata.add(rating: rating, &builder)
        Arkavo_Metadata.add(purpose: purpose, &builder)
        Arkavo_Metadata.addVectorOf(topics: topicsVector, &builder)
        Arkavo_Metadata.add(content: contentFormat, &builder)

        // End metadata
        let arkMetadata = Arkavo_Metadata.endMetadata(&builder, start: start)
        print("📋 Metadata created at offset: \(arkMetadata.o)")

        // 7. Finish the buffer
        builder.finish(offset: arkMetadata)
        print("🏁 Builder finished")

        // Now verify the finished buffer
        do {
            var verificationBuffer = ByteBuffer(data: builder.data)
            var verifier = try Verifier(buffer: &verificationBuffer)

            // Get the root offset from the buffer
            let rootOffset = verificationBuffer.read(def: Int32.self, position: 0)
//            print("🔍 Root offset: \(rootOffset)")

            // Verify the root object
            try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)
//            print("✅ Metadata verification successful")
        } catch {
            print("❌ Metadata verification failed: \(error)")
            throw FlatBufferVerificationError.verificationFailed("Invalid metadata structure: \(error)")
        }

        // Get the final bytes
        let bytes = builder.sizedBuffer
        let policyData = Data(bytes: bytes.memory.advanced(by: bytes.reader), count: Int(bytes.size))
//        print("📦 Final policy data size: \(policyData.count) bytes")

        // Create NanoTDF with metadata in policy
        let nanoTDFData = try await client.encryptAndSendPayload(
            payload: videoData,
            policyData: policyData,
        )

        return Thought(
            id: thoughtUUID,
            nano: nanoTDFData,
            metadata: metadata, // This is now redundant since it's in the policy
        )
    }

    private static func generatePublicID(from uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid) { buffer in
            Data(SHA256.hash(data: buffer))
        }
    }

    private func handleRecordingComplete(_ result: UploadResult?, description: String) async throws {
        guard var result else {
            throw VideoError.processingFailed("Failed to get recording result")
        }

        // Account for NanoTDF overhead - target ~950KB for the video
        let videoTargetSize = 950_000 // Leave ~100KB for NanoTDF overhead

        let videoURL = URL(string: result.playbackURL)!
        let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = resourceValues.fileSize ?? 0

        print("Original video size: \(fileSize) bytes")

        // Analyze the original video
        let asset = AVURLAsset(url: videoURL)
        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let videoAngle = atan2(transform.b, transform.a)

            print("\n📹 Original Video Analysis:")
            print("- File size: \(fileSize) bytes")
            print("- Natural size: \(naturalSize)")
            print("- Aspect ratio: \(naturalSize.width / naturalSize.height)")
            print("- Transform angle: \(videoAngle * 180 / .pi)°")
            print("- Transform matrix: \(transform)")
        }

        // Compress video with optimized settings
        let compressedData = try await compressVideo(url: videoURL, description: description, targetSize: videoTargetSize)
        print("Compressed video size: \(compressedData.count) bytes")

        // Process video metadata and save
        let persistenceController = PersistenceController.shared
        let context = persistenceController.container.mainContext

        // Find video stream
        guard let videoStream = account.streams.first(where: { stream in
            stream.source?.metadata.mediaType == .video
        }) else {
            throw VideoError.processingFailed("No video stream available")
        }

        let contributor = Contributor(profilePublicID: profile.publicID, role: "creator")

//        print("handleRecordingComplete profile.publicID \(profile.publicID.base58EncodedString)")
        // Create metadata
        let metadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: videoStream.publicID,
            mediaType: .video,
            createdAt: Date(),
            contributors: [contributor],
        )

        // Create thought with policy and encrypted data
        let videoThought = try await createThoughtWithPolicy(
            videoData: compressedData,
            metadata: metadata,
        )
        result.nano = videoThought.nano

        // Verify NanoTDF size before sending
        guard videoThought.nano.count <= 1_000_000 else {
            throw NSError(domain: "VideoCompression", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Final NanoTDF too large for websocket"])
        }

        // Send the same NanoTDF over websocket
        try await client.sendNATSMessage(videoThought.nano)

        videoStream.addThought(videoThought)
        try context.save()
    }

    // MARK: - Private Helpers

    private func compressVideo(url: URL, description: String, targetSize: Int) async throws -> Data {
        let asset = AVURLAsset(url: url)

        // Try different export presets in order of decreasing quality
        let presets = [
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPreset960x540,
            AVAssetExportPresetLowQuality,
            AVAssetExportPreset640x480,
        ]

        for preset in presets {
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

            // Apply file protection before writing compressed video
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: FileManager.default.temporaryDirectory.path
            )

            print("\nTrying compression with preset: \(preset)")

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            // Create metadata
            let metadataItem = AVMutableMetadataItem()
            metadataItem.identifier = AVMetadataIdentifier(rawValue: "uiso/dscp")
            metadataItem.value = description as NSString
            metadataItem.extendedLanguageTag = "und"
            exportSession.metadata = [metadataItem]
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true

            try await exportSession.export(to: outputURL, as: .mp4)

            let compressedData = try Data(contentsOf: outputURL)
            print("Compressed size: \(compressedData.count) bytes")

            try? FileManager.default.removeItem(at: outputURL)

            if compressedData.count <= targetSize {
                return compressedData
            }
        }

        throw VideoError.compressionFailed("Could not compress video to target size with any preset")
    }

    private func startProgressTimer() {
        recordingProgress = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.recordingProgress < 1.0 {
                    self.recordingProgress += 0.1 / 18 // based on compression ratio and under 1MB limit
                } else {
                    Task {
                        await self.stopRecording(description: "")
                    }
                }
            }
        }
    }
}
