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
import ArkavoRecorderShared
import simd

/// Converts between ArkavoRecorder metadata types and VRMMetalKit ARKit types.
///
/// This converter bridges the transport-agnostic metadata from camera sources
/// (CameraMetadataEvent) to the VRMMetalKit ARKit driver types.
enum ARKitDataConverter {

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
            return nil
        }
        return toARKitFaceBlendShapes(faceMetadata, timestamp: event.timestamp)
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
    /// - Parameter jointName: Joint name from metadata (e.g., "hips", "leftUpperArm")
    /// - Returns: ARKitJoint enum value, or nil if unknown joint
    static func toARKitJoint(_ jointName: String) -> ARKitJoint? {
        return ARKitJoint(rawValue: jointName)
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

        for joint in metadata.joints {
            // Map joint name to ARKitJoint enum
            guard let arkitJoint = toARKitJoint(joint.name) else {
                continue
            }

            // Convert transform array to matrix
            guard let matrix = toMatrix4x4(joint.transform) else {
                continue
            }

            joints[arkitJoint] = matrix
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
