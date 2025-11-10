import ArkavoRecorder
import Foundation

/// Utility for detecting the best ARKit mode for a device
enum ARKitModeDetector {
    /// Detects the best AR mode based on device capabilities
    /// - Returns: The recommended ARKit mode for VTuber streaming
    ///
    /// Priority:
    /// 1. Face tracking (most common VTuber use case - seated streaming with expressions)
    /// 2. Body tracking (full-body VTuber - requires phone mount)
    /// 3. Fallback to face even if unsupported (will show error during connection)
    static func detectBestMode() -> ARKitCaptureManager.Mode {
        let faceSupported = ARKitCaptureManager.isSupported(.face)
        let bodySupported = ARKitCaptureManager.isSupported(.body)

        print("📱 [ModeDetection] Face: \(faceSupported ? "✅" : "❌"), Body: \(bodySupported ? "✅" : "❌")")

        // VTuber auto-detection: Default to face mode (most common use case)
        // - Face mode: Front camera, expressions & lip sync, seated streaming
        // - Body mode: Back camera, full skeleton, standing/walking (requires phone mount)
        // - Combined mode: 2 devices, professional setup with face + body simultaneously
        if faceSupported {
            print("🎭 [ModeDetection] Selected: Face tracking (seated vtuber style)")
            return .face
        } else if bodySupported {
            print("🦴 [ModeDetection] Selected: Body tracking (full-body vtuber style)")
            return .body
        }

        // Fallback to face even if not supported (error will be shown during connection)
        print("⚠️ [ModeDetection] No ARKit support detected, defaulting to Face")
        return .face
    }

    /// Checks if a specific mode is supported on the current device
    static func isSupported(_ mode: ARKitCaptureManager.Mode) -> Bool {
        ARKitCaptureManager.isSupported(mode)
    }

    /// Returns a user-friendly description of a mode
    static func modeDescription(_ mode: ARKitCaptureManager.Mode) -> String {
        switch mode {
        case .face:
            return "Face Tracking (Front Camera)"
        case .body:
            return "Body Tracking (Back Camera)"
        case .combined:
            return "Combined (Dual Device)"
        }
    }

    /// Returns the camera used for a given mode
    static func cameraPosition(_ mode: ARKitCaptureManager.Mode) -> String {
        switch mode {
        case .face:
            return "Front"
        case .body:
            return "Back"
        case .combined:
            return "Both"
        }
    }
}
