import AVFoundation
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
    @StateObject private var viewModel = TikTokRecordingViewModel()
    @State private var showErrorAlert = false
    let onComplete: (UploadResult?) -> Void

    var body: some View {
        RecordingInterface(
            viewModel: viewModel,
            onComplete: onComplete
        )
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if case let .error(message) = viewModel.recordingState {
                Text(message)
            }
        }
        .onChange(of: viewModel.recordingState) { _, state in
            if case .error = state {
                showErrorAlert = true
            }
        }
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

// MARK: - Recording Interface

struct RecordingInterface: View {
    @ObservedObject var viewModel: TikTokRecordingViewModel
    let onComplete: (UploadResult?) -> Void

    var body: some View {
        ZStack {
            // Preview view
            PreviewViewWrapper(viewModel: viewModel)
                .ignoresSafeArea()

            // Controls overlay
            VStack(spacing: 20) {
                // Recording controls
                VStack(spacing: 20) {
                    // Progress bar
                    ProgressBar(progress: viewModel.recordingProgress)
                        .frame(height: 4)

                    // Recording button and state
                    HStack {
                        Button {
                            viewModel.flipCamera()
                        } label: {
                            Image(systemName: "camera.rotate")
                                .font(.title2)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        switch viewModel.recordingState {
                        case .initial:
                            ProgressView()
                                .tint(.white)
                        case .setupComplete:
                            RecordButton(isRecording: false) {
                                Task {
                                    await viewModel.startRecording()
                                }
                            }
                        case .recording:
                            RecordButton(isRecording: true) {
                                Task {
                                    await viewModel.stopRecording()
                                }
                            }
                        case .processing:
                            ProgressView("Processing")
                                .tint(.white)
                        case .uploading:
                            ProgressView("Uploading")
                                .tint(.white)
                        case let .complete(result):
                            Button("Done") {
                                viewModel.cleanup()
                                onComplete(result)
                            }
                            .buttonStyle(.borderedProminent)
                        case .error:
                            Text("Error \(viewModel.recordingState)")
                                .foregroundColor(.red)
                        }

                        Spacer()
                    }
                }
                .padding(.bottom, 80)
            }
        }
    }
}

// MARK: - Supporting Views

struct PreviewView: UIViewRepresentable {
    let previewLayer: CALayer?

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        if let previewLayer {
            if previewLayer.superlayer == nil {
                previewLayer.frame = uiView.bounds
                uiView.layer.addSublayer(previewLayer)
            }
        }
    }
}

struct RecordButton: View {
    var isRecording: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 40)
                    .fill(Color.red)
                    .frame(width: isRecording ? 40 : 70, height: isRecording ? 40 : 70)
                    .animation(.spring(), value: isRecording)
            }
        }
    }
}

struct ProgressBar: View {
    var progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))

                Rectangle()
                    .fill(Color.red)
                    .frame(width: geometry.size.width * progress)
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class TikTokRecordingViewModel: ObservableObject {
    @Published private(set) var recordingState: RecordingState = .initial
    @Published private(set) var recordingProgress: CGFloat = 0
    @Published private(set) var previewLayer: CALayer?

    private var recordingManager: VideoRecordingManager?
    private let processingManager = HLSProcessingManager()
    private let uploadManager = VideoUploadManager()
    private var progressTimer: Timer?

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
