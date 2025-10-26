@preconcurrency import AVFoundation
import CoreVideo

/// Encodes video and audio to MOV files using AVAssetWriter
public final class VideoEncoder: Sendable {
    // MARK: - Properties

    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var videoInput: AVAssetWriterInput?
    nonisolated(unsafe) private var audioInput: AVAssetWriterInput?
    nonisolated(unsafe) private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    nonisolated(unsafe) private var outputURL: URL?
    nonisolated(unsafe) private var startTime: CMTime?
    nonisolated(unsafe) private var lastVideoTimestamp: CMTime = .zero
    nonisolated(unsafe) private var isPaused: Bool = false
    nonisolated(unsafe) private var pauseStartTime: CMTime?
    nonisolated(unsafe) private var totalPausedDuration: CMTime = .zero

    nonisolated(unsafe) public private(set) var isRecording: Bool = false

    // Encoding settings
    private let videoWidth: Int = 1920
    private let videoHeight: Int = 1080
    private let frameRate: Int32 = 30
    private let videoBitrate: Int = 5_000_000 // 5 Mbps
    private let audioBitrate: Int = 128_000 // 128 kbps

    // MARK: - Public Methods

    public init() {}

    /// Starts recording to the specified output file
    public func startRecording(to url: URL, title: String) async throws {
        guard !isRecording else { return }

        outputURL = url

        // Remove existing file if present
        try? FileManager.default.removeItem(at: url)

        // Create asset writer
        assetWriter = try AVAssetWriter(url: url, fileType: .mov)

        guard let assetWriter = assetWriter else {
            throw RecorderError.encodingFailed
        }

        // Setup video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        // Setup pixel buffer adaptor
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        if let videoInput = videoInput {
            assetWriter.add(videoInput)
        }

        // Setup audio input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100.0,
            AVEncoderBitRateKey: audioBitrate
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        if let audioInput = audioInput {
            assetWriter.add(audioInput)
        }

        // Add metadata
        assetWriter.metadata = createMetadata(title: title)

        // Start writing
        guard assetWriter.startWriting() else {
            throw RecorderError.encodingFailed
        }

        isRecording = true
        startTime = nil
        lastVideoTimestamp = .zero
        isPaused = false
        pauseStartTime = nil
        totalPausedDuration = .zero
    }

    /// Finishes recording and returns the output URL
    public func finishRecording() async throws -> URL {
        guard isRecording, let assetWriter = assetWriter, let outputURL = outputURL else {
            throw RecorderError.encodingFailed
        }

        isRecording = false

        // Mark inputs as finished
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        // Finish writing
        await assetWriter.finishWriting()

        if assetWriter.status == .failed {
            throw assetWriter.error ?? RecorderError.encodingFailed
        }

        // Clean up
        self.assetWriter = nil
        self.videoInput = nil
        self.audioInput = nil
        self.pixelBufferAdaptor = nil

        return outputURL
    }

    /// Pauses recording
    public func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStartTime = lastVideoTimestamp
    }

    /// Resumes recording
    public func resume() {
        guard isRecording, isPaused, let pauseStart = pauseStartTime else { return }
        isPaused = false
        totalPausedDuration = CMTimeAdd(totalPausedDuration, CMTimeSubtract(lastVideoTimestamp, pauseStart))
        pauseStartTime = nil
    }

    /// Current recording duration
    public var duration: TimeInterval {
        guard let startTime = startTime else { return 0 }
        let adjustedDuration = CMTimeSubtract(lastVideoTimestamp, startTime)
        let finalDuration = CMTimeSubtract(adjustedDuration, totalPausedDuration)
        return CMTimeGetSeconds(finalDuration)
    }

    // MARK: - Frame Encoding

    /// Encodes a video frame
    public nonisolated func encodeVideoFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) async {
        guard isRecording, !isPaused else { return }
        guard let videoInput = videoInput, let adaptor = pixelBufferAdaptor else { return }
        guard let assetWriter = assetWriter else { return }

        // Initialize start time on first frame
        if startTime == nil {
            startTime = timestamp
            assetWriter.startSession(atSourceTime: timestamp)
        }

        // Wait if input is not ready
        if !videoInput.isReadyForMoreMediaData {
            return
        }

        // Adjust timestamp for pauses
        var adjustedTimestamp = timestamp
        if !totalPausedDuration.seconds.isZero {
            adjustedTimestamp = CMTimeSubtract(timestamp, totalPausedDuration)
        }

        // Append pixel buffer
        adaptor.append(pixelBuffer, withPresentationTime: adjustedTimestamp)
        lastVideoTimestamp = timestamp
    }

    /// Encodes an audio sample
    public nonisolated func encodeAudioSample(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording, !isPaused else { return }
        guard let audioInput = audioInput else { return }

        // Wait if input is not ready
        if !audioInput.isReadyForMoreMediaData {
            return
        }

        // Adjust timestamp for pauses
        var adjustedBuffer = sampleBuffer
        if !totalPausedDuration.seconds.isZero {
            // Create adjusted sample buffer with new timing
            // This is simplified - full implementation would need proper timing adjustment
            adjustedBuffer = sampleBuffer
        }

        // Append audio sample
        audioInput.append(adjustedBuffer)
    }

    // MARK: - Private Methods

    private func createMetadata(title: String) -> [AVMetadataItem] {
        var metadata: [AVMetadataItem] = []

        // Title
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        metadata.append(titleItem)

        // Creator
        let creatorItem = AVMutableMetadataItem()
        creatorItem.identifier = .commonIdentifierCreator
        creatorItem.value = "Arkavo Creator" as NSString
        metadata.append(creatorItem)

        // Software
        let softwareItem = AVMutableMetadataItem()
        softwareItem.identifier = .commonIdentifierSoftware
        softwareItem.value = "Arkavo Creator v1.0" as NSString
        metadata.append(softwareItem)

        // Creation date
        let dateItem = AVMutableMetadataItem()
        dateItem.identifier = .commonIdentifierCreationDate
        dateItem.value = ISO8601DateFormatter().string(from: Date()) as NSString
        metadata.append(dateItem)

        return metadata
    }
}
