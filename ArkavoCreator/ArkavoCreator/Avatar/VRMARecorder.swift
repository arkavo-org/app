//
//  VRMARecorder.swift
//  ArkavoCreator
//
//  VRMA recording infrastructure for capturing ARKit face/body data
//  and exporting to VRMA format.
//

import Foundation
import simd
import VRMMetalKit

/// State machine for recording
public enum VRMARecordingState: Sendable {
    case idle
    case recording
    case stopped
}

/// Quality metrics updated during recording
public struct CaptureQuality: Sendable {
    /// Number of frames with body tracking data
    public var framesWithBody: Int = 0

    /// Number of frames without body tracking data
    public var framesWithoutBody: Int = 0

    /// Current consecutive frame drops
    public var consecutiveDrops: Int = 0

    /// Maximum consecutive frame drops seen
    public var maxConsecutiveDrops: Int = 0

    /// Ratio of frames with body tracking (0.0 - 1.0)
    public var bodyTrackingRatio: Float {
        let total = framesWithBody + framesWithoutBody
        return total > 0 ? Float(framesWithBody) / Float(total) : 0
    }

    /// Whether capture quality meets minimum requirements
    /// - At least 70% of frames have body tracking
    /// - No more than 30 consecutive dropped frames (1 second at 30fps)
    public var isAdequate: Bool {
        return bodyTrackingRatio >= 0.7 && maxConsecutiveDrops < 30
    }

    public init() {}
}

/// A single frame of VRMA data
public struct VRMAFrame: Sendable {
    /// Time offset from recording start in seconds
    public let time: Float

    /// ARKit face blend shapes (52 shapes)
    public let faceBlendShapes: [String: Float]?

    /// Head transform from ARKit face tracking
    public let headTransform: simd_float4x4?

    /// Body joint rotations mapped to VRM humanoid bones
    public let bodyJoints: [VRMHumanoidBone: simd_quatf]?

    /// Hips translation (root motion)
    public let hipsTranslation: simd_float3?

    public init(
        time: Float,
        faceBlendShapes: [String: Float]? = nil,
        headTransform: simd_float4x4? = nil,
        bodyJoints: [VRMHumanoidBone: simd_quatf]? = nil,
        hipsTranslation: simd_float3? = nil
    ) {
        self.time = time
        self.faceBlendShapes = faceBlendShapes
        self.headTransform = headTransform
        self.bodyJoints = bodyJoints
        self.hipsTranslation = hipsTranslation
    }
}

/// A completed motion capture session ready for export
public struct VRMASession: Sendable {
    /// Session name (used for export filename)
    public let name: String

    /// Total duration in seconds
    public let duration: Float

    /// Target frame rate
    public let frameRate: Int

    /// All captured frames
    public let frames: [VRMAFrame]

    /// Creation timestamp
    public let createdAt: Date

    public init(name: String, duration: Float, frameRate: Int, frames: [VRMAFrame], createdAt: Date = Date()) {
        self.name = name
        self.duration = duration
        self.frameRate = frameRate
        self.frames = frames
        self.createdAt = createdAt
    }

    /// Number of frames captured
    public var frameCount: Int { frames.count }

    /// Actual frame rate achieved
    public var actualFrameRate: Float {
        guard duration > 0 else { return 0 }
        return Float(frames.count) / duration
    }
}

