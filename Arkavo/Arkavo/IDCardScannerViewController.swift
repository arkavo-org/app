import AVFoundation
import SwiftUI
import UIKit
import Vision

// MARK: - Camera View Controller

class IDCardScannerViewController: UIViewController {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rectangleLayer = CAShapeLayer()
    private var lastCapturedImage: UIImage?
    private weak var delegate: IDCardScannerDelegate?
    private let sessionQueue = DispatchQueue(label: "com.app.camera.session")

    init(delegate: IDCardScannerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        // Setup camera on background thread
        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.startSession()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.stopSession()
        }
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession else { return }

        // Set highest quality preset
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        }

        guard let camera = AVCaptureDevice.default(for: .video) else { return }

        do {
            // Configure camera for highest resolution
            try camera.lockForConfiguration()

            // Get the highest resolution format available
            let formats = camera.formats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let width = CGFloat(dimensions.width)
                let height = CGFloat(dimensions.height)

                // Filter for formats that support high resolution (e.g., 4K or higher)
                return width >= 3840 && height >= 2160 // 4K minimum
            }.sorted { format1, format2 in
                let dim1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription)
                let dim2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription)
                return dim1.width * dim1.height > dim2.width * dim2.height
            }

            if let bestFormat = formats.first {
                camera.activeFormat = bestFormat

                // Set maximum frame rate for the selected format
                let maxRate = bestFormat.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(maxRate))
            }

            // Enable auto-focus
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }

            // Enable auto-exposure
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }

            camera.unlockForConfiguration()

            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: sessionQueue)

            // Set highest quality pixel format
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]

            // Avoid frame dropping
            output.alwaysDiscardsLateVideoFrames = false

            if captureSession.canAddInput(input), captureSession.canAddOutput(output) {
                captureSession.addInput(input)
                captureSession.addOutput(output)

                // Setup preview layer on main thread
                DispatchQueue.main.async { [weak self] in
                    self?.setupPreviewLayer()
                }
            }
        } catch {
            print("Debug: Camera configuration error: \(error)")
        }
    }

    private func setupPreviewLayer() {
        guard let captureSession else { return }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        // Add rectangle layer for card detection
        rectangleLayer.fillColor = UIColor.clear.cgColor
        rectangleLayer.strokeColor = UIColor.green.cgColor
        rectangleLayer.lineWidth = 2
        view.layer.addSublayer(rectangleLayer)
    }

    private func setupUI() {
        // Add capture button
        let captureButton = UIButton(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        captureButton.center = CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 100)
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        // Add cancel button
        let cancelButton = UIButton(frame: CGRect(x: 20, y: 40, width: 60, height: 40))
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
    }

    private func startSession() {
        captureSession?.startRunning()
    }

    private func stopSession() {
        captureSession?.stopRunning()
    }

    @objc private func captureButtonTapped() {
        guard let lastImage = lastCapturedImage else {
            print("Debug: No image captured")
            return
        }

        print("Debug: Image captured, dimensions: \(lastImage.size)")

        // Show processing indicator
        showProcessingOverlay()

        // Process the image on background queue
        sessionQueue.async { [weak self] in
            print("Debug: Starting image processing on background queue")
            self?.processIDCardImage(lastImage) { result in
                DispatchQueue.main.async {
                    self?.hideProcessingOverlay()

                    switch result {
                    case let .success(image):
                        print("Debug: Successfully processed image")
                        self?.delegate?.idCardScanner(self!, didCaptureImage: image)
                    case let .failure(error):
                        print("Debug: Failed to process image: \(error)")
                        self?.handleScanError(error)
                    }
                }
            }
        }
    }

    @objc private func cancelButtonTapped() {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.idCardScannerDidCancel(self!)
        }
    }
}

// MARK: - AVCapture Delegate

extension IDCardScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        let rectangleRequest = VNDetectRectanglesRequest { [weak self] request, _ in
            guard let results = request.results as? [VNRectangleObservation],
                  let rectangle = results.first else { return }

            DispatchQueue.main.async {
                self?.updateRectangleFrame(rectangle)
            }

            // Convert buffer to UIImage and store it
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                self?.lastCapturedImage = UIImage(cgImage: cgImage)
            }
        }

        rectangleRequest.minimumAspectRatio = 0.5
        rectangleRequest.maximumAspectRatio = 1.0
        rectangleRequest.minimumSize = 0.5
        rectangleRequest.maximumObservations = 1

        try? imageRequestHandler.perform([rectangleRequest])
    }

    private func updateRectangleFrame(_ rectangle: VNRectangleObservation) {
        guard let previewLayer else { return }

        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: rectangle.boundingBox)
        let path = UIBezierPath()

        // Convert normalized points to layer coordinates
        let topLeft = CGPoint(
            x: convertedRect.minX + (convertedRect.width * rectangle.topLeft.x),
            y: convertedRect.minY + (convertedRect.height * (1 - rectangle.topLeft.y))
        )
        let topRight = CGPoint(
            x: convertedRect.minX + (convertedRect.width * rectangle.topRight.x),
            y: convertedRect.minY + (convertedRect.height * (1 - rectangle.topRight.y))
        )
        let bottomRight = CGPoint(
            x: convertedRect.minX + (convertedRect.width * rectangle.bottomRight.x),
            y: convertedRect.minY + (convertedRect.height * (1 - rectangle.bottomRight.y))
        )
        let bottomLeft = CGPoint(
            x: convertedRect.minX + (convertedRect.width * rectangle.bottomLeft.x),
            y: convertedRect.minY + (convertedRect.height * (1 - rectangle.bottomLeft.y))
        )

        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.close()

        rectangleLayer.path = path.cgPath
    }
}

