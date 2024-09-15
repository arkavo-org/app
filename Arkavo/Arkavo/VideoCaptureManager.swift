#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    import AVFoundation
    import CryptoKit
    import OpenTDFKit
    import UIKit

    class VideoCaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
        @Published var isCameraActive: Bool = true
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

        override func viewDidLoad() {
            super.viewDidLoad()
            setupCaptureSession()
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
            }

            setupPreviewLayer()
        }

        func setupPreviewLayer() {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }

        func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
            guard isStreaming, let streamingService, let videoEncryptor else {
                return
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("Failed to get pixel buffer from sample buffer")
                return
            }
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
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
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

        func startStreaming(viewModel: VideoStreamViewModel) {
            let webSocketManager = viewModel.webSocketManager
            streamingService = StreamingService(webSocketManager: webSocketManager)
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
#endif