/// Records ARKit face and body tracking data for export to VRMA
@MainActor
public class VRMARecorder: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var state: VRMARecordingState = .idle
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var frameCount: Int = 0
    @Published public private(set) var captureQuality = CaptureQuality()

    // MARK: - Recording State

    private var frames: [VRMAFrame] = []
    private var startTime: Date?
    private var targetFrameRate: Int = 30
    private var lastFrameTime: TimeInterval = 0
    private let minFrameInterval: TimeInterval

    // MARK: - Initialization

    public init(frameRate: Int = 30) {
        self.targetFrameRate = frameRate
        self.minFrameInterval = 1.0 / Double(frameRate)
    }

    // MARK: - Recording Control

    /// Start a new recording session
    public func startRecording() {
        guard state == .idle else { return }

        frames.removeAll()
        startTime = Date()
        lastFrameTime = 0
        frameCount = 0
        recordingDuration = 0
        captureQuality = CaptureQuality()
        state = .recording

        debugLog("[VRMARecorder] Recording started at \(targetFrameRate) fps")
    }

    /// Stop recording and return the captured session
    /// - Parameter name: Name for the session (used in export filename)
    /// - Returns: The completed VRMASession
    public func stopRecording(name: String = "recording") -> VRMASession {
        guard state == .recording, let start = startTime else {
            return VRMASession(name: name, duration: 0, frameRate: targetFrameRate, frames: [])
        }

        state = .stopped
        let duration = Float(Date().timeIntervalSince(start))

        let session = VRMASession(
            name: name,
            duration: duration,
            frameRate: targetFrameRate,
            frames: frames,
            createdAt: start
        )

        debugLog("[VRMARecorder] Recording stopped: \(frames.count) frames, \(String(format: "%.2f", duration))s")

        // Reset for next recording
        frames.removeAll()
        startTime = nil
        state = .idle

        return session
    }

    /// Cancel recording without saving
    public func cancelRecording() {
        frames.removeAll()
        startTime = nil
        frameCount = 0
        recordingDuration = 0
        captureQuality = CaptureQuality()
        state = .idle

        debugLog("[VRMARecorder] Recording cancelled")
    }

    // MARK: - Frame Capture

    /// Append a frame with face tracking data
    /// - Parameters:
    ///   - face: ARKit face blend shapes
    ///   - timestamp: Event timestamp
    public func appendFaceFrame(face: ARKitFaceBlendShapes, timestamp: Date) {
        guard state == .recording, let start = startTime else { return }

        let time = timestamp.timeIntervalSince(start)

        // Rate limiting
        guard time - lastFrameTime >= minFrameInterval else { return }

        let frame = VRMAFrame(
            time: Float(time),
            faceBlendShapes: face.shapes,
            headTransform: face.headTransform
        )

        frames.append(frame)
        lastFrameTime = time
        frameCount = frames.count
        recordingDuration = time
    }

    /// Append a frame with body tracking data
    /// - Parameters:
    ///   - body: ARKit body skeleton
    ///   - timestamp: Event timestamp
    public func appendBodyFrame(body: ARKitBodySkeleton, timestamp: Date) {
        guard state == .recording, let start = startTime else { return }

        let time = timestamp.timeIntervalSince(start)

        // Rate limiting
        guard time - lastFrameTime >= minFrameInterval else { return }

        // Track capture quality
        if body.joints.isEmpty {
            captureQuality.framesWithoutBody += 1
            captureQuality.consecutiveDrops += 1
            captureQuality.maxConsecutiveDrops = max(
                captureQuality.maxConsecutiveDrops,
                captureQuality.consecutiveDrops
            )
        } else {
            captureQuality.framesWithBody += 1
            captureQuality.consecutiveDrops = 0
        }

        // Convert ARKitBodySkeleton joint transforms to VRM bone rotations
        let (rotations, hipsTranslation) = convertBodyToVRMBones(body)

        let frame = VRMAFrame(
            time: Float(time),
            bodyJoints: rotations,
            hipsTranslation: hipsTranslation
        )

        frames.append(frame)
        lastFrameTime = time
        frameCount = frames.count
        recordingDuration = time
    }

    /// Append a frame with already-processed VRM bone rotations
    ///
    /// Use this method to capture rotations that have already been processed
    /// by ARKitBodyDriver (coordinate conversion, local rotation, smoothing applied).
    /// This avoids duplicate conversion and captures exactly what the avatar displays.
    ///
    /// - Parameters:
    ///   - rotations: Processed bone rotations from VRMNode.rotation
    ///   - hipsTranslation: Hips translation for root motion
    ///   - faceBlendShapes: Optional face blend shape weights
    ///   - timestamp: Event timestamp
    public func appendProcessedFrame(
        rotations: [VRMHumanoidBone: simd_quatf],
        hipsTranslation: simd_float3?,
        faceBlendShapes: [String: Float]?,
        timestamp: Date
    ) {
        guard state == .recording, let start = startTime else { return }

        let time = timestamp.timeIntervalSince(start)

        // Rate limiting
        guard time - lastFrameTime >= minFrameInterval else { return }

        // Track capture quality for body data
        if rotations.isEmpty {
            captureQuality.framesWithoutBody += 1
            captureQuality.consecutiveDrops += 1
            captureQuality.maxConsecutiveDrops = max(
                captureQuality.maxConsecutiveDrops,
                captureQuality.consecutiveDrops
            )
        } else {
            captureQuality.framesWithBody += 1
            captureQuality.consecutiveDrops = 0
        }

        let frame = VRMAFrame(
            time: Float(time),
            faceBlendShapes: faceBlendShapes,
            headTransform: nil,  // Not needed when using processed rotations
            bodyJoints: rotations,
            hipsTranslation: hipsTranslation
        )

        frames.append(frame)
        lastFrameTime = time
        frameCount = frames.count
        recordingDuration = time
    }

    /// Append a combined frame with both face and body data
    /// - Parameters:
    ///   - face: ARKit face blend shapes (optional)
    ///   - body: ARKit body skeleton (optional)
    ///   - timestamp: Event timestamp
    public func appendFrame(
        face: ARKitFaceBlendShapes?,
        body: ARKitBodySkeleton?,
        timestamp: Date
    ) {
        guard state == .recording, let start = startTime else { return }

        let time = timestamp.timeIntervalSince(start)

        // Rate limiting
        guard time - lastFrameTime >= minFrameInterval else { return }

        // Track capture quality for body data
        if let body = body {
            if body.joints.isEmpty {
                captureQuality.framesWithoutBody += 1
                captureQuality.consecutiveDrops += 1
                captureQuality.maxConsecutiveDrops = max(
                    captureQuality.maxConsecutiveDrops,
                    captureQuality.consecutiveDrops
                )
            } else {
                captureQuality.framesWithBody += 1
                captureQuality.consecutiveDrops = 0
            }
        }

        var rotations: [VRMHumanoidBone: simd_quatf]?
        var hipsTranslation: simd_float3?

        if let body = body {
            (rotations, hipsTranslation) = convertBodyToVRMBones(body)
        }

        let frame = VRMAFrame(
            time: Float(time),
            faceBlendShapes: face?.shapes,
            headTransform: face?.headTransform,
            bodyJoints: rotations,
            hipsTranslation: hipsTranslation
        )

        frames.append(frame)
        lastFrameTime = time
        frameCount = frames.count
        recordingDuration = time
    }

    // MARK: - Diagnostics

    /// Diagnostics callback for VRM mapping stage capture
    public typealias VRMMappingDiagnosticsCallback = (
        _ inputJoints: [ARKitJoint: simd_float4x4],
        _ outputRotations: [VRMHumanoidBone: simd_quatf],
        _ missingParentJoints: [String],
        _ usedFallback: Set<VRMHumanoidBone>,
        _ hipsTranslation: simd_float3?
    ) -> Void

    /// Optional diagnostics callback - set by external recorder
    public var diagnosticsCallback: VRMMappingDiagnosticsCallback?

    // MARK: - Body Conversion

    /// Convert ARKit body skeleton to VRM humanoid bone rotations
    ///
    /// Uses ARKitToVRMConverter for consistent conversion with live preview.
    private func convertBodyToVRMBones(_ skeleton: ARKitBodySkeleton) -> ([VRMHumanoidBone: simd_quatf], simd_float3?) {
        var missingParentJoints: [String] = []
        var usedFallback: Set<VRMHumanoidBone> = []
        
        // Use the new ARKitToVRMConverter for all conversion logic
        let (rotations, hipsTranslation) = ARKitToVRMConverter.convertWithDiagnostics(
            skeleton: skeleton,
            onUnmappedJoint: { joint in
                if let parentJoint = ARKitToVRMConverter.arkitParentMap[joint] {
                    missingParentJoints.append(parentJoint.rawValue)
                }
                if let vrmBone = ARKitToVRMConverter.jointToBoneMap[joint] {
                    usedFallback.insert(vrmBone)
                }
            }
        )

        // Call diagnostics callback if set
        diagnosticsCallback?(
            skeleton.joints,
            rotations,
            missingParentJoints,
            usedFallback,
            hipsTranslation
        )

        return (rotations, hipsTranslation)
    }
}
