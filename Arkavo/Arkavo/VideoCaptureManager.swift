#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
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
        public var videoDecoder: VideoDecoder?
        private var videoWidth = 80
        private var videoHeight = 80
        private var videoEncryptor: VideoEncryptor?
        private var encryptionSession: EncryptionSession?
        private var kasPublicKey: P256.KeyAgreement.PublicKey?
        private var kasPublicKeySubscription: AnyCancellable?
        private var currentOrientation: UIInterfaceOrientation = .portrait
        private var orientationObserver: NSObjectProtocol?
        @Published var previewLayer: AVCaptureVideoPreviewLayer?
        @Published var isCameraActive = false
        @Published var isStreaming = false
        @Published var isConnected = false
        @Published var hasCameraAccess = false
        @Published var error: Error?
        @Published var unCompressionFrame: UIImage?

        private var cancellables = Set<AnyCancellable>()
        private let videoEncryptorQueue = DispatchQueue(label: "com.yourapp.videoEncryptorQueue")

        override init() {
            super.init()
            checkCameraPermissions()
            videoDecoder = VideoDecoder()
            setupOrientationObserver()
        }

        deinit {
            if let observer = orientationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func setupOrientationObserver() {
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didChangeStatusBarOrientationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateForOrientation()
            }
        }

        private func updateForOrientation() {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let newOrientation = windowScene.interfaceOrientation
            guard newOrientation != currentOrientation else { return }

            switch newOrientation {
            case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
                currentOrientation = newOrientation
                updateVideoOrientation()
            default:
                break
            }
        }

        private func updateVideoOrientation() {
            guard let connection = videoOutput?.connection(with: .video) else { return }

            let videoOrientation: AVCaptureVideoOrientation = switch currentOrientation {
            case .portrait:
                .portrait
            case .portraitUpsideDown:
                .portraitUpsideDown
            case .landscapeLeft:
                .landscapeRight
            case .landscapeRight:
                .landscapeLeft
            default:
                .portrait
            }

            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }

            DispatchQueue.main.async {
                self.previewLayer?.connection?.videoOrientation = videoOrientation
            }
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
            videoEncryptorQueue.async { [weak self] in
                self?.kasPublicKey = newValue
                if let newValue {
                    self?.videoEncryptor = VideoEncryptor(kasPublicKey: newValue)
                } else {
                    self?.videoEncryptor = nil
                }
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
                guard let self else { return }

                let session = AVCaptureSession()
                session.sessionPreset = .low

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

                self.videoOutput = videoOutput
                captureSession = session

                DispatchQueue.main.async {
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    previewLayer.frame = UIScreen.main.bounds
                    self.previewLayer = previewLayer
                    self.updateVideoOrientation()
                }

                // Set up video encryptor
                DispatchQueue.main.async {
                    if let kasPublicKey = self.kasPublicKey {
                        self.videoEncryptor = VideoEncryptor(kasPublicKey: kasPublicKey)
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
                    self?.updateVideoOrientation()
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
            streamingService = StreamingService(webSocketManager: webSocketManager)
            isStreaming = true
        }

        func stopStreaming() {
            streamingService = nil
            isStreaming = false
        }

        func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
            guard isStreaming, let streamingService, let videoEncryptor else {
                return
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("Failed to get pixel buffer from sample buffer")
                return
            }
            updateVideoOrientation()

            // Define the target size
            let targetWidth = 80
            let targetHeight = 80

            // Downscale the image
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let scaleX = CGFloat(targetWidth) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let scaleY = CGFloat(targetHeight) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let context = CIContext()
            var downscaledPixelBuffer: CVPixelBuffer?

            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, targetWidth, targetHeight, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &downscaledPixelBuffer)

            if let downscaledPixelBuffer {
                if CVPixelBufferLockBaseAddress(downscaledPixelBuffer, .readOnly) == kCVReturnSuccess {
                    context.render(scaledImage, to: downscaledPixelBuffer)

                    // Convert downscaled pixel buffer to Data
                    let baseAddress = CVPixelBufferGetBaseAddress(downscaledPixelBuffer)
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(downscaledPixelBuffer)
                    let data = Data(bytes: baseAddress!, count: bytesPerRow * targetHeight)
                    CVPixelBufferUnlockBaseAddress(downscaledPixelBuffer, .readOnly)

                    let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    videoEncryptor.encryptFrame(data, timestamp: presentationTimeStamp, width: targetWidth, height: targetHeight) { encryptedData in
                        if let encryptedData {
                            streamingService.sendVideoFrame(encryptedData)
                        } else {
                            print("Failed to encrypt frame")
                        }
                    }
                } else {
                    print("Failed to lock base address of pixel buffer")
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

    class VideoEncryptor {
        private var encryptionSession: EncryptionSession

        init(kasPublicKey: P256.KeyAgreement.PublicKey) {
            encryptionSession = EncryptionSession()
            encryptionSession.setupEncryption(kasPublicKey: kasPublicKey)
        }

        func encryptFrame(_ compressedData: Data, timestamp _: CMTime, width _: Int, height _: Int, completion: @escaping (Data?) -> Void) {
            do {
                let nanoTDFBytes = try encryptionSession.encrypt(input: compressedData)
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
            // FIXME: pass int , iv: iv
            let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: input)
            return nanoTDF.toData()
        }
    }

    enum EncryptionError: Error {
        case missingKasPublicKey
    }

    class VideoDecoder {
        private var videoWidth = 80
        private var videoHeight = 80

        func decodeFrame(_ frameData: Data, completion: @escaping (UIImage?) -> Void) {
            let bytesPerRow = videoWidth * 4 // 32-bit BGRA format
            let expectedDataSize = videoHeight * bytesPerRow

            guard frameData.count == expectedDataSize else {
                print("Unexpected frame data size. Expected: \(expectedDataSize), Actual: \(frameData.count)")
                completion(nil)
                return
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

            guard let context = CGContext(data: nil,
                                          width: videoWidth,
                                          height: videoHeight,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo.rawValue)
            else {
                print("Failed to create CGContext")
                completion(nil)
                return
            }

            frameData.withUnsafeBytes { bufferPointer in
                guard let baseAddress = bufferPointer.baseAddress else {
                    completion(nil)
                    return
                }
                context.data?.copyMemory(from: baseAddress, byteCount: frameData.count)
            }

            if let cgImage = context.makeImage() {
                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                completion(image)
            } else {
                print("Failed to create CGImage")
                completion(nil)
            }
        }
    }

    extension Data {
        func hexEncodedString() -> String {
            map { String(format: "%02hhx", $0) }.joined()
        }
    }

    extension Notification.Name {
        static let decodedFrameReady = Notification.Name("decodedFrameReady")
    }
#endif
