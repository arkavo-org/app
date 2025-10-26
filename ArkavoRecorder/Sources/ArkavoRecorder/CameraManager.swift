@preconcurrency import AVFoundation
import CoreGraphics

/// Manages camera capture using AVFoundation
@MainActor
public final class CameraManager: NSObject, Sendable {
    // MARK: - Properties

    private let captureSession: AVCaptureSession
    private var cameraInput: AVCaptureDeviceInput?
    private let videoOutput: AVCaptureVideoDataOutput

    private let outputQueue = DispatchQueue(label: "com.arkavo.cameracapture")

    nonisolated(unsafe) public var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    // MARK: - Initialization

    public override init() {
        self.captureSession = AVCaptureSession()
        self.videoOutput = AVCaptureVideoDataOutput()

        super.init()

        setupSession()
    }

    // MARK: - Setup

    private func setupSession() {
        captureSession.beginConfiguration()

        // Configure for 1080p
        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        }

        // Setup video output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Public Methods

    /// Requests camera permission
    public static func requestPermission() async -> Bool {
        #if os(macOS) || os(iOS)
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }

    /// Starts camera capture with the default device
    public func startCapture() throws {
        try startCapture(with: nil)
    }

    /// Starts camera capture with a specific device
    public func startCapture(with deviceID: String?) throws {
        #if os(macOS) || os(iOS)
        // Find the camera device
        let device: AVCaptureDevice?
        if let deviceID = deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)
        }

        guard let camera = device else {
            throw RecorderError.cameraUnavailable
        }

        // Create input
        let input = try AVCaptureDeviceInput(device: camera)

        captureSession.beginConfiguration()

        // Remove existing input if any
        if let existingInput = cameraInput {
            captureSession.removeInput(existingInput)
        }

        // Add new input
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            cameraInput = input
        } else {
            captureSession.commitConfiguration()
            throw RecorderError.cannotAddInput
        }

        captureSession.commitConfiguration()

        // Start the session
        Task {
            captureSession.startRunning()
        }
        #else
        throw RecorderError.cameraUnavailable
        #endif
    }

    /// Stops camera capture
    public func stopCapture() {
        Task {
            captureSession.stopRunning()

            captureSession.beginConfiguration()
            if let input = cameraInput {
                captureSession.removeInput(input)
                cameraInput = nil
            }
            captureSession.commitConfiguration()
        }
    }

    /// Returns available cameras
    public static func availableCameras() -> [CameraInfo] {
        #if os(macOS) || os(iOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external
            ],
            mediaType: .video,
            position: .unspecified
        )

        return discoverySession.devices.map { device in
            CameraInfo(
                id: device.uniqueID,
                name: device.localizedName,
                position: device.position
            )
        }
        #else
        return []
        #endif
    }

    /// Get the capture session for preview
    public func getPreviewSession() -> AVCaptureSession {
        return captureSession
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Forward frame to handler - calling directly on callback queue
        // CMSampleBuffer is not Sendable but we handle it synchronously
        onFrame?(sampleBuffer)
    }
}

// MARK: - Supporting Types

public struct CameraInfo: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let position: AVCaptureDevice.Position

    public var displayName: String {
        switch position {
        case .front:
            return "\(name) (Front)"
        case .back:
            return "\(name) (Back)"
        default:
            return name
        }
    }
}
