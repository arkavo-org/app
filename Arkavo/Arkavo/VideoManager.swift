import AVFoundation
import UIKit

// MARK: - Error Types

enum VideoError: Error {
    case captureSessionSetupFailed
    case deviceNotAvailable
    case invalidInput
    case outputSetupFailed
    case recordingFailed(String)
    case processingFailed(String)
    case uploadFailed(String)
    case exportFailed(String)
    case setupFailed(String)
    case assetLoadingFailed(String)
    case compressionFailed(String)
    case exportSessionCreationFailed(String)
    case exportSessionFailed(String)
}

class VideoRecordingManager {
    private let captureSession: AVCaptureSession
    private let videoOutput: AVCaptureMovieFileOutput
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    // Current recording state
    private(set) var isRecording = false
    private(set) var currentVideoURL: URL?

    // Strong reference to current recording delegate
    private var currentRecordingDelegate: RecordingDelegate?

    init() async throws {
        captureSession = AVCaptureSession()
        videoOutput = AVCaptureMovieFileOutput()
        try await setupCaptureSession()
    }

    private func setupCaptureSession() async throws {
        // Use 1080x1920 for portrait HD
        captureSession.sessionPreset = .hd1920x1080

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .back)
        else {
            throw VideoError.deviceNotAvailable
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(videoInput) else {
                throw VideoError.invalidInput
            }
            captureSession.addInput(videoInput)

            guard captureSession.canAddOutput(videoOutput) else {
                throw VideoError.outputSetupFailed
            }
            captureSession.addOutput(videoOutput)

            // Lock to portrait orientation using new rotation angle API
            if let connection = videoOutput.connection(with: .video) {
                let angle = CGFloat.pi/2 // 90 degrees
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        } catch {
            throw VideoError.captureSessionSetupFailed
        }
    }

    func startPreview(in view: UIView) -> CALayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
            print("✅ Camera preview started")
        }
        return previewLayer
    }

    func startRecording() async throws -> URL {
        guard !isRecording else {
            throw VideoError.recordingFailed("Already recording")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let videoID = UUID().uuidString
        let videoPath = tempDir.appendingPathComponent("\(videoID).mp4")
        print("📝 Will save video to: \(videoPath.path)")

        return try await withCheckedThrowingContinuation { continuation in
            // Create new delegate and store strong reference
            let delegate = RecordingDelegate { [weak self] error in
                if let error {
                    print("❌ Recording failed with error: \(error.localizedDescription)")
                    continuation.resume(throwing: VideoError.recordingFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: videoPath)
                }
                // Clear the delegate reference after completion
                self?.currentRecordingDelegate = nil
            }

            // Store strong reference to delegate
            self.currentRecordingDelegate = delegate

            // Start recording
            videoOutput.startRecording(to: videoPath, recordingDelegate: delegate)
            isRecording = true
            currentVideoURL = videoPath
            print("📹 Started recording to: \(videoPath)")
        }
    }

    func stopRecording() async throws {
        guard isRecording else { return }

        return try await withCheckedThrowingContinuation { continuation in
            // Create completion handler for stop recording
            let handler = { continuation.resume() }

            // Stop recording and set completion handler
            videoOutput.stopRecording()
            isRecording = false

            // If there's no active recording delegate, complete immediately
            if currentRecordingDelegate == nil {
                handler()
            } else {
                // Otherwise, wait for the delegate to complete
                currentRecordingDelegate?.onStop = handler
            }
        }
    }

    deinit {
        captureSession.stopRunning()
    }
}

// Recording Delegate
private class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let completion: (Error?) -> Void
    var onStop: (() -> Void)?

    init(completion: @escaping (Error?) -> Void) {
        self.completion = completion
        super.init()
    }

    func fileOutput(_: AVCaptureFileOutput,
                    didFinishRecordingTo _: URL,
                    from _: [AVCaptureConnection],
                    error: Error?)
    {
        completion(error)
        onStop?()
    }
}

// MARK: - HLS Processing Manager

