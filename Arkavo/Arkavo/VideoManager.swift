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
        // Force HD 1080x1920 for portrait
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

            // Force portrait orientation using rotation angle (90 degrees)
            if let connection = videoOutput.connection(with: .video) {
                let portraitAngle = CGFloat.pi / 2 // 90 degrees
                if connection.isVideoRotationAngleSupported(portraitAngle) {
                    connection.videoRotationAngle = portraitAngle
                }

                // Enable video stabilization if available
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

        // Force portrait orientation using rotation angle (90 degrees)
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(CGFloat.pi / 2)
        {
            connection.videoRotationAngle = CGFloat.pi / 2
        }

        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
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

            // Generate thumbnail
            guard let thumbnail = try await generateThumbnail(for: asset) else {
                throw VideoError.processingFailed("Failed to generate thumbnail")
            }

            let duration = try await asset.load(.duration).seconds

            // Simply copy the original video file to the output directory
            let finalVideoURL = outputDirectory.appendingPathComponent("\(videoID).mp4")
            try FileManager.default.copyItem(at: url, to: finalVideoURL)

            return ProcessingResult(
                directory: outputDirectory,
                thumbnail: thumbnail,
                duration: duration
            )
        } catch {
            print("❌ Video processing failed: \(error.localizedDescription)")
            throw VideoError.processingFailed(error.localizedDescription)
        }
    }

    private func generateThumbnail(for asset: AVAsset) async throws -> UIImage? {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ Thumbnail generation failed: \(error.localizedDescription)")
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

    override init() {
        player = AVPlayer()
        super.init()
    }

    func setupPlayer(in view: UIView) {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
//        playerLayer.videoGravity = .resizeAspectFill
//        view.layer.masksToBounds = true
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
    }

    @objc private func handleLayoutChange() {
        guard let view = playerLayer?.superlayer else { return }
        playerLayer?.frame = view.bounds
    }

    func playVideo(url: URL) {
        print("📹 Playing video: \(url)")
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Debug video track info
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = tracks.first {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)

                    print("\n📼 Video Track Info:")
                    print("- Natural size: \(naturalSize)")
                    print("- Transform matrix: \(transform)")

                    // Create a video composition
                    let videoComposition = AVMutableVideoComposition()
                    videoComposition.renderSize = naturalSize
                    videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

                    print("🔍 Video Composition Render Size: \(videoComposition.renderSize)")
                    print("🔍 Video Composition Frame Duration: \(videoComposition.frameDuration)")

                    // Create a composition instruction
                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = CMTimeRangeMake(start: .zero, duration: asset.duration)

                    print("🔍 Composition Instruction Time Range: \(instruction.timeRange)")

                    // Create a layer instruction for the video track
                    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

                    print("🔍 Layer Instruction Track ID: \(videoTrack.trackID)")

                    // Apply the transform to the layer instruction
                    layerInstruction.setTransform(transform, at: .zero)

                    print("🔍 Layer Instruction Transform Applied: \(transform)")

                    // Add the layer instruction to the composition instruction
                    instruction.layerInstructions = [layerInstruction]

                    print("🔍 Composition Instruction Layer Instructions: \(instruction.layerInstructions)")

                    // Add the instruction to the video composition
                    videoComposition.instructions = [instruction]

                    print("🔍 Video Composition Instructions: \(videoComposition.instructions)")

                    // Set the video composition on the player item
                    item.videoComposition = videoComposition

                    print("🔍 Player Item Video Composition: \(String(describing: item.videoComposition))")
                }
            } catch {
                print("❌ Error loading video track info: \(error)")
            }
        }

        currentItem = item
        player.replaceCurrentItem(with: item)
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
        NotificationCenter.default.removeObserver(self)
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
