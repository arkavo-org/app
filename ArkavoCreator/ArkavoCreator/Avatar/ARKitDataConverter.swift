//
// Copyright 2025 Arkavo
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import VRMMetalKit
import ArkavoKit
import simd

final class AtomicBool: @unchecked Sendable {
    private var value: Bool = false
    private let lock = NSLock()

    func getAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = true
        return old
    }
}

/// Converts between ArkavoRecorder metadata types and VRMMetalKit ARKit types.
///
/// This converter bridges the transport-agnostic metadata from camera sources
/// (CameraMetadataEvent) to the VRMMetalKit ARKit driver types.
enum ARKitDataConverter {
    private static let hasLoggedUnmappedJoints = AtomicBool()

    // MARK: - Face Tracking Conversion

    /// Convert ARFaceMetadata to ARKitFaceBlendShapes
    ///
    /// - Parameters:
    ///   - metadata: Face metadata from camera source
    ///   - timestamp: Timestamp when the event was received
    /// - Returns: ARKit blend shapes compatible with VRMMetalKit
    static func toARKitFaceBlendShapes(
        _ metadata: ARFaceMetadata,
        timestamp: Date
    ) -> ARKitFaceBlendShapes {
        var headTransform: simd_float4x4? = nil
        if let transformArray = metadata.headTransform {
            headTransform = toMatrix4x4(transformArray)
        }

        // Convert underscore format (eyeBlink_L) to camelCase (eyeBlinkLeft) for VRMMetalKit
        let convertedShapes = convertBlendShapeKeys(metadata.blendShapes)

        return ARKitFaceBlendShapes(
            timestamp: timestamp.timeIntervalSinceReferenceDate,
            shapes: convertedShapes,
            headTransform: headTransform
        )
    }

    /// Convert blend shape keys from underscore format to camelCase
    /// ArkavoKit uses: eyeBlink_L, mouthSmile_L, browDown_L
    /// VRMMetalKit expects: eyeBlinkLeft, mouthSmileLeft, browDownLeft
    private static func convertBlendShapeKeys(_ shapes: [String: Float]) -> [String: Float] {
        var converted: [String: Float] = [:]

        for (key, value) in shapes {
            let convertedKey = convertBlendShapeKey(key)
            converted[convertedKey] = value
        }

        return converted
    }

    /// Convert a single blend shape key from underscore to camelCase
    private static func convertBlendShapeKey(_ key: String) -> String {
        // Handle _L and _R suffixes
        if key.hasSuffix("_L") {
            let base = String(key.dropLast(2))
            return base + "Left"
        } else if key.hasSuffix("_R") {
            let base = String(key.dropLast(2))
            return base + "Right"
        }
        // No conversion needed for keys without _L/_R suffix
        return key
    }

    /// Convert CameraMetadataEvent to ARKitFaceBlendShapes (if face metadata)
    ///
    /// - Parameter event: Camera metadata event from remote source
    /// - Returns: ARKit blend shapes, or nil if not face tracking metadata
    static func toARKitFaceBlendShapes(_ event: CameraMetadataEvent) -> ARKitFaceBlendShapes? {
        guard case let .arFace(faceMetadata) = event.metadata else {
            print("🔄 [ARKitDataConverter] Event metadata is not .arFace, returning nil")
            return nil
        }
        print("🔄 [ARKitDataConverter] Converting face metadata with \(faceMetadata.blendShapes.count) blend shapes, headTransform: \(faceMetadata.headTransform != nil ? "yes" : "no")")
        let result = toARKitFaceBlendShapes(faceMetadata, timestamp: event.timestamp)
        print("   └─ Converted to ARKitFaceBlendShapes with \(result.shapes.count) shapes, headTransform: \(result.headTransform != nil ? "yes" : "no")")
        return result
    }

    // MARK: - Body Tracking Conversion

