#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    import AVFoundation
    import CryptoKit
    import OpenTDFKit
    import UIKit

    class VideoCaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
        @Published var isCameraActive: Bool = false
        @Published var isStreaming: Bool = false
        @Published var hasCameraAccess = false
        @Published var isFrontCameraActive: Bool = false

        var captureSession: AVCaptureSession!
        var previewLayer: AVCaptureVideoPreviewLayer!
        var streamingService: StreamingService?
        var videoEncryptor: VideoEncryptor?
        var videoDecoder: VideoDecoder?
        private var frontCamera: AVCaptureDevice?
        private var backCamera: AVCaptureDevice?
        private var currentCameraInput: AVCaptureDeviceInput?
        private var videoConnection: AVCaptureConnection?

        override func viewDidLoad() {
            super.viewDidLoad()
            setupCaptureSession()
            // Add observer for orientation changes
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(orientationChanged),
                                                   name: UIDevice.orientationDidChangeNotification,
                                                   object: nil)
        }

        func setupCaptureSession() {
            captureSession = AVCaptureSession()
            captureSession.sessionPreset = .high

            // Setup back camera by default
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: backCamera)
            else {
                print("Unable to access back camera")
                return
            }

            self.backCamera = backCamera
            frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentCameraInput = input
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                // Store video connection for orientation updates
                videoConnection = videoOutput.connection(with: .video)
                updateVideoOrientation()
            }

            setupPreviewLayer()
        }

        func setupPreviewLayer() {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
            updatePreviewLayerOrientation()
        }

        @objc private func orientationChanged() {
            updateVideoOrientation()
            updatePreviewLayerOrientation()
        }

        private func updateVideoOrientation() {
            guard let videoConnection else { return }

            let currentDevice = UIDevice.current
            let orientation = currentDevice.orientation

            switch orientation {
            case .portrait:
                videoConnection.videoOrientation = .portrait
            case .portraitUpsideDown:
                videoConnection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft:
                // This might seem counterintuitive, but it's correct
                videoConnection.videoOrientation = .landscapeRight
            case .landscapeRight:
                // This might seem counterintuitive, but it's correct
                videoConnection.videoOrientation = .landscapeLeft
            default:
                videoConnection.videoOrientation = .portrait
            }
        }

        private func updatePreviewLayerOrientation() {
            guard let connection = previewLayer?.connection else { return }

            let currentDevice = UIDevice.current
            let orientation = currentDevice.orientation

            switch orientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft:
                connection.videoOrientation = .landscapeRight
            case .landscapeRight:
                connection.videoOrientation = .landscapeLeft
            default:
                connection.videoOrientation = .portrait
            }
        }

        func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
            guard isStreaming, let streamingService, let videoEncryptor else {
                return
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("Failed to get pixel buffer from sample buffer")
                return
            }

            // Convert pixel buffer to UIImage for compression
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("Failed to create CGImage")
                return
            }

            // Create UIImage with proper orientation
            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: getImageOrientation())

            // Compress the image data with JPEG compression
            guard let compressedData = image.jpegData(compressionQuality: 0.5) else {
                print("Failed to compress image")
                return
            }

            let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            videoEncryptor.encryptFrame(compressedData, timestamp: presentationTimeStamp, width: Int(image.size.width), height: Int(image.size.height)) { encryptedData in
                if let encryptedData {
                    streamingService.sendVideoFrame(encryptedData)
                } else {
                    print("Failed to encrypt frame")
                }
            }
        }

        private func getImageOrientation() -> UIImage.Orientation {
            guard let videoConnection else { return .up }

            let isUsingFrontCamera = isFrontCameraActive

            switch videoConnection.videoOrientation {
            case .portrait:
                return isUsingFrontCamera ? .leftMirrored : .right
            case .portraitUpsideDown:
                return isUsingFrontCamera ? .rightMirrored : .left
            case .landscapeRight:
                return isUsingFrontCamera ? .upMirrored : .up
            case .landscapeLeft:
                return isUsingFrontCamera ? .downMirrored : .down
            @unknown default:
                return .up
            }
        }

        func startCapture() {
            guard !isCameraActive else { return }
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

        func switchCamera() {
            guard let currentCameraInput, isCameraActive else { return }

            let newCamera = isFrontCameraActive ? backCamera : frontCamera
            guard let newInput = try? AVCaptureDeviceInput(device: newCamera!) else { return }

            captureSession.beginConfiguration()
            captureSession.removeInput(currentCameraInput)

            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                self.currentCameraInput = newInput
            } else {
                captureSession.addInput(currentCameraInput)
            }

            captureSession.commitConfiguration()

            DispatchQueue.main.async {
                self.isFrontCameraActive.toggle()
            }
        }

        func startStreaming(viewModel _: VideoStreamViewModel) {
            streamingService = StreamingService(webSocketManager: WebSocketManager.shared)
            if let kasPublicKey = ArkavoService.kasPublicKey {
                videoEncryptor = VideoEncryptor(kasPublicKey: kasPublicKey)
            } else {
                print("Error: Unable to get KAS public key for video encryption")
            }
            isStreaming = true
        }

        func stopStreaming() {
            streamingService = nil
            videoEncryptor = nil
            isStreaming = false
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer.frame = view.bounds
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

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func encrypt(input: Data) throws -> Data {
            guard let kasPublicKey else {
                throw EncryptionError.missingKasPublicKey
            }
            let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
            let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)

            // Smart contract
            let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: ArkavoPolicy.PolicyType.videoFrame.rawValue)!
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
        func decodeFrame(_ frameData: Data, completion: @escaping (UIImage?) -> Void) {
            // Decode JPEG data directly to UIImage
            if let image = UIImage(data: frameData) {
                completion(image)
            } else {
                print("Failed to decode JPEG data")
                completion(nil)
            }
        }
    }
#endif
