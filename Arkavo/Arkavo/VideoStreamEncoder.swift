import AVFoundation
import CoreMedia
import VideoToolbox

/// Hardware-accelerated H.264 video encoder for streaming
/// Uses VideoToolbox VTCompressionSession for efficient encoding
final class VideoStreamEncoder {
    // MARK: - Types

    struct Configuration {
        let width: Int
        let height: Int
        let frameRate: Int32
        let bitrate: Int
        let keyFrameInterval: Int

        static let `default` = Configuration(
            width: 1920,
            height: 1080,
            frameRate: 30,
            bitrate: 3_000_000,  // 3 Mbps
            keyFrameInterval: 60  // I-frame every 2 seconds at 30 FPS
        )
    }

    /// Callback invoked when H.264 NAL unit is ready
    /// - Parameters:
    ///   - data: H.264 NAL unit data
    ///   - isKeyFrame: True if this is an I-frame (keyframe)
    ///   - timestamp: Presentation timestamp
    typealias OutputHandler = (Data, Bool, CMTime) -> Void

    // MARK: - Properties

    private var compressionSession: VTCompressionSession?
    private let configuration: Configuration
    private let outputHandler: OutputHandler
    private let outputQueue = DispatchQueue(label: "com.arkavo.video-stream-encoder")

    private var isEncoding = false

    // MARK: - Initialization

    init(configuration: Configuration = .default, outputHandler: @escaping OutputHandler) throws {
        self.configuration = configuration
        self.outputHandler = outputHandler

        try setupCompressionSession()
    }

    deinit {
        invalidate()
    }

    // MARK: - Public Methods

    /// Encode a video frame
    func encode(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) throws {
        guard let session = compressionSession else {
            throw EncoderError.sessionNotReady
        }

        guard isEncoding else {
            throw EncoderError.notEncoding
        }

        // Frame properties
        var frameProperties: [CFString: Any] = [:]

        // Request keyframe every N frames
        let frameNumber = Int(timestamp.seconds * Double(configuration.frameRate))
        if frameNumber % configuration.keyFrameInterval == 0 {
            frameProperties[kVTEncodeFrameOptionKey_ForceKeyFrame] = kCFBooleanTrue
        }

        // Encode frame
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: .invalid,
            frameProperties: frameProperties.isEmpty ? nil : frameProperties as CFDictionary,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        guard status == noErr else {
            throw EncoderError.encodingFailed(status)
        }
    }

    /// Start encoding
    func start() throws {
        guard !isEncoding else { return }
        isEncoding = true
    }

    /// Stop encoding and flush pending frames
    func stop() async throws {
        guard isEncoding else { return }
        isEncoding = false

        guard let session = compressionSession else { return }

        // Flush remaining frames
        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else {
            throw EncoderError.flushFailed(status)
        }
    }

    /// Invalidate the encoder
    func invalidate() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        isEncoding = false
    }

    // MARK: - Private Methods

    private func setupCompressionSession() throws {
        var session: VTCompressionSession?

        // Create compression session
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(configuration.width),
            height: Int32(configuration.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw EncoderError.sessionCreationFailed(status)
        }

        // Configure session properties
        try setSessionProperties(session)

        // Prepare to encode
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            throw EncoderError.prepareFailed(prepareStatus)
        }

        self.compressionSession = session
    }

    private func setSessionProperties(_ session: VTCompressionSession) throws {
        // Enable real-time encoding
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        // Set average bitrate
        let bitrate = configuration.bitrate as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate)

        // Set expected frame rate
        let frameRate = configuration.frameRate as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate)

        // Set max keyframe interval
        let keyFrameInterval = configuration.keyFrameInterval as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyFrameInterval)

        // Profile level (baseline for compatibility, main for better compression)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Main_AutoLevel
        )

        // Allow frame reordering for better compression (B-frames)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        // Hardware acceleration
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, value: kCFBooleanTrue)
    }

    // MARK: - Compression Callback

    private let compressionOutputCallback: VTCompressionOutputCallback = { (
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        _: UnsafeMutableRawPointer?,
        status: OSStatus,
        _: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) in
        guard status == noErr else {
            print("❌ [VideoStreamEncoder] Compression error: \(status)")
            return
        }

        guard let sampleBuffer = sampleBuffer else {
            print("❌ [VideoStreamEncoder] No sample buffer")
            return
        }

        guard let refCon = outputCallbackRefCon else {
            print("❌ [VideoStreamEncoder] No refcon")
            return
        }

        let encoder = Unmanaged<VideoStreamEncoder>.fromOpaque(refCon).takeUnretainedValue()
        encoder.handleCompressedFrame(sampleBuffer)
    }

    private func handleCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
        // Check if this is a keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyFrame = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)

        // Extract H.264 NAL units
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("❌ [VideoStreamEncoder] No data buffer")
            return
        }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let dataPointer = dataPointer else {
            print("❌ [VideoStreamEncoder] Failed to get data pointer: \(status)")
            return
        }

        // Convert to Data
        let data = Data(bytes: dataPointer, count: length)

        // Get timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Deliver via output handler
        outputQueue.async { [weak self] in
            self?.outputHandler(data, isKeyFrame, timestamp)
        }
    }

    // MARK: - Errors

    enum EncoderError: Error {
        case sessionCreationFailed(OSStatus)
        case prepareFailed(OSStatus)
        case sessionNotReady
        case notEncoding
        case encodingFailed(OSStatus)
        case flushFailed(OSStatus)
    }
}
