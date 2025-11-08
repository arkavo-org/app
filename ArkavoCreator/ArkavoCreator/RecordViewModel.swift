import ArkavoC2PA
import ArkavoRecorder
import AVFoundation
import Foundation
import SwiftUI

@MainActor
@Observable
final class RecordViewModel {
    // MARK: - Recording State

    private(set) var recordingSession: RecordingSession?
    var isRecording: Bool = false
    var isPaused: Bool = false
    var duration: TimeInterval = 0.0
    var audioLevel: Float = 0.0

    // Configuration
    var title: String = ""
    var pipPosition: PiPPosition = .bottomRight
    var enableCamera: Bool = true
    var enableMicrophone: Bool = true

    // Watermark configuration
    var watermarkEnabled: Bool = true // Enabled by default per MVP spec
    var watermarkPosition: WatermarkPosition = .bottomCenter
    var watermarkOpacity: Float = 0.6

    // Status
    var error: String?
    var isProcessing: Bool = false

    // Timer for updating duration
    private var timer: Timer?

    // MARK: - Initialization

    init() {
        generateDefaultTitle()
    }

    // MARK: - Recording Control

    func startRecording() async {
        // Validate title before starting
        if let validationError = validateTitle(title) {
            error = validationError
            return
        }

        do {
            // Create recording session
            let session = try RecordingSession()
            session.pipPosition = pipPosition
            session.enableCamera = enableCamera
            session.enableMicrophone = enableMicrophone
            session.watermarkEnabled = watermarkEnabled
            session.watermarkPosition = watermarkPosition
            session.watermarkOpacity = watermarkOpacity
            recordingSession = session

            // Register with shared state for streaming access
            RecordingState.shared.setRecordingSession(session)

            // Generate output URL
            let outputURL = try generateOutputURL()

            // Start recording
            try await session.startRecording(outputURL: outputURL, title: title)

            isRecording = true
            error = nil

            // Start duration timer
            startTimer()
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
            recordingSession = nil
            RecordingState.shared.setRecordingSession(nil)
        }
    }

    func stopRecording() async {
        guard let session = recordingSession else { return }

        stopTimer()
        isProcessing = true

        do {
            let outputURL = try await session.stopRecording()

            // Sign with C2PA
            let signedURL = try await signRecording(outputURL: outputURL, recordingTitle: title, recordingDuration: duration)

            isRecording = false
            isPaused = false
            duration = 0.0
            recordingSession = nil

            // Unregister from shared state
            RecordingState.shared.setRecordingSession(nil)

            // Recording complete - saved successfully
            print("Recording saved and signed: \(signedURL.path)")

            // Post notification to refresh library
            NotificationCenter.default.post(name: .recordingCompleted, object: nil)
        } catch {
            self.error = "Failed to stop recording: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    // MARK: - C2PA Signing

    private func signRecording(outputURL: URL, recordingTitle: String, recordingDuration: TimeInterval) async throws -> URL {
        // Build C2PA manifest
        var builder = C2PAManifestBuilder(title: recordingTitle)
        _ = builder.addCreatedAction()
        _ = builder.addRecordedAction(when: Date(), duration: recordingDuration)

        // Add device metadata
        #if os(macOS)
            let deviceModel = getMacModel()
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            _ = builder.addDeviceMetadata(model: deviceModel, os: osVersion)
        #endif

        // Add author (if we have identity info - for now use app name)
        _ = builder.addAuthor(name: "Arkavo Creator")

        let manifest = builder.build()

        // Sign the recording
        let signer = try C2PASigner()
        let signedURL = outputURL.deletingPathExtension().appendingPathExtension("signed.mov")

        do {
            try await signer.sign(
                inputFile: outputURL,
                outputFile: signedURL,
                manifest: manifest,
            )

            // Replace original with signed version
            try FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: signedURL, to: outputURL)

            return outputURL
        } catch {
            // If signing fails, keep the unsigned recording
            print("C2PA signing failed: \(error.localizedDescription), keeping unsigned recording")
            return outputURL
        }
    }

    private func getMacModel() -> String {
        #if os(macOS)
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            let bytes = model.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        #else
            return "Unknown"
        #endif
    }

    func pauseRecording() {
        guard let session = recordingSession else { return }
        session.pauseRecording()
        isPaused = true
        stopTimer()
    }

    func resumeRecording() {
        guard let session = recordingSession else { return }
        session.resumeRecording()
        isPaused = false
        startTimer()
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let session = recordingSession else { return }
                duration = session.duration
                audioLevel = session.audioLevel
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Utilities

    private func generateDefaultTitle() {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        title = "Recording \(formatter.string(from: Date()))"
    }

    private func generateOutputURL() throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        // Create recordings directory if needed
        try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)

        // Generate filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "arkavo_recording_\(formatter.string(from: Date())).mov"

        return recordingsPath.appendingPathComponent(filename)
    }

    func getAvailableDevices() -> (screens: [ScreenInfo], cameras: [CameraInfo], microphones: [AudioDeviceInfo]) {
        (
            RecordingSession.availableScreens(),
            RecordingSession.availableCameras(),
            RecordingSession.availableMicrophones(),
        )
    }

    func getCameraPreview() -> AVCaptureSession? {
        recordingSession?.getCameraPreview()
    }

    // MARK: - Format Helpers

    func formattedDuration() -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func audioLevelPercentage() -> Double {
        Double(min(1.0, max(0.0, audioLevel)))
    }

    // MARK: - Input Validation

    /// Validates recording title length and characters
    /// - Parameter title: The recording title to validate
    /// - Returns: Error message if validation fails, nil if valid
    private func validateTitle(_ title: String) -> String? {
        // Check if empty (title is optional but should have fallback)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            // This is OK - will use default title
            return nil
        }

        // Check minimum length (if provided)
        if trimmedTitle.count < 3 {
            return "Recording title is too short (minimum 3 characters)"
        }

        // Check maximum length
        if trimmedTitle.count > 200 {
            return "Recording title is too long (maximum 200 characters)"
        }

        // Check for control characters
        if title.rangeOfCharacter(from: .controlCharacters) != nil {
            return "Recording title contains invalid control characters"
        }

        // Check for invalid file system characters
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if title.rangeOfCharacter(from: invalidChars) != nil {
            return "Recording title contains invalid characters (/, \\, :, *, ?, \", <, >, |)"
        }

        return nil
    }
}
