import ArkavoSocial
import AVFoundation
import SwiftData
import SwiftUI

// MARK: - View States

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

// MARK: - Main View

struct TikTokRecordingView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: TikTokRecordingViewModel = ViewModelFactory.shared.makeTikTokRecordingViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ModernRecordingInterface(
            viewModel: viewModel,
            onComplete: { result in
                await handleRecordingComplete(result)
            }
        )
        .alert("Recording Error", isPresented: $showError) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func handleRecordingComplete(_ result: UploadResult?) async {
        let account = viewModel.account

        // Validate we have required data
        guard let result else {
            showError(message: "Failed to get recording result")
            return
        }

        guard let firstStream = account.streams.first else {
            showError(message: "No stream available to save video")
            return
        }

        do {
            // Create a new Thought for the video
            let videoThought = Thought(
                id: UUID(),
                nano: Data(result.playbackURL.utf8)
            )
            videoThought.metadata = ThoughtMetadata(
                creator: UUID(uuidString: account.id.description) ?? UUID(),
                mediaType: .video,
                createdAt: Date()
            )

            // Add thought to the first stream
            firstStream.thoughts.append(videoThought)

            // Save changes
            try PersistenceController.shared.saveStream(firstStream)
            try await PersistenceController.shared.saveChanges()

            // Only dismiss on successful save
            dismiss()
        } catch let error as NSError {
            // Handle specific error cases
            switch error.domain {
            case NSCocoaErrorDomain:
                showError(message: "Failed to save video: Storage error")
            default:
                showError(message: "Failed to save video: \(error.localizedDescription)")
            }
        } catch {
            showError(message: "Unexpected error while saving video")
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

struct PreviewViewWrapper: UIViewRepresentable {
    @ObservedObject var viewModel: TikTokRecordingViewModel

    func makeUIView(context _: Context) -> UIView {
        let previewView = UIView()
        previewView.backgroundColor = .black

        // Call the viewModel setup function
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
    @ObservedObject var viewModel: TikTokRecordingViewModel
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
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }

            VStack {
                Spacer()

                VStack(spacing: 32) {
                    ProgressBar(progress: viewModel.recordingProgress)
                        .frame(height: 3)
                        .padding(.horizontal)

                    ZStack {
                        RecordingControl(
                            viewModel: viewModel,
                            onComplete: onComplete
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

struct RecordingControl: View {
    @ObservedObject var viewModel: TikTokRecordingViewModel
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
                        await viewModel.stopRecording()
                    }
                }
            case .processing, .uploading:
                ProcessingView(state: viewModel.recordingState)
            case let .complete(result):
                CompleteButton {
                    Task {
                        viewModel.cleanup()
                        await onComplete(result)
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

struct CompleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Done")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
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
                                    endPoint: .bottom
                                )
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
                            endPoint: .trailing
                        )
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
                                    endPoint: .trailing
                                )
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

// MARK: - ViewModel

@MainActor
class TikTokRecordingViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published private(set) var recordingState: RecordingState = .initial
    @Published private(set) var recordingProgress: CGFloat = 0
    @Published private(set) var previewLayer: CALayer?

    private var recordingManager: VideoRecordingManager?
    private let processingManager = HLSProcessingManager()
    private let uploadManager = VideoUploadManager()
    private var progressTimer: Timer?

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
    }

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

    func startRecording() async {
        guard let recordingManager else { return }

        do {
            recordingState = .recording
            startProgressTimer()

            let videoURL = try await recordingManager.startRecording()
            print("videoURL: \(videoURL)")
            // Recording continues until stopRecording is called
        } catch {
            print("❌ Recording start failed with error: \(error.localizedDescription)")
            recordingState = .error(error.localizedDescription)
        }
    }

    func stopRecording() async {
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
            let metadata = VideoMetadata(
                title: "New Video",
                thumbnailURL: "",
                videoURL: "",
                duration: processedVideo.duration
            )

            let result = try await uploadManager.uploadVideo(
                directory: processedVideo.directory,
                metadata: metadata
            )

            recordingState = .complete(result)
        } catch {
            print("❌ Recording stop failed with error: \(error.localizedDescription)")
            recordingState = .error(error.localizedDescription)
        }
    }

    func flipCamera() {
        // Implement camera flip functionality
    }

    func cleanup() {
        progressTimer?.invalidate()
        recordingProgress = 0
        recordingState = .initial
        recordingManager = nil
        previewLayer = nil
    }

    private func startProgressTimer() {
        recordingProgress = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.recordingProgress < 1.0 {
                    self.recordingProgress += 0.1 / 60.0 // 60 seconds max
                } else {
                    Task {
                        await self.stopRecording()
                    }
                }
            }
        }
    }

//    deinit {
//        cleanup()
//    }
}
