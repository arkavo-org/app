import AVFoundation
import SwiftUI
import VideoToolbox
import CommonCrypto

class VideoCaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var streamingService: StreamingService?
    private var videoCompressor: VideoCompressor?
    private var videoEncryptor: VideoEncryptor?
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var isCameraActive = false
    @Published var isStreaming = false
    @Published var hasCameraAccess = false
    @Published var error: Error?

    override init() {
        super.init()
        checkCameraPermissions()
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

            // Set up video encryptor
            self?.videoEncryptor = VideoEncryptor()
            self?.videoEncryptor?.setupEncryption()
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

    func startStreaming() {
        streamingService = StreamingService()
        isStreaming = true
    }

    func stopStreaming() {
        streamingService = nil
        isStreaming = false
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming, let streamingService = streamingService else { return }
        
        videoCompressor?.compressFrame(sampleBuffer) { [weak self] compressedBuffer in
            if let compressedBuffer = compressedBuffer {
                self?.videoEncryptor?.encryptFrame(compressedBuffer) { encryptedBuffer in
                    if let encryptedBuffer = encryptedBuffer {
                        streamingService.sendVideoFrame(encryptedBuffer)
                    }
                }
            }
        }
    }
}

// Placeholder for the actual streaming service implementation
class StreamingService {
    func sendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        // Implement the actual streaming logic here
        print("Sending video frame to streaming service")
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
    private var encryptionSession: EncryptionSession?
    
    func setupEncryption() {
        encryptionSession = EncryptionSession()
        encryptionSession?.generateKey()
    }
    
    func encryptFrame(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?) -> Void) {
        guard let encryptionSession = encryptionSession,
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            completion(nil)
            return
        }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let inputBuffer = dataPointer else {
            completion(nil)
            return
        }
        
        let outputBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: length)
        encryptionSession.encrypt(input: inputBuffer, inputLength: length, output: outputBuffer)
        
        var encryptedBlockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: outputBuffer,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &encryptedBlockBuffer
        )
        
        if let encryptedBlockBuffer = encryptedBlockBuffer {
            var encryptedSampleBuffer: CMSampleBuffer?
            CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleBufferOut: &encryptedSampleBuffer)
            CMSampleBufferSetDataBuffer(encryptedSampleBuffer!, newValue: encryptedBlockBuffer)
            completion(encryptedSampleBuffer)
        } else {
            completion(nil)
        }
    }
}

class EncryptionSession {
    private var key: Data?
    private let algorithm: CCAlgorithm = CCAlgorithm(kCCAlgorithmAES)
    private let options: CCOptions = CCOptions(kCCOptionPKCS7Padding)
    private let keySize = kCCKeySizeAES256
    private let blockSize = kCCBlockSizeAES128
    
    func generateKey() {
        key = Data(count: keySize)
        key?.withUnsafeMutableBytes { keyBytes in
            if let keyBaseAddress = keyBytes.baseAddress {
                let result = SecRandomCopyBytes(kSecRandomDefault, keySize, keyBaseAddress)
                if result != errSecSuccess {
                    print("Error generating random bytes for encryption key")
                }
            }
        }
    }
    
    func encrypt(input: UnsafePointer<Int8>, inputLength: Int, output: UnsafeMutablePointer<Int8>) {
        print("Encrypting length \(inputLength)")
        guard let key = key else {
            print("Encryption key not set")
            return
        }
        
        let ivSize = kCCBlockSizeAES128
        var iv = Data(count: ivSize)
        iv.withUnsafeMutableBytes { ivBytes in
            if let ivBaseAddress = ivBytes.baseAddress {
                let result = SecRandomCopyBytes(kSecRandomDefault, ivSize, ivBaseAddress)
                if result != errSecSuccess {
                    print("Error generating random bytes for IV")
                }
            }
        }
        
        var numBytesEncrypted: Int = 0
        
        key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                let keyBaseAddress = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                let ivBaseAddress = ivBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                
                CCCrypt(CCOperation(kCCEncrypt),
                        algorithm,
                        options,
                        keyBaseAddress,
                        keySize,
                        ivBaseAddress,
                        input,
                        inputLength,
                        output,
                        inputLength + blockSize,
                        &numBytesEncrypted)
            }
        }
        
        // Prepend IV to encrypted data
        memcpy(output + ivSize, output, numBytesEncrypted)
        memcpy(output, [UInt8](iv), ivSize)
    }
}
