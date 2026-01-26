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

    /// Convert ARKit body skeleton to VRM humanoid bone rotations
    private func convertBodyToVRMBones(_ skeleton: ARKitBodySkeleton) -> ([VRMHumanoidBone: simd_quatf], simd_float3?) {
        var rotations: [VRMHumanoidBone: simd_quatf] = [:]
        var hipsTranslation: simd_float3?

        // ARKit joint to VRM bone mapping
        let jointMapping: [ARKitJoint: VRMHumanoidBone] = [
            .hips: .hips,
            .spine: .spine,
            .chest: .chest,
            .neck: .neck,
            .head: .head,
            .leftShoulder: .leftShoulder,
            .rightShoulder: .rightShoulder,
            .leftUpperArm: .leftUpperArm,
            .rightUpperArm: .rightUpperArm,
            .leftLowerArm: .leftLowerArm,
            .rightLowerArm: .rightLowerArm,
            .leftHand: .leftHand,
            .rightHand: .rightHand,
            .leftUpperLeg: .leftUpperLeg,
            .rightUpperLeg: .rightUpperLeg,
            .leftLowerLeg: .leftLowerLeg,
            .rightLowerLeg: .rightLowerLeg,
            .leftFoot: .leftFoot,
            .rightFoot: .rightFoot
        ]

        for (arkitJoint, vrmBone) in jointMapping {
            if let transform = skeleton.joints[arkitJoint] {
                // Extract rotation from transform matrix
                let rotation = extractRotation(from: transform)
                rotations[vrmBone] = rotation

                // Extract hips translation for root motion
                if arkitJoint == .hips {
                    hipsTranslation = simd_float3(
                        transform.columns.3.x,
                        transform.columns.3.y,
                        transform.columns.3.z
                    )
                }
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
