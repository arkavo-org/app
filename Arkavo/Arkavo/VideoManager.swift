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

            // Configure video connection
            if let connection = videoOutput.connection(with: .video) {
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
        print("generateThumbnail")
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
    private var loopObserver: NSObjectProtocol?
    private var currentItem: AVPlayerItem?
    private var preloadedItems: [String: AVPlayerItem] = [:]

    override init() {
        player = AVPlayer()
        super.init()
    }

    func setupPlayer(in view: UIView) {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        setupLooping()
    }

    private func setupLooping() {
        // Remove any existing observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Add new looping observer
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
    }

    @objc private func handleLayoutChange() {
        guard let view = playerLayer?.superlayer else { return }
        playerLayer?.frame = view.bounds
    }

    @objc private func playerItemDidReachEnd(notification _: Notification) {
        print("📼 Video playback completed")
    }

    func playVideo(url: URL) {
//        print("📊 Playing video: \(url)")
        if let preloadedItem = preloadedItems[url.absoluteString] {
            currentItem = preloadedItem
            player.replaceCurrentItem(with: preloadedItem)
        } else {
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            currentItem = item
            player.replaceCurrentItem(with: item)
        }
        player.seek(to: .zero)
        player.play()
        setupLooping()
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
    var nano: Data?
}
