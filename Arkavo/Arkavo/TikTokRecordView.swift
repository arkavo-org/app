import SwiftUI
import AVFoundation

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
            return true
        case (.complete(let lhsResult), .complete(let rhsResult)):
            return lhsResult.id == rhsResult.id
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Main View
struct TikTokRecordingView: View {
    @StateObject private var viewModel = TikTokRecordingViewModel()
    @State private var showRecordingView = false
    @State private var showErrorAlert = false
    
    var body: some View {
        ZStack {
            if !showRecordingView {
                TikTokFeedView()
                    .overlay(alignment: .bottom) {
                        RecordButton(isRecording: false) {
                            showRecordingView = true
                        }
                        .padding(.bottom, 30)
                    }
            } else {
                RecordingInterface(
                    viewModel: viewModel,
                    onComplete: { showRecordingView = false }
                )
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .error(let message) = viewModel.recordingState {
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

// MARK: - Recording Interface
struct RecordingInterface: View {
    @ObservedObject var viewModel: TikTokRecordingViewModel
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Preview view
            PreviewView(previewLayer: viewModel.previewLayer)
                .ignoresSafeArea()
            
            // Controls overlay
            VStack(spacing: 20) {
                // Top toolbar
                HStack {
                    Button {
                        viewModel.cleanup()
                        onComplete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button {
                        viewModel.flipCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                Spacer()
                
                // Recording controls
                VStack(spacing: 20) {
                    // Progress bar
                    ProgressBar(progress: viewModel.recordingProgress)
                        .frame(height: 4)
                    
                    // Recording button and state
                    HStack {
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
                        case .complete:
                            Button("Done") {
                                viewModel.cleanup()
                                onComplete()
                            }
                            .buttonStyle(.borderedProminent)
                        case .error:
                            Button("Retry") {
                                Task {
                                    await viewModel.setup()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .task {
            await viewModel.setup()
        }
    }
}

// MARK: - Supporting Views
struct PreviewView: UIViewRepresentable {
    let previewLayer: CALayer?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = previewLayer {
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
    
    func setup() async {
        do {
            recordingManager = try await VideoRecordingManager()
            recordingState = .setupComplete
        } catch {
            recordingState = .error(error.localizedDescription)
        }
    }
    
    func startRecording() async {
        guard let recordingManager = recordingManager else { return }
        
        do {
            recordingState = .recording
            startProgressTimer()
            
            let videoURL = try await recordingManager.startRecording()
            print("videoURL: \(videoURL)")
            // Recording continues until stopRecording is called
        } catch {
            recordingState = .error(error.localizedDescription)
        }
    }
    
    func stopRecording() async {
        guard let recordingManager = recordingManager else { return }
        
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
            guard let self = self else { return }
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

// MARK: - Preview
#Preview {
    TikTokRecordingView()
}
