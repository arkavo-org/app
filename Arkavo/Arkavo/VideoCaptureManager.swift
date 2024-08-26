import AVFoundation
import Combine
import CryptoKit
import OpenTDFKit
import SwiftUI
import VideoToolbox

class VideoCaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var streamingService: StreamingService?
    private var videoCompressor: VideoCompressor?
    private var videoWidth: Int32 = 0
    private var videoHeight: Int32 = 0
    private var videoEncryptor: VideoEncryptor?
    private var encryptionSession: EncryptionSession?
    private var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var kasPublicKeySubscription: AnyCancellable?
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isCameraActive = false
    @Published var isStreaming = false
    @Published var isConnected = false
    @Published var hasCameraAccess = false
    @Published var error: Error?

    override init() {
        super.init()
        checkCameraPermissions()
    }

    func setKasPublicKeyBinding(_ binding: Binding<P256.KeyAgreement.PublicKey?>) {
        kasPublicKeySubscription = binding.wrappedValue.publisher
            .sink { [weak self] newValue in
                self?.updateKasPublicKey(newValue)
            }
        // Initial update
        updateKasPublicKey(binding.wrappedValue)
    }

    private func updateKasPublicKey(_ newValue: P256.KeyAgreement.PublicKey?) {
        kasPublicKey = newValue
        if let newValue {
            videoEncryptor = VideoEncryptor(kasPublicKey: newValue)
        } else {
            videoEncryptor = nil
        }
    }

    func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraAccess = true
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasCameraAccess = granted
                    if granted {
                        self?.setupCaptureSession()
                    }
                }
            }
        case .denied, .restricted:
            hasCameraAccess = false
        @unknown default:
            hasCameraAccess = false
        }
    }

    private func setupCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let session = AVCaptureSession()
            session.sessionPreset = .high

            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  session.canAddInput(videoInput)
            else {
                print("Failed to set up video capture device")
                return
            }

            session.addInput(videoInput)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            self?.videoOutput = videoOutput
            self?.captureSession = session

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = UIScreen.main.bounds
                self?.previewLayer = previewLayer
            }
            // Set up video compressor
            let formatDescription = videoDevice.activeFormat.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            self?.videoWidth = dimensions.width
            self?.videoHeight = dimensions.height
            self?.videoCompressor = VideoCompressor()
            self?.videoCompressor?.setupCompression()
            // FIXME: add back video compression
            // Set up video encryptor
            DispatchQueue.main.async {
                if let kasPublicKey = self?.kasPublicKey {
                    self?.videoEncryptor = VideoEncryptor(kasPublicKey: kasPublicKey)
                } else {
                    print("Error: KAS public key not available")
                }
            }
        }
    }

    func startCapture() {
        guard hasCameraAccess else {
            checkCameraPermissions()
            return
        }

        if captureSession == nil {
            setupCaptureSession()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isCameraActive = true
            }
        }
    }

    func stopCapture() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isCameraActive = false
                self?.isStreaming = false
            }
        }
    }

    func setupEncryption() {
        encryptionSession = EncryptionSession()
        if let kasPublicKey {
            encryptionSession?.setupEncryption(kasPublicKey: kasPublicKey)
        }
    }

    func startStreaming(webSocketManager: WebSocketManager) {
//        print("connectionState: \(webSocketManager.connectionState)")
        streamingService = StreamingService(webSocketManager: webSocketManager)
        isStreaming = true
    }

    func stopStreaming() {
        streamingService = nil
        isStreaming = false
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard isStreaming, let streamingService, let videoEncryptor, let videoCompressor else {
//            print("Streaming is not active or required services are not available")
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get pixel buffer from sample buffer")
            return
        }
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        videoCompressor.compressFrame(pixelBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration) { compressedData in
            if let compressedData {
                videoEncryptor.encryptFrame(compressedData, timestamp: presentationTimeStamp, width: self.videoWidth, height: self.videoHeight) { encryptedData in
                    if let encryptedData {
//                        print("Frame compressed and encrypted successfully. Sending frame of size: \(encryptedData.count) bytes")
                        streamingService.sendVideoFrame(encryptedData)
                    } else {
                        print("Failed to encrypt frame")
                    }
                }
            } else {
                print("Failed to compress video frame")
            }
        }
    }
}

enum VideoCodecConfig {
    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let fps: Int32 = 30
    static let bitRate: Int32 = 1_000_000 // 1 Mbps
    static let keyframeInterval: Int32 = 60
    static let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

