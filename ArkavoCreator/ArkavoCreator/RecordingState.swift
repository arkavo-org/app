import Foundation
import SwiftUI
import ArkavoRecorder

/// Shared recording state accessible across the app
@MainActor
@Observable
final class RecordingState {
    // Singleton instance
    static let shared = RecordingState()

    // Current recording session (if any)
    private(set) var recordingSession: RecordingSession?

    private init() {}

    /// Set the active recording session
    func setRecordingSession(_ session: RecordingSession?) {
        self.recordingSession = session
    }

    /// Get the active recording session
    func getRecordingSession() -> RecordingSession? {
        return recordingSession
    }

    /// Check if currently recording
    var isRecording: Bool {
        recordingSession?.isRecording ?? false
    }
}
