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

        print("[VRMARecorder] Recording started at \(targetFrameRate) fps")
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

        print("[VRMARecorder] Recording stopped: \(frames.count) frames, \(String(format: "%.2f", duration))s")

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

        print("[VRMARecorder] Recording cancelled")
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

    // MARK: - Body Conversion

    /// ARKit skeleton hierarchy - defines parent-child relationships
    /// ARKit joints are in model space (relative to root), we need local rotations
    private static let arkitParentMap: [ARKitJoint: ARKitJoint] = [
        // Spine chain
        .spine: .hips,
        .chest: .spine,
        .upperChest: .chest,
        .neck: .chest,  // or upperChest if present
        .head: .neck,
        // Left arm
        .leftShoulder: .chest,
        .leftUpperArm: .leftShoulder,
        .leftLowerArm: .leftUpperArm,
        .leftHand: .leftLowerArm,
        // Right arm
        .rightShoulder: .chest,
        .rightUpperArm: .rightShoulder,
        .rightLowerArm: .rightUpperArm,
        .rightHand: .rightLowerArm,
        // Left leg
        .leftUpperLeg: .hips,
        .leftLowerLeg: .leftUpperLeg,
        .leftFoot: .leftLowerLeg,
        .leftToes: .leftFoot,
        // Right leg
        .rightUpperLeg: .hips,
        .rightLowerLeg: .rightUpperLeg,
        .rightFoot: .rightLowerLeg,
        .rightToes: .rightFoot
    ]

    /// Convert ARKit body skeleton to VRM humanoid bone rotations
    /// ARKit provides model-space transforms; we need local bone rotations
    private func convertBodyToVRMBones(_ skeleton: ARKitBodySkeleton) -> ([VRMHumanoidBone: simd_quatf], simd_float3?) {
        var rotations: [VRMHumanoidBone: simd_quatf] = [:]
        var hipsTranslation: simd_float3?

        // ARKit joint to VRM bone mapping (all key body bones)
        let jointMapping: [ARKitJoint: VRMHumanoidBone] = [
            // Core spine chain
            .hips: .hips,
            .spine: .spine,
            .chest: .chest,
            .upperChest: .upperChest,
            .neck: .neck,
            .head: .head,
            // Arms
            .leftShoulder: .leftShoulder,
            .rightShoulder: .rightShoulder,
            .leftUpperArm: .leftUpperArm,
            .rightUpperArm: .rightUpperArm,
            .leftLowerArm: .leftLowerArm,
            .rightLowerArm: .rightLowerArm,
            .leftHand: .leftHand,
            .rightHand: .rightHand,
            // Legs
            .leftUpperLeg: .leftUpperLeg,
            .rightUpperLeg: .rightUpperLeg,
            .leftLowerLeg: .leftLowerLeg,
            .rightLowerLeg: .rightLowerLeg,
            .leftFoot: .leftFoot,
            .rightFoot: .rightFoot,
            .leftToes: .leftToes,
            .rightToes: .rightToes
        ]

        for (arkitJoint, vrmBone) in jointMapping {
            guard let childTransform = skeleton.joints[arkitJoint] else { continue }

            // Extract hips translation for root motion
            if arkitJoint == .hips {
                // Convert ARKit translation to glTF/VRM (negate X and Z)
                hipsTranslation = simd_float3(
                    -childTransform.columns.3.x,
                    childTransform.columns.3.y,
                    -childTransform.columns.3.z
                )
                // Hips is root - convert model-space rotation
                var rot = extractRotation(from: childTransform)
                rot = simd_quatf(ix: -rot.imag.x, iy: rot.imag.y, iz: -rot.imag.z, r: rot.real)
                rotations[vrmBone] = rot
                continue
            }

            // Get parent transform to compute local rotation
            if let parentJoint = Self.arkitParentMap[arkitJoint],
               let parentTransform = skeleton.joints[parentJoint] {
                // Compute local rotation: localRot = inverse(parentWorldRot) * childWorldRot
                let parentRot = extractRotation(from: parentTransform)
                let childRot = extractRotation(from: childTransform)
                var localRot = simd_mul(simd_inverse(parentRot), childRot)
                // Convert ARKit coordinate system to VRM/glTF
                // ARKit: Y-up, camera facing -Z
                // glTF/VRM: Y-up, forward is +Z
                // Negate X and Z to convert from ARKit to glTF conventions
                localRot = simd_quatf(
                    ix: -localRot.imag.x,
                    iy: localRot.imag.y,
                    iz: -localRot.imag.z,
                    r: localRot.real
                )
                rotations[vrmBone] = localRot
            } else {
                // No parent found, use model-space rotation as fallback
                var rot = extractRotation(from: childTransform)
                rot = simd_quatf(ix: -rot.imag.x, iy: rot.imag.y, iz: -rot.imag.z, r: rot.real)
                rotations[vrmBone] = rot
            }
        }

        return (rotations, hipsTranslation)
    }

    /// Extract rotation quaternion from a 4x4 transform matrix
    private func extractRotation(from transform: simd_float4x4) -> simd_quatf {
        let col0 = simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let col1 = simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        let col2 = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)

        // Normalize columns to remove scale
        let x = simd_normalize(col0)
        let y = simd_normalize(col1)
        let z = simd_normalize(col2)

        let rotationMatrix = simd_float3x3(x, y, z)
        return simd_quatf(rotationMatrix)
    }
}