    static var compressionProperties: [String: Any] {
        [
            kVTCompressionPropertyKey_RealTime as String: kCFBooleanTrue!,
            kVTCompressionPropertyKey_ProfileLevel as String: kVTProfileLevel_H264_Baseline_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate as String: bitRate,
            kVTCompressionPropertyKey_ExpectedFrameRate as String: fps,
            kVTCompressionPropertyKey_MaxKeyFrameInterval as String: keyframeInterval,
            kVTCompressionPropertyKey_AllowFrameReordering as String: kCFBooleanFalse!,
            kVTCompressionPropertyKey_DataRateLimits as String: [bitRate / 8, 1] as CFArray,
        ]
    }

    static var decompressionImageBufferAttributes: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
    }
}

class StreamingService {
    private let webSocketManager: WebSocketManager

    init(webSocketManager: WebSocketManager) {
        self.webSocketManager = webSocketManager
    }

    func sendVideoFrame(_ encryptedBuffer: Data) {
        let natsMessage = NATSMessage(payload: encryptedBuffer)
        let messageData = natsMessage.toData()

        webSocketManager.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending video frame: \(error)")
            }
        }
    }
}

class VideoCompressor {
    private var compressionSession: VTCompressionSession?
    private let compressionQueue = DispatchQueue(label: "com.videocompressor.compression")

    func setupCompression() {
        VTCompressionSessionCreate(
            allocator: nil,
            width: VideoCodecConfig.width,
            height: VideoCodecConfig.height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &compressionSession
        )
        guard let compressionSession else {
            print("Failed to create compression session")
            return
        }
        // Configure compression settings
        for (key, value) in VideoCodecConfig.compressionProperties {
            VTSessionSetProperty(compressionSession, key: key as CFString, value: value as CFTypeRef)
        }
        // Start the compression session
        VTCompressionSessionPrepareToEncodeFrames(compressionSession)
    }

    func compressFrame(_ pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, duration: CMTime, completion: @escaping (Data?) -> Void) {
        guard let compressionSession else {
            print("Compression session is nil")
            completion(nil)
            return
        }

        var flags: VTEncodeInfoFlags = []

        compressionQueue.async {
            VTCompressionSessionEncodeFrame(
                compressionSession,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTimeStamp,
                duration: duration,
                frameProperties: nil,
                infoFlagsOut: &flags,
                outputHandler: { status, _, sampleBuffer in
                    if status == noErr, let sampleBuffer {
                        if let dataBuffer = sampleBuffer.dataBuffer {
                            var totalLength = 0
                            var dataPointer: UnsafeMutablePointer<Int8>?
                            let result = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                            if result == kCMBlockBufferNoErr, let dataPointer {
                                let data = Data(bytes: dataPointer, count: totalLength)
//                                print("Frame compressed successfully, size: \(data.count) bytes")
                                DispatchQueue.main.async {
                                    completion(data)
                                }
                            } else {
                                print("Error getting compressed data: \(result)")
                                DispatchQueue.main.async {
                                    completion(nil)
                                }
                            }
                        } else {
                            print("No data buffer in sample buffer")
                            DispatchQueue.main.async {
                                completion(nil)
                            }
                        }
                    } else {
                        print("Error compressing frame: \(status)")
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                    }
                }
            )
        }
    }
}

class VideoEncryptor {
    private var encryptionSession: EncryptionSession

    init(kasPublicKey: P256.KeyAgreement.PublicKey) {
        encryptionSession = EncryptionSession()
        encryptionSession.setupEncryption(kasPublicKey: kasPublicKey)
    }

    func encryptFrame(_ compressedData: Data, timestamp _: CMTime, width _: Int32, height _: Int32, completion: @escaping (Data?) -> Void) {
//        print("Encrypting frame")
        print("Sending frame data of length: \(compressedData.count) bytes")
        print("Sending first 32 bytes of frame data: \(compressedData.prefix(32).hexEncodedString())")
        do {
            let nanoTDFBytes = try encryptionSession.encrypt(input: compressedData)
            // Prepend timestamp to encrypted data
//            var timestampBytes = timestamp.value.bigEndian
//            encryptedData.insert(contentsOf: Data(bytes: &timestampBytes, count: MemoryLayout<Int64>.size), at: 0)
            // Prepend width and height to encrypted data
//            var widthBytes = width.bigEndian
//            var heightBytes = height.bigEndian
//            encryptedData.insert(contentsOf: Data(bytes: &heightBytes, count: MemoryLayout<Int32>.size), at: 0)
//            encryptedData.insert(contentsOf: Data(bytes: &widthBytes, count: MemoryLayout<Int32>.size), at: 0)
//            print("Frame encrypted successfully. Encrypted size: \(encryptedData.count)")
            completion(nanoTDFBytes)
        } catch {
            print("Error encrypting video frame: \(error)")
            completion(nil)
        }
    }
}

class EncryptionSession {
    private var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var iv: UInt64 = 0

