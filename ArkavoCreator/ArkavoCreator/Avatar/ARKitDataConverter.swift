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
        return ARKitFaceBlendShapes(
            timestamp: timestamp.timeIntervalSinceReferenceDate,
            shapes: metadata.blendShapes
        )
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
        print("🔄 [ARKitDataConverter] Converting face metadata with \(faceMetadata.blendShapes.count) blend shapes")
        let result = toARKitFaceBlendShapes(faceMetadata, timestamp: event.timestamp)
        print("   └─ Converted to ARKitFaceBlendShapes with \(result.shapes.count) shapes")
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
            "left_upLeg": "leftUpperLeg",
            "left_leg": "leftLowerLeg",
            "left_foot": "leftFoot",
            "left_toes": "leftToes",
            "left_toesEnd": "leftToes",  // Map toesEnd to toes
            "right_upLeg": "rightUpperLeg",
            "right_leg": "rightLowerLeg",
            "right_foot": "rightFoot",
            "right_toes": "rightToes",
            "right_toesEnd": "rightToes",  // Map toesEnd to toes
            "left_shoulder": "leftShoulder",
            "left_arm": "leftUpperArm",
            "left_forearm": "leftLowerArm",
            "left_hand": "leftHand",
            "right_shoulder": "rightShoulder",
            "right_arm": "rightUpperArm",
            "right_forearm": "rightLowerArm",
            "right_hand": "rightHand",
            "upper_chest": "upperChest",
            "left_upArm": "leftUpperArm",
            "left_lowArm": "leftLowerArm",
            "right_upArm": "rightUpperArm",
            "right_lowArm": "rightLowerArm"
        ]

        // Apply mapping if exists
        if let mapped = mapping[cleanName] {
            cleanName = mapped
        }

        return ARKitJoint(rawValue: cleanName)
    }

    /// Convert ARBodyMetadata to ARKitBodySkeleton
    ///
    /// - Parameters:
    ///   - metadata: Body metadata from camera source
    ///   - timestamp: Timestamp when the event was received
    /// - Returns: ARKit body skeleton compatible with VRMMetalKit
    static func toARKitBodySkeleton(
        _ metadata: ARBodyMetadata,
        timestamp: Date
    ) -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]
        var unmappedJoints: [String] = []

        for joint in metadata.joints {
            // Map joint name to ARKitJoint enum
            guard let arkitJoint = toARKitJoint(joint.name) else {
                unmappedJoints.append(joint.name)
                continue
            }

            // Convert transform array to matrix
            guard let matrix = toMatrix4x4(joint.transform) else {
                print("⚠️ [ARKitDataConverter] Invalid transform for joint: \(joint.name)")
                continue
            }

            joints[arkitJoint] = matrix
        }

        // Log unmapped joints (only first time)
        if !unmappedJoints.isEmpty && !Self.hasLoggedUnmappedJoints.getAndSet() {
            print("⚠️ [ARKitDataConverter] Unmapped joints (not in ARKitJoint enum):")
            print("   Total: \(unmappedJoints.count) out of \(metadata.joints.count)")
            print("   First 10: \(unmappedJoints.prefix(10).joined(separator: ", "))")
        }

        return ARKitBodySkeleton(
            timestamp: timestamp.timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: !joints.isEmpty,
            confidence: nil
        )
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
