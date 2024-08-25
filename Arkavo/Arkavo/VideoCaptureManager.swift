import AVFoundation
import SwiftUI
import VideoToolbox
import CryptoKit
import OpenTDFKit
import Combine

class VideoCaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var streamingService: StreamingService?
    private var videoCompressor: VideoCompressor?
    private var videoEncryptor: VideoEncryptor?
    private var encryptionSession: EncryptionSession?
    private var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var kasPublicKeySubscription: AnyCancellable?
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isCameraActive = false
    @Published var isStreaming = false
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
        if let newValue = newValue {
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
                  session.canAddInput(videoInput) else {
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
            self?.videoCompressor = VideoCompressor()
            self?.videoCompressor?.setupCompression(width: Int(dimensions.width), height: Int(dimensions.height))
            // FIXME add back video compression
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
        if let kasPublicKey = kasPublicKey {
            encryptionSession?.setupEncryption(kasPublicKey: kasPublicKey)
        }
    }
    
    func startStreaming(webSocketManager: WebSocketManager) {
        streamingService = StreamingService(webSocketManager: webSocketManager)
        isStreaming = true
    }

    func stopStreaming() {
        streamingService = nil
        isStreaming = false
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming, let streamingService = streamingService, let videoEncryptor = videoEncryptor else {
            print("Streaming is not active or required services are not available")
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get pixel buffer from sample buffer")
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        videoEncryptor.encryptFrame(pixelBuffer, timestamp: timestamp) { encryptedData in
            if let encryptedData = encryptedData {
                print("Frame encrypted successfully. Sending frame of size: \(encryptedData.count) bytes")
                streamingService.sendVideoFrame(encryptedData)
            } else {
                print("Failed to encrypt frame")
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
            if let error = error {
                print("Error sending video frame: \(error)")
            }
        }
    }
}

class VideoCompressor {
    private var compressionSession: VTCompressionSession?
    
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
        guard let compressionSession = compressionSession else {
            print("Failed to create compression session")
            return
        }
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(compressionSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)

    }
    
    func compressFrame(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?) -> Void) {
        guard let compressionSession = compressionSession,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(nil)
            return
        }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: CMTime.invalid,
            frameProperties: nil,
            infoFlagsOut: nil
        ) { status, infoFlags, compressedBuffer in
            guard status == noErr, let compressedBuffer = compressedBuffer else {
                completion(nil)
                return
            }
            completion(compressedBuffer)
        }
    }
}

class VideoEncryptor {
    private var encryptionSession: EncryptionSession
    
    init(kasPublicKey: P256.KeyAgreement.PublicKey) {
        self.encryptionSession = EncryptionSession()
        self.encryptionSession.setupEncryption(kasPublicKey: kasPublicKey)
    }
    
    func encryptFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime, completion: @escaping (Data?) -> Void) {
        print("Encrypting frame")
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Failed to get base address")
            completion(nil)
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bufferSize = bytesPerRow * height
        
        print("Frame dimensions: \(width)x\(height), Bytes per row: \(bytesPerRow), Total size: \(bufferSize)")
        
        let buffer = Data(bytes: baseAddress, count: bufferSize)
        
        do {
            var encryptedData = try encryptionSession.encrypt(input: buffer)
            
            // Prepend timestamp to encrypted data
            var timestampBytes = timestamp.value.bigEndian
            encryptedData.insert(contentsOf: Data(bytes: &timestampBytes, count: MemoryLayout<Int64>.size), at: 0)
            
            // Prepend width and height to encrypted data
            var widthBytes = Int32(width).bigEndian
            var heightBytes = Int32(height).bigEndian
            encryptedData.insert(contentsOf: Data(bytes: &heightBytes, count: MemoryLayout<Int32>.size), at: 0)
            encryptedData.insert(contentsOf: Data(bytes: &widthBytes, count: MemoryLayout<Int32>.size), at: 0)
            
            print("Frame encrypted successfully. Encrypted size: \(encryptedData.count)")
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
        print("Encrypting...")
        guard let kasPublicKey = kasPublicKey else {
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
        // FIXME pass int , iv: ivData
        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: input)
        return nanoTDF.toData()
    }
}

enum EncryptionError: Error {
    case missingKasPublicKey
}
