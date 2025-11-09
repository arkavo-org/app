import Foundation

public enum RecorderError: Error, Sendable {
    case screenCaptureUnavailable
    case cameraUnavailable
    case microphoneUnavailable
    case cannotAddInput
    case cannotAddOutput
    case recordingFailed
    case encodingFailed
    case permissionDenied
}