    /// Convert ARBodyMetadata.Joint transform array to simd_float4x4
    ///
    /// The transform array is expected to be 16 floats representing a column-major 4x4 matrix.
    ///
    /// - Parameter transform: 16-element float array (column-major)
    /// - Returns: 4x4 matrix, or nil if invalid format
    static func toMatrix4x4(_ transform: [Float]) -> simd_float4x4? {
        guard transform.count == 16 else {
            return nil
        }

        // Column-major matrix construction
        return simd_float4x4(
            simd_float4(transform[0], transform[1], transform[2], transform[3]),
            simd_float4(transform[4], transform[5], transform[6], transform[7]),
            simd_float4(transform[8], transform[9], transform[10], transform[11]),
            simd_float4(transform[12], transform[13], transform[14], transform[15])
        )
    }

    /// Map ARBodyMetadata.Joint name to ARKitJoint enum
    ///
    /// - Parameter jointName: Joint name from metadata (e.g., "hips_joint", "left_upLeg_joint")
    /// - Returns: ARKitJoint enum value, or nil if unknown joint
    static func toARKitJoint(_ jointName: String) -> ARKitJoint? {
        // ARKit joint names come with "_joint" suffix, strip it
        var cleanName = jointName.hasSuffix("_joint")
            ? String(jointName.dropLast(6))
            : jointName

        // Convert underscore_case to camelCase and map specific joint names
        // ARKit: left_upLeg → VRM: leftUpperLeg
        // ARKit: left_leg → VRM: leftLowerLeg
        let mapping: [String: String] = [
            // Core spine chain
            "hips": "hips",
            "spine_1": "spine",
            "spine_2": "spine",
            "spine_3": "chest",
            "spine_4": "chest",
            "spine_5": "chest",
            "spine_6": "upperChest",
            "spine_7": "upperChest",
            "neck_1": "neck",
            "neck_2": "neck",
            "neck_3": "neck",
            "neck_4": "neck",
            "head": "head",

            // Legs
            "left_upLeg": "leftUpperLeg",
            "left_leg": "leftLowerLeg",
            "left_foot": "leftFoot",
            "left_toes": "leftToes",
            "left_toesEnd": "leftToes",
            "right_upLeg": "rightUpperLeg",
            "right_leg": "rightLowerLeg",
            "right_foot": "rightFoot",
            "right_toes": "rightToes",
            "right_toesEnd": "rightToes",

            // Arms - include _1 variants that ARKit may provide
            "left_shoulder": "leftShoulder",
            "left_shoulder_1": "leftShoulder",
            "left_arm": "leftUpperArm",
            "left_forearm": "leftLowerArm",
            "left_hand": "leftHand",
            "right_shoulder": "rightShoulder",
            "right_shoulder_1": "rightShoulder",
            "right_arm": "rightUpperArm",
            "right_forearm": "rightLowerArm",
            "right_hand": "rightHand",
            "upper_chest": "upperChest",
            "left_upArm": "leftUpperArm",
            "left_lowArm": "leftLowerArm",
            "right_upArm": "rightUpperArm",
            "right_lowArm": "rightLowerArm",

            // Left hand fingers - Thumb
            "left_handThumbStart": "leftHandThumb1",
            "left_handThumbIntermediate": "leftHandThumb2",
            "left_handThumbEnd": "leftHandThumb3",
            "left_handThumbTip": "leftHandThumb4",
            "left_handThumb1": "leftHandThumb1",
            "left_handThumb2": "leftHandThumb2",
            "left_handThumb3": "leftHandThumb3",
            "left_handThumb4": "leftHandThumb4",

            // Left hand fingers - Index
            "left_handIndexStart": "leftHandIndex1",
            "left_handIndexIntermediate": "leftHandIndex2",
            "left_handIndexEnd": "leftHandIndex3",
            "left_handIndexTip": "leftHandIndex4",
            "left_handIndex1": "leftHandIndex1",
            "left_handIndex2": "leftHandIndex2",
            "left_handIndex3": "leftHandIndex3",
            "left_handIndex4": "leftHandIndex4",

            // Left hand fingers - Middle
            "left_handMiddleStart": "leftHandMiddle1",
            "left_handMiddleIntermediate": "leftHandMiddle2",
            "left_handMiddleEnd": "leftHandMiddle3",
            "left_handMiddleTip": "leftHandMiddle4",
            "left_handMiddle1": "leftHandMiddle1",
            "left_handMiddle2": "leftHandMiddle2",
            "left_handMiddle3": "leftHandMiddle3",
            "left_handMiddle4": "leftHandMiddle4",

            // Left hand fingers - Ring
            "left_handRingStart": "leftHandRing1",
            "left_handRingIntermediate": "leftHandRing2",
            "left_handRingEnd": "leftHandRing3",
            "left_handRingTip": "leftHandRing4",
            "left_handRing1": "leftHandRing1",
            "left_handRing2": "leftHandRing2",
            "left_handRing3": "leftHandRing3",
            "left_handRing4": "leftHandRing4",

            // Left hand fingers - Pinky
            "left_handPinkyStart": "leftHandPinky1",
            "left_handPinkyIntermediate": "leftHandPinky2",
            "left_handPinkyEnd": "leftHandPinky3",
            "left_handPinkyTip": "leftHandPinky4",
            "left_handLittleStart": "leftHandPinky1",
            "left_handLittleIntermediate": "leftHandPinky2",
            "left_handLittleEnd": "leftHandPinky3",
            "left_handLittleTip": "leftHandPinky4",
            "left_handPinky1": "leftHandPinky1",
            "left_handPinky2": "leftHandPinky2",
            "left_handPinky3": "leftHandPinky3",
            "left_handPinky4": "leftHandPinky4",

            // Right hand fingers - Thumb
            "right_handThumbStart": "rightHandThumb1",
            "right_handThumbIntermediate": "rightHandThumb2",
            "right_handThumbEnd": "rightHandThumb3",
            "right_handThumbTip": "rightHandThumb4",
            "right_handThumb1": "rightHandThumb1",
            "right_handThumb2": "rightHandThumb2",
            "right_handThumb3": "rightHandThumb3",
            "right_handThumb4": "rightHandThumb4",

            // Right hand fingers - Index
            "right_handIndexStart": "rightHandIndex1",
            "right_handIndexIntermediate": "rightHandIndex2",
            "right_handIndexEnd": "rightHandIndex3",
            "right_handIndexTip": "rightHandIndex4",
            "right_handIndex1": "rightHandIndex1",
            "right_handIndex2": "rightHandIndex2",
            "right_handIndex3": "rightHandIndex3",
            "right_handIndex4": "rightHandIndex4",

            // Right hand fingers - Middle
            "right_handMiddleStart": "rightHandMiddle1",
            "right_handMiddleIntermediate": "rightHandMiddle2",
            "right_handMiddleEnd": "rightHandMiddle3",
            "right_handMiddleTip": "rightHandMiddle4",
            "right_handMiddle1": "rightHandMiddle1",
            "right_handMiddle2": "rightHandMiddle2",
            "right_handMiddle3": "rightHandMiddle3",
            "right_handMiddle4": "rightHandMiddle4",

            // Right hand fingers - Ring
            "right_handRingStart": "rightHandRing1",
            "right_handRingIntermediate": "rightHandRing2",
            "right_handRingEnd": "rightHandRing3",
            "right_handRingTip": "rightHandRing4",
            "right_handRing1": "rightHandRing1",
            "right_handRing2": "rightHandRing2",
            "right_handRing3": "rightHandRing3",
            "right_handRing4": "rightHandRing4",

            // Right hand fingers - Pinky
            "right_handPinkyStart": "rightHandPinky1",
            "right_handPinkyIntermediate": "rightHandPinky2",
            "right_handPinkyEnd": "rightHandPinky3",
            "right_handPinkyTip": "rightHandPinky4",
            "right_handLittleStart": "rightHandPinky1",
            "right_handLittleIntermediate": "rightHandPinky2",
            "right_handLittleEnd": "rightHandPinky3",
            "right_handLittleTip": "rightHandPinky4",
            "right_handPinky1": "rightHandPinky1",
            "right_handPinky2": "rightHandPinky2",
            "right_handPinky3": "rightHandPinky3",
            "right_handPinky4": "rightHandPinky4"
        ]

        // Apply mapping if exists
        if let mapped = mapping[cleanName] {
            cleanName = mapped
        }

        return ARKitJoint(rawValue: cleanName)
    }