actor HLSProcessingManager {
    struct ProcessingResult {
        let directory: URL
        let thumbnail: UIImage
        let duration: Double
    }

    func processVideo(at url: URL) async throws -> ProcessingResult {
        let asset = AVURLAsset(url: url)
        let videoID = UUID().uuidString
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(videoID)

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            // First, export to an intermediate MP4
            let intermediateURL = outputDirectory.appendingPathComponent("\(videoID).mp4")
            try await exportToMP4(asset: asset, outputURL: intermediateURL)

            // Then create HLS segments
            let hlsOutputURL = outputDirectory.appendingPathComponent("index.mp4")
            try await generateMP4Segments(from: intermediateURL, to: hlsOutputURL)

            // Clean up intermediate file
            try? FileManager.default.removeItem(at: intermediateURL)

            guard let thumbnail = try await generateThumbnail(for: asset) else {
                print("❌ Thumbnail generation failed")
                throw VideoError.processingFailed("Failed to generate thumbnail")
            }

            let duration = try await asset.load(.duration).seconds
            print("✅ Video processing completed successfully")
            return ProcessingResult(
                directory: outputDirectory,
                thumbnail: thumbnail,
                duration: duration
            )
        } catch {
            print("❌ Video processing failed: \(error.localizedDescription)\n")
            throw VideoError.processingFailed(error.localizedDescription)
        }
    }

    private func exportToMP4(asset: AVAsset, outputURL: URL) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            print("❌ Failed to create MP4 export session")
            throw VideoError.exportFailed("Failed to create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Use the new export(to:as:) method
        try await exportSession.export(to: outputURL, as: .mp4)
    }

    private func generateMP4Segments(from sourceURL: URL, to outputURL: URL) async throws {
        print("🎯 Starting MP4 segment generation...")
        guard let exportSession = AVAssetExportSession(asset: AVURLAsset(url: sourceURL), presetName: AVAssetExportPresetHighestQuality) else {
            print("❌ Failed to create MP4 export session")
            throw VideoError.exportFailed("Failed to create MP4 export session")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        print("📊 MP4 Export status: \(exportSession.description)")
        try await exportSession.export(to: outputURL, as: .mp4)
    }

    private func generateThumbnail(for asset: AVAsset) async throws -> UIImage? {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ HLS generateThumbnail failed: \(error.localizedDescription)")
            throw VideoError.processingFailed("Thumbnail generation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Video Player Manager

@MainActor
final class VideoPlayerManager: NSObject {
    private let player: AVPlayer
    private weak var playerLayer: AVPlayerLayer?
    private var currentItem: AVPlayerItem?
    private var preloadedItems: [String: AVPlayerItem] = [:]
    private var currentVideoSize: CGSize?
    private var boundsObservation: NSKeyValueObservation?
    
    override init() {
        player = AVPlayer()
        super.init()
        
        // Add periodic time observer for smooth playback
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                     queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updatePlayerLayerIfNeeded()
            }
        }
    }
    
    func setupPlayer(in view: UIView) {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.masksToBounds = true
        
        // Initialize with full view bounds
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        
        // Add bounds change observer
        boundsObservation = view.layer.observe(\.bounds) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                await self?.updatePlayerLayerIfNeeded()
            }
        }
        
        // Register for orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func updatePlayerLayerFrame(with naturalSize: CGSize, transform: CGAffineTransform) {
        guard let view = playerLayer?.superlayer?.superlayer,
              let playerLayer = playerLayer else { return }
        
        let viewBounds = view.bounds
        let viewSize = viewBounds.size
        
        // Apply 90 degree rotation transform
        playerLayer.transform = CATransform3DMakeRotation(.pi/2, 0, 0, 1)
        
        // For 1080x1920 video, use height/width ratio
        let videoRatio = naturalSize.height / naturalSize.width  // 1920/1080 ≈ 1.77
        var newFrame = viewBounds
        
        // Use full view height
        newFrame.size.height = viewSize.height
        // Width should be height * aspect ratio to maintain proportions
        newFrame.size.width = viewSize.height * videoRatio
        
        // Position at top-left corner with rotation offset
        newFrame.origin.x = -newFrame.size.height
        newFrame.origin.y = 0
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        playerLayer.frame = newFrame
        CATransaction.commit()
        
        print("\n📐 Frame Calculation:")
        print("- View size: \(viewSize)")
        print("- Video natural size: \(naturalSize)")
        print("- Video ratio: \(videoRatio)")
        print("- Calculated frame: \(newFrame)")
    }
    
    private func updatePlayerLayerIfNeeded() async {
        guard let playerLayer = playerLayer,
              let currentItem = player.currentItem else { return }
        
        do {
            let videoTracks = try await currentItem.asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first,
                  let currentVideoSize = currentVideoSize else { return }
            
            let transform = try await videoTrack.load(.preferredTransform)
            updatePlayerLayerFrame(with: currentVideoSize, transform: transform)
        } catch {
            print("Error updating player layer: \(error)")
        }
    }
    
    @objc private func handleOrientationChange() {
        Task { @MainActor in
            await updatePlayerLayerIfNeeded()
        }
    }
    
    func playVideo(url: URL) {
        print("📊 Playing video: \(url)")
        let item: AVPlayerItem
        
        if let preloadedItem = preloadedItems[url.absoluteString] {
            item = preloadedItem
        } else {
            let asset = AVURLAsset(url: url)
            item = AVPlayerItem(asset: asset)
        }
        
        currentItem = item
        player.replaceCurrentItem(with: item)
        
        // Configure video track
        Task {
            do {
                if let videoTrack = try await item.asset.loadTracks(withMediaType: .video).first {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    
                    await MainActor.run { [weak self] in
                        self?.currentVideoSize = naturalSize
                        self?.updatePlayerLayerFrame(with: naturalSize, transform: transform)
                    }
                }
            } catch {
                print("Error configuring video track: \(error)")
            }
        }
        
        player.seek(to: .zero)
        player.play()
    }
    
    func preloadVideo(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        _ = try await asset.load(.isPlayable)

        let item = AVPlayerItem(asset: asset)
        preloadedItems[url.absoluteString] = item
        item.preferredForwardBufferDuration = 4.0
    }
    
    deinit {
        // Remove observers
        boundsObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
        
        // Cleanup playback
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - Supporting Types

struct VideoMetadata: Codable, Sendable {
    let id: String
    let title: String
    let thumbnailURL: String
    let videoURL: String
    let duration: Double
    let createdAt: Date

    init(id: String = UUID().uuidString,
         title: String,
         thumbnailURL: String,
         videoURL: String,
         duration: Double,
         createdAt: Date = Date())
    {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.videoURL = videoURL
        self.duration = duration
        self.createdAt = createdAt
    }
}

struct UploadResult: Codable, Sendable {
    let id: String
    let playbackURL: String
}
