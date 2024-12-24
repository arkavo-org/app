import ArkavoSocial
import AVFoundation
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

    init(feedViewModel _: VideoFeedViewModel) {
        let recordingVM = ViewModelFactory.shared.makeVideoRecordingViewModel()
        _viewModel = StateObject(wrappedValue: recordingVM)
    }

    var body: some View {
        ModernRecordingInterface(
            viewModel: viewModel,
            onComplete: { result in
                await handleRecordingComplete(result)
                sharedState.showCreateView = false
            }
        )
        .alert("Recording Error", isPresented: $showError) {
            Button("OK") {
                sharedState.showCreateView = false
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func handleRecordingComplete(_ result: UploadResult?) async {
        guard let result else {
            showError(message: "Failed to get recording result")
            return
        }
        // Account for NanoTDF overhead - target ~950KB for the video
        let videoTargetSize = 950_000 // Leave ~100KB for NanoTDF overhead
        do {
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
            let compressedData = try await compressVideo(url: videoURL, targetSize: videoTargetSize)
            print("Compressed video size: \(compressedData.count) bytes")

            // Create NanoTDF
            let nanoTDFData = try await viewModel.client.encryptRemotePolicy(
                payload: compressedData,
                remotePolicyBody: ArkavoPolicy.PolicyType.videoFrame.rawValue
            )

            guard nanoTDFData.count <= 1_000_000 else {
                throw NSError(domain: "VideoCompression", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Final NanoTDF too large for websocket"])
            }

            // Send over websocket
            try await viewModel.client.sendNATSMessage(nanoTDFData)

            // Process video metadata and save
            let persistenceController = PersistenceController.shared
            let context = persistenceController.container.mainContext

            // Find video stream
            guard let videoStream = viewModel.account.streams.first(where: { stream in
                stream.sources.first?.metadata.mediaType == .video
            }) else {
                showError(message: "No video stream available")
                return
            }

            let title = "New video recording"

            let streamProfile = Profile(name: title)

            // Create new Thought Stream fo Video
            let stream = Stream(
                creatorPublicID: viewModel.profile.publicID,
                profile: streamProfile,
                policies: Policies(
                    admission: .closed,
                    interaction: .closed,
                    age: .forAll
                )
            )

            // Create metadata
            let metadata = ThoughtMetadata(
                creator: viewModel.profile.id,
                streamPublicID: videoStream.publicID,
                mediaType: .video,
                createdAt: Date(),
                summary: title,
                contributors: []
            )

            // Create thought with policy and encrypted data
            let videoThought = try await viewModel.createThoughtWithPolicy(
                videoData: compressedData,
                metadata: metadata
            )

            videoStream.addThought(videoThought)
            try context.save()

            // Create contributor and update feed
            let contributor = Contributor(
                id: viewModel.profile.id.uuidString,
                creator: Creator(
                    id: viewModel.profile.id.uuidString,
                    name: viewModel.profile.name,
                    imageURL: "",
                    latestUpdate: "",
                    tier: "creator",
                    socialLinks: [],
                    notificationCount: 0,
                    bio: ""
                ),
                role: "Creator"
            )
        } catch {
            print("Failed to process video - Error:", error)
            showError(message: "Failed to process video: \(error.localizedDescription)")
        }
    }

    private func compressVideo(url: URL, targetSize: Int) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let naturalSize = try await track?.load(.naturalSize) ?? CGSize(width: 1080, height: 1920)

        let temporaryDirectory = FileManager.default.temporaryDirectory
        let outputURL = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        // Get original transform to preserve orientation
        let originalTransform = try await track?.load(.preferredTransform) ?? .identity
        // Initial compression settings
        let compressionSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(naturalSize.width),
            AVVideoHeightKey: Int(naturalSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 800_000,
                AVVideoProfileLevelKey: "HEVC_Main_AutoLevel",
                AVVideoMaxKeyFrameIntervalKey: 1,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoQualityKey: 0.6,
            ],
        ]

        // First compression attempt
        print("Starting initial compression with 800Kbps bitrate...")
        let compressedData = try await exportVideo(
            asset: asset,
            toURL: outputURL,
            settings: compressionSettings,
            originalTransform: originalTransform
        )
        print("Initial compression result: \(compressedData.count) bytes (target: \(targetSize) bytes)")

        // Progressive bitrate reduction if needed
        let bitrates = [600_000, 450_000, 350_000, 250_000]
        var resultData = compressedData
        var index = 0

        while resultData.count > targetSize, index < bitrates.count {
            let currentBitrate = bitrates[index]
            print("\nAttempting compression with \(currentBitrate / 1000)Kbps bitrate...")

            var newSettings = compressionSettings
            var properties = newSettings[AVVideoCompressionPropertiesKey] as! [String: Any]
            properties[AVVideoAverageBitRateKey] = currentBitrate
            newSettings[AVVideoCompressionPropertiesKey] = properties

            let retryAsset = AVURLAsset(url: url)
            let retryURL = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

            let previousSize = resultData.count
            resultData = try await exportVideo(
                asset: retryAsset,
                toURL: retryURL,
                settings: newSettings,
                originalTransform: originalTransform
            )
            let reduction = 100.0 - (Double(resultData.count) / Double(previousSize) * 100.0)

            print("Compression result: \(resultData.count) bytes")
            print("Size reduction: \(String(format: "%.1f%%", reduction)) from previous attempt")
            print("Current size vs target: \(resultData.count) vs \(targetSize) bytes")

            try? FileManager.default.removeItem(at: retryURL)
            index += 1
        }

        // Clean up
        try? FileManager.default.removeItem(at: outputURL)

        print("\nFinal compression result: \(resultData.count) bytes")
        if resultData.count > targetSize {
            print("⚠️ Warning: Could not achieve target size of \(targetSize) bytes after all compression attempts")
        }

        return resultData
    }

    @MainActor
    private func exportVideo(
        asset: AVURLAsset,
        toURL: URL,
        settings _: [String: Any],
        originalTransform: CGAffineTransform
    ) async throws -> Data {
        let composition = AVMutableComposition()

        guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoError.compressionFailed("Failed to get video track")
        }

        // Use original size for composition
        let naturalSize = try await assetTrack.load(.naturalSize)
        composition.naturalSize = naturalSize

        // Create and add video track
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoError.compressionFailed("Failed to create composition track")
        }

        // Insert the video
        try await compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.load(.duration)),
            of: assetTrack,
            at: .zero
        )

        // Modify the video track to preserve the rotation metadata
        let videoTrack = composition.tracks(withMediaType: .video).first!
        videoTrack.preferredTransform = originalTransform

        // Create a video composition for the export session
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = naturalSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

        print("🔍 Video Composition Render Size: \(videoComposition.renderSize)")
        print("🔍 Video Composition Frame Duration: \(videoComposition.frameDuration)")

        // Create a composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

        print("🔍 Composition Instruction Time Range: \(instruction.timeRange)")

        // Create a layer instruction for the video track
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        print("🔍 Layer Instruction Track ID: \(compositionTrack.trackID)")

        // Apply the transform to the layer instruction
        layerInstruction.setTransform(originalTransform, at: .zero)

        print("🔍 Layer Instruction Transform Applied: \(originalTransform)")

        // Add the layer instruction to the composition instruction
        instruction.layerInstructions = [layerInstruction]

        print("🔍 Composition Instruction Layer Instructions: \(instruction.layerInstructions)")

        // Add the instruction to the video composition
        videoComposition.instructions = [instruction]

        print("🔍 Video Composition Instructions: \(videoComposition.instructions)")

        // Create export session
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHEVC1920x1080
        ) else {
            throw VideoError.exportSessionCreationFailed("Failed to create HEVC export session")
        }

        // Configure the export
        exporter.outputURL = toURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition // Ensure the transform is preserved
        exporter.shouldOptimizeForNetworkUse = true

        print("🔍 Export Session Video Composition: \(String(describing: exporter.videoComposition))")

        // Use the new async export method
        do {
            try await exporter.export(to: toURL, as: .mp4)
            print("✅ Export completed successfully")
        } catch {
            print("❌ Export failed with error: \(error.localizedDescription)")
            throw VideoError.exportFailed("Export failed: \(error.localizedDescription)")
        }

        print("Export complete - checking file size...")
        let fileSize = try toURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("Exported file size: \(fileSize) bytes")

        return try Data(contentsOf: toURL)
    }

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
    @ObservedObject var viewModel: VideoRecordingViewModel
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
final class VideoRecordingViewModel: ObservableObject {
    // MARK: - Properties

