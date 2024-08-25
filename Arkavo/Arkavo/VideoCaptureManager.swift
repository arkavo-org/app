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
            self?.videoCompressor?.setupCompression(width: Int(dimensions.width), height: Int(dimensions.height))
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

    func setupCompression(width: Int, height: Int) {
        VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
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
        // Configure compression settings for real-time video
        let properties: [(CFString, Any)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue!),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse!),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, 60),
            (kVTCompressionPropertyKey_ExpectedFrameRate, 30),
            (kVTCompressionPropertyKey_AverageBitRate, 1_000_000), // 1 Mbps
            (kVTCompressionPropertyKey_DataRateLimits, [1_000_000, 1] as CFArray),
        ]
        for (key, value) in properties {
            VTSessionSetProperty(compressionSession, key: key, value: value as CFTypeRef)
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

    func encryptFrame(_ compressedData: Data, timestamp: CMTime, width: Int32, height: Int32, completion: @escaping (Data?) -> Void) {
//        print("Encrypting frame")
        do {
            var encryptedData = try encryptionSession.encrypt(input: compressedData)
            // Prepend timestamp to encrypted data
            var timestampBytes = timestamp.value.bigEndian
            encryptedData.insert(contentsOf: Data(bytes: &timestampBytes, count: MemoryLayout<Int64>.size), at: 0)
            // Prepend width and height to encrypted data
            var widthBytes = width.bigEndian
            var heightBytes = height.bigEndian
            encryptedData.insert(contentsOf: Data(bytes: &heightBytes, count: MemoryLayout<Int32>.size), at: 0)
            encryptedData.insert(contentsOf: Data(bytes: &widthBytes, count: MemoryLayout<Int32>.size), at: 0)
//            print("Frame encrypted successfully. Encrypted size: \(encryptedData.count)")
            completion(encryptedData)
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
