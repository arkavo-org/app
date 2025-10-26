@preconcurrency import AVFoundation
import Foundation
import ArkavoStreaming

/// Coordinates screen, camera, and audio capture with composition and encoding
@MainActor
public final class RecordingSession: Sendable {
    // MARK: - Properties

    private let screenCapture: ScreenCaptureManager
    private let cameraCapture: CameraManager
    private let audioCapture: AudioManager
    nonisolated(unsafe) private let compositor: CompositorManager
    nonisolated(unsafe) private let encoder: VideoEncoder

    nonisolated(unsafe) public var isRecording: Bool {
        encoder.isRecording
    }

    public var duration: TimeInterval {
        encoder.duration
    }

    nonisolated(unsafe) public var audioLevel: Float = 0.0

    // Configuration
    public var pipPosition: PiPPosition {
        get { compositor.pipPosition }
        set { compositor.pipPosition = newValue }
    }

    public var watermarkEnabled: Bool {
        get { compositor.watermarkEnabled }
        set { compositor.watermarkEnabled = newValue }
    }

    public var watermarkPosition: WatermarkPosition {
        get { compositor.watermarkPosition }
        set { compositor.watermarkPosition = newValue }
    }

    public var watermarkOpacity: Float {
        get { compositor.watermarkOpacity }
        set { compositor.watermarkOpacity = newValue }
    }

    nonisolated(unsafe) public var enableCamera: Bool = true
    nonisolated(unsafe) public var enableMicrophone: Bool = true

    // MARK: - Initialization

    public init() throws {
        self.screenCapture = ScreenCaptureManager()
        self.cameraCapture = CameraManager()
        self.audioCapture = AudioManager()
        self.compositor = try CompositorManager()
        self.encoder = VideoEncoder()

        setupCapture()
    }

    // MARK: - Setup

    private nonisolated func setupCapture() {
        // Wire up screen capture
        screenCapture.onFrame = { @Sendable [weak self] screenBuffer in
            // Process asynchronously to handle encoding
            // Note: CMSampleBuffer is not Sendable, but we process it immediately without retaining
            Task {
                await self?.processFrameSync(screen: screenBuffer)
            }
        }

        // Wire up camera capture
        cameraCapture.onFrame = { @Sendable [weak self] cameraBuffer in
            // Store latest camera frame immediately
            self?.latestCameraBuffer = cameraBuffer
        }

        // Wire up audio capture
        audioCapture.onSample = { @Sendable [weak self] audioSample in
            // Process asynchronously to handle encoding
            // Note: CMSampleBuffer is not Sendable, but we process it immediately without retaining
            Task {
                await self?.processAudioSampleSync(audioSample)
            }
        }

        audioCapture.onLevelUpdate = { @Sendable [weak self] level in
            self?.audioLevel = level
        }
    }

    // MARK: - Recording Control

    /// Starts a new recording session
    public func startRecording(outputURL: URL, title: String) async throws {
        // Request permissions
        guard await requestPermissions() else {
            throw RecorderError.permissionDenied
        }

        // Start captures
        try screenCapture.startCapture()

        if enableCamera {
            try? cameraCapture.startCapture()
        }

        if enableMicrophone {
            try? audioCapture.startCapture()
        }

        // Start encoder
        try await encoder.startRecording(to: outputURL, title: title)
    }

    /// Stops the current recording session
    public func stopRecording() async throws -> URL {
        // Stop captures
        screenCapture.stopCapture()
        cameraCapture.stopCapture()
        audioCapture.stopCapture()

        // Finish encoding
        return try await encoder.finishRecording()
    }

    /// Pauses the current recording
    public func pauseRecording() {
        encoder.pause()
    }

    /// Resumes a paused recording
    public func resumeRecording() {
        encoder.resume()
    }

    // MARK: - Private Methods

    private func requestPermissions() async -> Bool {
        // Always need screen recording permission (handled by system)

        if enableCamera {
            guard await CameraManager.requestPermission() else {
                return false
            }
        }

        if enableMicrophone {
            guard await AudioManager.requestPermission() else {
                return false
            }
        }

        return true
    }

    nonisolated(unsafe) private var latestCameraBuffer: CMSampleBuffer?

    private nonisolated func processFrameSync(screen screenBuffer: CMSampleBuffer) async {
        guard encoder.isRecording else { return }

        // Composite with camera if enabled
        let cameraBuffer = enableCamera ? latestCameraBuffer : nil
        guard let composited = compositor.composite(screen: screenBuffer, camera: cameraBuffer) else {
            return
        }

        // Encode the composited frame
        let timestamp = CMSampleBufferGetPresentationTimeStamp(screenBuffer)
        await encoder.encodeVideoFrame(composited, timestamp: timestamp)
    }

    private nonisolated func processAudioSampleSync(_ audioSample: CMSampleBuffer) async {
        guard encoder.isRecording, enableMicrophone else { return }

        // Encode audio
        await encoder.encodeAudioSample(audioSample)
    }

    // MARK: - Public Utilities

    /// Get available screens
    public static func availableScreens() -> [ScreenInfo] {
        return ScreenCaptureManager.availableScreens()
    }

    /// Get available cameras
    public static func availableCameras() -> [CameraInfo] {
        return CameraManager.availableCameras()
    }

    /// Get available microphones
    public static func availableMicrophones() -> [AudioDeviceInfo] {
        return AudioManager.availableMicrophones()
    }

    /// Get camera preview session
    public func getCameraPreview() -> AVCaptureSession {
        return cameraCapture.getPreviewSession()
    }

    // MARK: - Streaming

    /// Start streaming to RTMP destination
    public func startStreaming(to destination: RTMPPublisher.Destination, streamKey: String) async throws {
        try await encoder.startStreaming(to: destination, streamKey: streamKey)
    }

    /// Stop streaming
    public func stopStreaming() async {
        await encoder.stopStreaming()
    }

    /// Get streaming statistics
    public var streamStatistics: RTMPPublisher.StreamStatistics? {
        get async {
            return await encoder.streamStatistics
        }
    }

    /// Check if currently streaming
    public var isStreaming: Bool {
        get async {
            if let stats = await encoder.streamStatistics {
                return stats.framesSent > 0
            }
            return false
        }
    }
}
