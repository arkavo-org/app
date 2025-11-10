@preconcurrency import AVFoundation
import CoreVideo
import ArkavoStreaming

/// Encodes video and audio to MOV files using AVAssetWriter
/// Supports optional simultaneous streaming via RTMP
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

    // Streaming support
    nonisolated(unsafe) private var rtmpPublisher: RTMPPublisher?
    nonisolated(unsafe) private var isStreaming: Bool = false
    nonisolated(unsafe) private var videoFormatDescription: CMFormatDescription?
    nonisolated(unsafe) private var audioFormatDescription: CMFormatDescription?
    nonisolated(unsafe) private var sentVideoSequenceHeader: Bool = false
    nonisolated(unsafe) private var sentAudioSequenceHeader: Bool = false

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
        guard isRecording else {
            print("❌ finishRecording: Not currently recording")
            throw RecorderError.encodingFailed
        }

        guard let assetWriter = assetWriter else {
            print("❌ finishRecording: Asset writer is nil")
            throw RecorderError.encodingFailed
        }

        guard let outputURL = outputURL else {
            print("❌ finishRecording: Output URL is nil")
            throw RecorderError.encodingFailed
        }

        isRecording = false

        // Check if a session was actually started (at least one frame was written)
        let sessionStarted = startTime != nil
        print("📊 Session started: \(sessionStarted), Asset writer status: \(assetWriter.status.rawValue)")

        // Only finish if a session was started and asset writer is in writing state
        if sessionStarted && assetWriter.status == .writing {
            print("📝 Marking inputs as finished...")

            // Mark inputs as finished if they exist and are ready
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.markAsFinished()
                print("  ✓ Video input marked as finished")
            } else {
                print("  ⚠️ Video input not ready or nil")
            }

            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.markAsFinished()
                print("  ✓ Audio input marked as finished")
            } else {
                print("  ⚠️ Audio input not ready or nil")
            }

            // Finish writing
            print("⏳ Finishing asset writer...")
            await assetWriter.finishWriting()
            print("✅ Asset writer finished with status: \(assetWriter.status.rawValue)")
        } else if !sessionStarted {
            print("⚠️ No frames were written (session never started), cancelling asset writer")
            assetWriter.cancelWriting()
        } else {
            print("⚠️ Asset writer not in writing state (status: \(assetWriter.status.rawValue)), cannot finish")
        }

        if assetWriter.status == .failed {
            let errorMessage = assetWriter.error?.localizedDescription ?? "Unknown error"
            let underlyingError = (assetWriter.error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError
            print("❌ Asset writer failed: \(errorMessage)")
            if let underlyingError = underlyingError {
                print("   Underlying error: Domain=\(underlyingError.domain) Code=\(underlyingError.code)")
            }
            throw assetWriter.error ?? RecorderError.encodingFailed
        }

        // Clean up
        self.assetWriter = nil
        self.videoInput = nil
        self.audioInput = nil
        self.pixelBufferAdaptor = nil

        print("✅ Recording finished successfully at: \(outputURL.path)")
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

        // Append pixel buffer to file
        adaptor.append(pixelBuffer, withPresentationTime: adjustedTimestamp)
        lastVideoTimestamp = timestamp

        // Also stream if streaming is active
        if isStreaming, let publisher = rtmpPublisher {
            // Need to convert pixel buffer to sample buffer for streaming
            // This would require creating a CMSampleBuffer from CVPixelBuffer
            // For now, skip - will implement when we have full pipeline
        }
    }

    /// Encodes an audio sample
    public nonisolated func encodeAudioSample(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording, !isPaused else { return }
        guard startTime != nil else {
            // Wait until video session has started to keep A/V in sync
            return
        }
        guard
            let audioInput = audioInput,
            let writer = assetWriter,
            writer.status == .writing,
            CMSampleBufferIsValid(sampleBuffer)
        else {
            return
        }

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

        // Append audio sample to file
        if !audioInput.append(adjustedBuffer) {
            print("⚠️ Audio input rejected sample buffer; dropping frame")
            return
        }

        // Also stream if streaming is active
        if isStreaming, let publisher = rtmpPublisher {
            Task {
                do {
                    // Send audio sequence header on first audio packet
                    if !sentAudioSequenceHeader, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                        audioFormatDescription = formatDesc
                        // TODO: Send audio sequence header via FLVMuxer
                        sentAudioSequenceHeader = true
                    }

                    // Send audio data
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    try await publisher.publishAudio(buffer: sampleBuffer, timestamp: timestamp)
                } catch {
                    print("⚠️ Failed to publish audio: \(error)")
                }
            }
        }
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

    // MARK: - Streaming Methods

    /// Start streaming to RTMP destination(s) while recording
    public func startStreaming(to destination: RTMPPublisher.Destination, streamKey: String) async throws {
        guard !isStreaming else {
            print("⚠️ Already streaming")
            return
        }

        print("📡 Starting RTMP stream...")

        let publisher = RTMPPublisher()
        try await publisher.connect(to: destination, streamKey: streamKey)

        rtmpPublisher = publisher
        isStreaming = true
        sentVideoSequenceHeader = false
        sentAudioSequenceHeader = false

        print("✅ RTMP stream started")
    }

    /// Stop streaming
    public func stopStreaming() async {
        guard isStreaming, let publisher = rtmpPublisher else { return }

        print("📡 Stopping RTMP stream...")
        await publisher.disconnect()

        rtmpPublisher = nil
        isStreaming = false
        sentVideoSequenceHeader = false
        sentAudioSequenceHeader = false

        print("✅ RTMP stream stopped")
    }

    /// Get streaming statistics
    public var streamStatistics: RTMPPublisher.StreamStatistics? {
        get async {
            guard let publisher = rtmpPublisher else { return nil }
            return await publisher.statistics
        }
    }
}
