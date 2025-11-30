#if os(macOS)
@preconcurrency import AVFoundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Manages screen capture using AVFoundation
@MainActor
public final class ScreenCaptureManager: NSObject, Sendable {
    // MARK: - Properties

    private let captureSession: AVCaptureSession
    private var screenInput: AVCaptureScreenInput?
    private let videoOutput: AVCaptureVideoDataOutput

    private let outputQueue = DispatchQueue(label: "com.arkavo.screencapture")

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

        // Configure for high quality
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
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

    /// Starts screen capture for the specified display (or main display if nil)
    public func startCapture(displayID: CGDirectDisplayID? = nil) throws {
        #if os(macOS)
        let targetDisplay = displayID ?? CGMainDisplayID()

        // Create screen input
        guard let input = AVCaptureScreenInput(displayID: targetDisplay) else {
            throw RecorderError.screenCaptureUnavailable
        }

        input.minFrameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        input.capturesCursor = true
        input.capturesMouseClicks = false

        captureSession.beginConfiguration()

        // Remove existing input if any
        if let existingInput = screenInput {
            captureSession.removeInput(existingInput)
        }

        // Add new input
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            screenInput = input
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
        throw RecorderError.screenCaptureUnavailable
        #endif
    }

    /// Stops screen capture
    public func stopCapture() {
        Task {
            captureSession.stopRunning()

            captureSession.beginConfiguration()
            if let input = screenInput {
                captureSession.removeInput(input)
                screenInput = nil
            }
            captureSession.commitConfiguration()
        }
    }

    /// Returns available screens with display IDs
    public static func availableScreens() -> [ScreenInfo] {
        #if os(macOS)
        let mainDisplayID = CGMainDisplayID()
        let displays = NSScreen.screens

        return displays.enumerated().compactMap { index, screen in
            // Get the display ID from the screen's deviceDescription
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            return ScreenInfo(
                id: index,
                displayID: screenNumber,
                name: screen.localizedName,
                bounds: screen.frame,
                isPrimary: screenNumber == mainDisplayID
            )
        }
        #else
        return []
        #endif
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ScreenCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
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

public struct ScreenInfo: Sendable, Identifiable, Hashable {
    public let id: Int
    public let displayID: CGDirectDisplayID
    public let name: String
    public let bounds: CGRect
    public let isPrimary: Bool

    public func hash(into hasher: inout Hasher) {
        hasher.combine(displayID)
    }

    public static func == (lhs: ScreenInfo, rhs: ScreenInfo) -> Bool {
        lhs.displayID == rhs.displayID
    }
}

#endif
