#if canImport(ARKit) && (os(iOS) || targetEnvironment(macCatalyst))
import ARKit
import CoreMedia

/// Metadata describing the semantic information contained in an ARKit frame.
public struct ARKitFrameMetadata {
    public let blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]?
    public let bodySkeleton: ARSkeleton3D?
    public let anchors: [ARAnchor]
}

@MainActor
public protocol ARKitCaptureManagerDelegate: AnyObject {
    func arKitCaptureManager(
        _ manager: ARKitCaptureManager,
        didOutput buffer: CVPixelBuffer,
        timestamp: CMTime,
        metadata: ARKitFrameMetadata
    )

    func arKitCaptureManager(_ manager: ARKitCaptureManager, didUpdate trackingState: ARCamera.TrackingState)
    func arKitCaptureManager(_ manager: ARKitCaptureManager, didFailWith error: Error)
}

/// Lightweight ARKit capture helper that streams ARFrame imagery plus semantic metadata.
@MainActor
public final class ARKitCaptureManager: NSObject {
    public enum Mode {
        case face
        case body
    }

    public enum CaptureError: Swift.Error, LocalizedError {
        case unsupported

        public var errorDescription: String? {
            switch self {
            case .unsupported:
                return "This device does not support the requested AR configuration."
            }
        }
    }

    private let session = ARSession()
    public weak var delegate: ARKitCaptureManagerDelegate?
    private(set) var currentMode: Mode?

    public override init() {
        super.init()
        session.delegate = self
    }

    public static func isSupported(_ mode: Mode) -> Bool {
        switch mode {
        case .face:
            return ARFaceTrackingConfiguration.isSupported
        case .body:
            if #available(iOS 13.0, *) {
                return ARBodyTrackingConfiguration.isSupported
            } else {
                return false
            }
        }
    }

    public var isRunning: Bool {
        currentMode != nil
    }

    public func start(mode: Mode) throws {
        guard Self.isSupported(mode) else {
            throw CaptureError.unsupported
        }

        currentMode = mode
        let configuration: ARConfiguration

        switch mode {
        case .face:
            let faceConfig = ARFaceTrackingConfiguration()
            faceConfig.isWorldTrackingEnabled = false
            faceConfig.providesAudioData = true  // Enable microphone for remote streaming
            configuration = faceConfig
        case .body:
            if #available(iOS 13.0, *) {
                let bodyConfig = ARBodyTrackingConfiguration()
                bodyConfig.isAutoFocusEnabled = true
                bodyConfig.frameSemantics = [.bodyDetection]
                configuration = bodyConfig
            } else {
                throw CaptureError.unsupported
            }
        }

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func stop() {
        session.pause()
        currentMode = nil
    }
}

extension ARKitCaptureManager: @preconcurrency ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let mode = currentMode else { return }

        let metadata: ARKitFrameMetadata
        switch mode {
        case .face:
            let faceAnchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
            metadata = ARKitFrameMetadata(
                blendShapes: faceAnchor?.blendShapes,
                bodySkeleton: nil,
                anchors: frame.anchors
            )
        case .body:
            if #available(iOS 13.0, *) {
                let bodyAnchor = frame.anchors.compactMap { $0 as? ARBodyAnchor }.first
                metadata = ARKitFrameMetadata(
                    blendShapes: nil,
                    bodySkeleton: bodyAnchor?.skeleton,
                    anchors: frame.anchors
                )
            } else {
                metadata = ARKitFrameMetadata(blendShapes: nil, bodySkeleton: nil, anchors: frame.anchors)
            }
        }

        let timestamp = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
        delegate?.arKitCaptureManager(
            self,
            didOutput: frame.capturedImage,
            timestamp: timestamp,
            metadata: metadata
        )
    }

    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        delegate?.arKitCaptureManager(self, didUpdate: camera.trackingState)
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        delegate?.arKitCaptureManager(self, didFailWith: error)
    }
}
#endif