// MARK: - Scanner Delegate

protocol IDCardScannerDelegate: AnyObject {
    func idCardScanner(_ scanner: IDCardScannerViewController, didCaptureImage image: UIImage)
    func idCardScannerDidCancel(_ scanner: IDCardScannerViewController)
}

// MARK: - SwiftUI Wrapper

struct IDCardScannerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> IDCardScannerViewController {
        IDCardScannerViewController(delegate: context.coordinator)
    }

    func updateUIViewController(_: IDCardScannerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, IDCardScannerDelegate {
        let parent: IDCardScannerView

        init(_ parent: IDCardScannerView) {
            self.parent = parent
        }

        func idCardScanner(_: IDCardScannerViewController, didCaptureImage image: UIImage) {
            parent.onCapture(image)
        }

        func idCardScannerDidCancel(_: IDCardScannerViewController) {
            parent.onCancel()
        }
    }
}

enum ScanError: Error {
    case noDOBFound
    case underAge
    case invalidDOBFormat
    case extractionFailed
}

extension IDCardScannerViewController {
    private func processIDCardImage(_ image: UIImage, completion: @escaping (Result<UIImage, Error>) -> Void) {
        print("Debug: Beginning processIDCardImage")

        guard let cgImage = image.cgImage else {
            print("Debug: Failed to get CGImage from UIImage")
            completion(.failure(ScanError.extractionFailed))
            return
        }

        print("Debug: CGImage created successfully, size: \(cgImage.width)x\(cgImage.height)")

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        print("Debug: Created VNImageRequestHandler")
        let textRequest = VNRecognizeTextRequest { request, error in
            print("Debug: Text recognition completed")
            if let error {
                print("Debug: Text recognition error: \(error)")
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("Debug: No text observations found")
                completion(.failure(ScanError.extractionFailed))
                return
            }
            print("Debug: Found \(observations.count) text observations")
            // Print all recognized text for debugging
            print("Debug: Recognized text:")
            for (index, observation) in observations.enumerated() {
                if let text = observation.topCandidates(1).first?.string {
                    print("Debug: Text \(index): '\(text)'")
                }
            }
            // Extract and validate DOB
            if let dob = self.extractDateOfBirth(from: observations) {
                print("Debug: Found DOB: \(dob)")
                if self.isOver18(dob) {
                    completion(.success(image))
                } else {
                    completion(.failure(ScanError.underAge))
                }
            } else {
                completion(.failure(ScanError.noDOBFound))
            }
        }

        // Configure text recognition request
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        do {
            try requestHandler.perform([textRequest])
        } catch {
            completion(.failure(error))
        }
    }

    private func extractDateOfBirth(from observations: [VNRecognizedTextObservation]) -> Date? {
        let datePatterns = [
            "\\d{2}/\\d{2}/\\d{4}", // DD/MM/YYYY
            "\\d{2}-\\d{2}-\\d{4}", // DD-MM-YYYY
            "\\d{4}/\\d{2}/\\d{2}", // YYYY/MM/DD
            "\\d{4}-\\d{2}-\\d{2}", // YYYY-MM-DD
            "\\d{1,2}\\s(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s\\d{4}", // DD MMM YYYY
        ]

        let dateFormatters: [DateFormatter] = [
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "yyyy/MM/dd",
            "yyyy-MM-dd",
            "d MMM yyyy",
        ].map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            return formatter
        }

        for observation in observations {
            let recognizedText = observation.topCandidates(1).first?.string ?? ""

            for (patternIndex, pattern) in datePatterns.enumerated() {
                if let range = recognizedText.range(of: pattern, options: .regularExpression) {
                    let dateString = String(recognizedText[range])
                    if let date = dateFormatters[patternIndex].date(from: dateString) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private func isOver18(_ dob: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)
        return ageComponents.year ?? 0 >= 18
    }

    private func handleScanError(_ error: Error) {
        var message = "Failed to process ID card."

        if let scanError = error as? ScanError {
            switch scanError {
            case .noDOBFound:
                message = "Could not find date of birth on ID card. Please try again."
            case .underAge:
                message = "Must be 18 or older to proceed."
            case .invalidDOBFormat:
                message = "Invalid date of birth format. Please try again."
            case .extractionFailed:
                message = "Failed to extract information from ID card. Please try again."
            }
        }

        let alert = UIAlertController(
            title: "Verification Failed",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showProcessingOverlay() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        overlay.tag = 100

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.center = overlay.center
        spinner.startAnimating()

        overlay.addSubview(spinner)
        view.addSubview(overlay)
    }

    private func hideProcessingOverlay() {
        view.viewWithTag(100)?.removeFromSuperview()
    }
}

// Update AgeVerificationManager to handle new error cases
extension AgeVerificationManager {
    func processCapturedImage(_ image: UIImage) async {
        do {
            let cardData = try await idVerificationManager.processIDCard(image: image)

            // Additional age verification check
            guard let dateOfBirth = cardData.dateOfBirth,
                  let dobDate = parseDate(dateOfBirth),
                  isOver18(dobDate)
            else {
                await MainActor.run {
                    isVerifying = false
                    verificationStatus = .failed
                }
                return
            }

            // Continue with selfie verification
            await MainActor.run {
                promptForSelfie(cardData: cardData)
            }
        } catch {
            await MainActor.run {
                isVerifying = false
                verificationStatus = .failed
            }
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd" // Adjust format based on your ID card date format
        return dateFormatter.date(from: dateString)
    }

    private func isOver18(_ dob: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)
        return ageComponents.year ?? 0 >= 18
    }
}