    func setupEncryption(kasPublicKey: P256.KeyAgreement.PublicKey) {
        self.kasPublicKey = kasPublicKey
    }

    func encrypt(input: Data) throws -> Data {
//        print("Encrypting...")
        guard let kasPublicKey else {
            throw EncryptionError.missingKasPublicKey
        }

        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)

        // Smart contract
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

        // Increment IV for each frame
        iv += 1
        let ivData = withUnsafeBytes(of: iv.bigEndian) { Data($0) }
        // FIXME: pass int , iv: ivData
        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: input)
        return nanoTDF.toData()
    }
}

enum EncryptionError: Error {
    case missingKasPublicKey
}

class VideoDecoder {
    private var decompressionSession: VTDecompressionSession?
    private let decompressionQueue = DispatchQueue(label: "com.videodecoder.decompression")
    private var formatDescription: CMVideoFormatDescription?
    private var extractedSPS: Data?
    private var extractedPPS: Data?

    init() {
        setupFormatDescription()
    }

    private func setupFormatDescription() {
        let parameters = [
            kCVPixelBufferWidthKey: VideoCodecConfig.width,
            kCVPixelBufferHeightKey: VideoCodecConfig.height,
            kCVPixelBufferPixelFormatTypeKey: VideoCodecConfig.pixelFormat,
        ] as [String: Any]

        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: VideoCodecConfig.width,
            height: VideoCodecConfig.height,
            extensions: parameters as CFDictionary,
            formatDescriptionOut: &formatDescription
        )

        if status != noErr {
            print("Failed to create format description. Status: \(status)")
        } else {
            print("Format description created successfully")
        }
    }

    func setupDecompressionSession() {
        guard let formatDescription else {
            print("Format description is not available")
            return
        }

        var callbacks = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { (decompressionOutputRefCon: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?, status: OSStatus, _: VTDecodeInfoFlags, imageBuffer: CVImageBuffer?, _: CMTime, _: CMTime) in
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
                decoder.handleDecompressedFrame(status: status, imageBuffer: imageBuffer, completion: nil)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let decoderSpecification: [String: Any] = [:]
        let imageBufferAttributes = VideoCodecConfig.decompressionImageBufferAttributes

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: imageBufferAttributes as CFDictionary,
            outputCallback: &callbacks,
            decompressionSessionOut: &session
        )

        if status != noErr {
            print("Failed to create decompression session. Status: \(status)")
        }

        decompressionSession = session
    }

    func decodeFrame(_ frameData: Data, completion _: @escaping (UIImage?) -> Void) {
        print("Received frame data of length: \(frameData.count) bytes")
        print("First 32 bytes of frame data: \(frameData.prefix(32).hexEncodedString())")
        // If we haven't set up the decompression session yet, try to extract parameter sets and set it up
        if decompressionSession == nil {
            setupDecompressionSession()
        }
        decompressionQueue.async { [weak self] in
            guard let self, let decompressionSession else {
                print("Decompression session is nil")
                return
            }

            var blockBuffer: CMBlockBuffer?
            var sampleBuffer: CMSampleBuffer?

            let result = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: frameData.count,
                blockAllocator: nil,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: frameData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard result == kCMBlockBufferNoErr, let blockBuffer else {
                print("Failed to create block buffer")
                return
            }

            frameData.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                guard let baseAddress = bufferPointer.baseAddress else { return }
                CMBlockBufferReplaceDataBytes(with: baseAddress, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: frameData.count)
            }

            var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime.invalid, decodeTimeStamp: CMTime.invalid)
            var sampleSize = frameData.count

            guard let formatDescription else {
                print("Format description is nil")
                return
            }

            let sampleBufferStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDescription,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timingInfo,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer
            )

            guard sampleBufferStatus == noErr, let sampleBuffer else {
                print("Failed to create sample buffer")
                return
            }

            var flagOut = VTDecodeInfoFlags()
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                decompressionSession,
                sampleBuffer: sampleBuffer,
                flags: [._1xRealTimePlayback],
                frameRefcon: nil,
                infoFlagsOut: &flagOut
            )

            if decodeStatus != noErr {
                print("Failed to decode frame: \(decodeStatus)")
            }
        }
    }

    private func handleDecompressedFrame(status: OSStatus, imageBuffer: CVImageBuffer?, completion: ((UIImage?) -> Void)?) {
        guard status == noErr, let imageBuffer else {
            print("Decompression failed with status: \(status)")
            completion?(nil)
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage from CIImage")
            completion?(nil)
            return
        }

        let image = UIImage(cgImage: cgImage)
        completion?(image)
    }
}

extension Notification.Name {
    static let decodedFrameReady = Notification.Name("decodedFrameReady")
}

extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}