    /// Diagnostics callback for conversion stage capture
    /// 
    /// Note: For full ARKit to VRM conversion diagnostics, use ARKitToVRMConverter
    /// which provides coordinate conversion and bone mapping in one place.
    public typealias ConversionDiagnosticsCallback = (
        _ inputMetadata: ARBodyMetadata,
        _ outputSkeleton: ARKitBodySkeleton,
        _ mappedJoints: [String: String],
        _ unmappedJoints: [(name: String, transform: [Float]?)],
        _ invalidTransformJoints: [String]
    ) -> Void

    /// Convert ARBodyMetadata to ARKitBodySkeleton
    ///
    /// - Parameters:
    ///   - metadata: Body metadata from camera source
    ///   - timestamp: Timestamp when the event was received
    ///   - diagnosticsCallback: Optional callback for diagnostics capture
    /// - Returns: ARKit body skeleton compatible with VRMMetalKit
    static func toARKitBodySkeleton(
        _ metadata: ARBodyMetadata,
        timestamp: Date,
        diagnosticsCallback: ConversionDiagnosticsCallback? = nil
    ) -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]
        var unmappedJoints: [String] = []
        var unmappedJointsWithTransforms: [(name: String, transform: [Float]?)] = []
        var invalidTransformJoints: [String] = []
        var mappedJointsRecord: [String: String] = [:]

        for joint in metadata.joints {
            // Map joint name to ARKitJoint enum
            guard let arkitJoint = toARKitJoint(joint.name) else {
                unmappedJoints.append(joint.name)
                unmappedJointsWithTransforms.append((name: joint.name, transform: joint.transform))
                continue
            }

            // Convert transform array to matrix
            guard let matrix = toMatrix4x4(joint.transform) else {
                print("⚠️ [ARKitDataConverter] Invalid transform for joint: \(joint.name)")
                invalidTransformJoints.append(joint.name)
                continue
            }

            joints[arkitJoint] = matrix
            mappedJointsRecord[joint.name] = arkitJoint.rawValue
        }

        // Log unmapped joints (only first time)
        if !unmappedJoints.isEmpty && !Self.hasLoggedUnmappedJoints.getAndSet() {
            print("⚠️ [ARKitDataConverter] Unmapped joints (not in ARKitJoint enum):")
            print("   Total: \(unmappedJoints.count) out of \(metadata.joints.count)")
            print("   First 10: \(unmappedJoints.prefix(10).joined(separator: ", "))")

            // Log which joints ARE mapped
            let mappedJointsList = joints.keys.map { $0.rawValue }.sorted()
            print("✅ [ARKitDataConverter] Mapped joints (\(mappedJointsList.count)):")
            print("   \(mappedJointsList.joined(separator: ", "))")

            // Check for missing parent joints
            let requiredParents: [String] = ["upperChest", "leftShoulder", "rightShoulder", "spine", "chest"]
            let missing = requiredParents.filter { parent in !mappedJointsList.contains(parent) }
            if !missing.isEmpty {
                print("❌ [ARKitDataConverter] Missing parent joints for arms: \(missing.joined(separator: ", "))")
            }
        }

        let skeleton = ARKitBodySkeleton(
            timestamp: timestamp.timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: !joints.isEmpty,
            confidence: nil
        )

        // Call diagnostics callback if provided
        diagnosticsCallback?(
            metadata,
            skeleton,
            mappedJointsRecord,
            unmappedJointsWithTransforms,
            invalidTransformJoints
        )

        return skeleton
    }

    /// Convert CameraMetadataEvent to ARKitBodySkeleton (if body metadata)
    ///
    /// - Parameter event: Camera metadata event from remote source
    /// - Returns: ARKit body skeleton, or nil if not body tracking metadata
    static func toARKitBodySkeleton(_ event: CameraMetadataEvent) -> ARKitBodySkeleton? {
        guard case let .arBody(bodyMetadata) = event.metadata else {
            return nil
        }
        return toARKitBodySkeleton(bodyMetadata, timestamp: event.timestamp)
    }
}