    let client: ArkavoClient
    let account: Account
    let profile: Profile

    @Published private(set) var recordingState: RecordingState = .initial
    @Published private(set) var recordingProgress: CGFloat = 0
    @Published private(set) var previewLayer: CALayer?

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

            let result = UploadResult(
                id: processedVideo.directory.lastPathComponent,
                playbackURL: videoURL.absoluteString
            )

            recordingState = .complete(result)
        } catch {
            print("❌ Recording stop failed with error: \(error.localizedDescription)")
            recordingState = .error(error.localizedDescription)
        }
    }

    func flipCamera() {
        // Implementation for camera flip functionality
        // This would interact with the AVCaptureDevice to switch between front and back cameras
    }

    func createThoughtWithPolicy(videoData: Data, metadata: ThoughtMetadata) async throws -> Thought {
        var builder = FlatBufferBuilder()

        // Create rating based on video content
        let rating = Arkavo_Rating.createRating(
            &builder,
            violent: .mild,
            sexual: .none_,
            profane: .none_,
            substance: .none_,
            hate: .none_,
            harm: .none_,
            mature: .mild,
            bully: .none_
        )

        // Create purpose probabilities
        let purpose = Arkavo_Purpose.createPurpose(
            &builder,
            educational: 0.2,
            entertainment: 0.8, // Video content is primarily entertainment
            news: 0.0,
            promotional: 0.0,
            personal: 0.0,
            opinion: 0.0,
            transactional: 0.0,
            harmful: 0.0,
            confidence: 0.9
        )

        // Create format info for video
        let formatVersionString = builder.create(string: "H.265")
        let formatProfileString = builder.create(string: "HEVC")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
            &builder,
            type: .plain, // Update with appropriate video format type
            versionOffset: formatVersionString,
            profileOffset: formatProfileString
        )

        // Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: .video,
            dataEncoding: .binary,
            formatOffset: formatInfo
        )

        // Create vectors for IDs
        let idVector = builder.createVector(bytes: metadata.creator.uuidString.data(using: .utf8) ?? Data())
        let relatedVector = builder.createVector(bytes: metadata.streamPublicID)

        // Create topics vector (if needed)
        let topics: [UInt32] = [] // Add relevant topic IDs
        let topicsVector = builder.createVector(topics)

        // Create metadata root
        let arkMetadata = Arkavo_Metadata.createMetadata(
            &builder,
            created: Int64(Date().timeIntervalSince1970),
            idVectorOffset: idVector,
            relatedVectorOffset: relatedVector,
            ratingOffset: rating,
            purposeOffset: purpose,
            topicsVectorOffset: topicsVector,
            contentOffset: contentFormat
        )

        builder.finish(offset: arkMetadata)

        // Get policy data
        let policyData = Data(
            bytes: builder.sizedBuffer.memory.advanced(by: builder.sizedBuffer.reader),
            count: Int(builder.sizedBuffer.size)
        )

        // Create NanoTDF with metadata in policy
        let nanoTDFData = try await client.encryptAndSendPayload(
            payload: videoData,
            policyData: policyData
        )

        return Thought(
            nano: nanoTDFData,
            metadata: metadata // This is now redundant since it's in the policy
        )
    }

    // MARK: - Private Helpers

    private func startProgressTimer() {
        recordingProgress = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.recordingProgress < 1.0 {
                    self.recordingProgress += 0.1 / 5.5 // 5.5 seconds max based on compression ratio
                } else {
                    Task {
                        await self.stopRecording()
                    }
                }
            }
        }
    }
}
