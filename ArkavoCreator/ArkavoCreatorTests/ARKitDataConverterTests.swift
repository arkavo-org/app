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

@testable import ArkavoCreator
import ArkavoKit
import simd
import VRMMetalKit
import XCTest

/// Tests for ARKitDataConverter - the bridge between ArkavoKit metadata and VRMMetalKit types
final class ARKitDataConverterTests: XCTestCase {
    // MARK: - Matrix Conversion Tests

    func testToMatrix4x4WithValidInput() {
        // Identity matrix in column-major order
        let identity: [Float] = [
            1, 0, 0, 0, // column 0
            0, 1, 0, 0, // column 1
            0, 0, 1, 0, // column 2
            0, 0, 0, 1, // column 3
        ]

        let matrix = ARKitDataConverter.toMatrix4x4(identity)

        XCTAssertNotNil(matrix, "Should convert valid 16-element array")

        // Verify identity matrix
        XCTAssertEqual(matrix!.columns.0.x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(matrix!.columns.1.y, 1.0, accuracy: 0.0001)
        XCTAssertEqual(matrix!.columns.2.z, 1.0, accuracy: 0.0001)
        XCTAssertEqual(matrix!.columns.3.w, 1.0, accuracy: 0.0001)
    }

    func testToMatrix4x4WithTranslation() {
        // Matrix with translation (5, 10, 15)
        let translated: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            5, 10, 15, 1, // translation in column 3
        ]

        let matrix = ARKitDataConverter.toMatrix4x4(translated)

        XCTAssertNotNil(matrix)
        XCTAssertEqual(matrix!.columns.3.x, 5.0, accuracy: 0.0001, "X translation")
        XCTAssertEqual(matrix!.columns.3.y, 10.0, accuracy: 0.0001, "Y translation")
        XCTAssertEqual(matrix!.columns.3.z, 15.0, accuracy: 0.0001, "Z translation")
    }

    func testToMatrix4x4WithInvalidInput() {
        // Too few elements
        let tooShort: [Float] = [1, 0, 0, 0, 0, 1, 0, 0]
        XCTAssertNil(ARKitDataConverter.toMatrix4x4(tooShort), "Should return nil for < 16 elements")

        // Too many elements
        let tooLong: [Float] = Array(repeating: 1.0, count: 20)
        XCTAssertNil(ARKitDataConverter.toMatrix4x4(tooLong), "Should return nil for > 16 elements")

        // Empty array
        XCTAssertNil(ARKitDataConverter.toMatrix4x4([]), "Should return nil for empty array")
    }

    // MARK: - Joint Mapping Tests

    func testToARKitJointCoreSpine() {
        // Test core spine joints
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("hips_joint"), ARKitJoint.hips)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("spine_1_joint"), ARKitJoint.spine)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("spine_3_joint"), ARKitJoint.chest)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("spine_7_joint"), ARKitJoint.upperChest)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("neck_1_joint"), ARKitJoint.neck)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("head_joint"), ARKitJoint.head)
    }

    func testToARKitJointLegs() {
        // Test leg joints
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_upLeg_joint"), ARKitJoint.leftUpperLeg)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_leg_joint"), ARKitJoint.leftLowerLeg)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_foot_joint"), ARKitJoint.leftFoot)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_toes_joint"), ARKitJoint.leftToes)

        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_upLeg_joint"), ARKitJoint.rightUpperLeg)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_leg_joint"), ARKitJoint.rightLowerLeg)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_foot_joint"), ARKitJoint.rightFoot)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_toes_joint"), ARKitJoint.rightToes)
    }

    func testToARKitJointArms() {
        // Test arm joints
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_shoulder_joint"), ARKitJoint.leftShoulder)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_arm_joint"), ARKitJoint.leftUpperArm)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_forearm_joint"), ARKitJoint.leftLowerArm)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_hand_joint"), ARKitJoint.leftHand)

        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_shoulder_joint"), ARKitJoint.rightShoulder)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_arm_joint"), ARKitJoint.rightUpperArm)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_forearm_joint"), ARKitJoint.rightLowerArm)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_hand_joint"), ARKitJoint.rightHand)
    }

    func testToARKitJointFingers() {
        // Test finger joints (sample)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_handThumb1_joint"), ARKitJoint.leftHandThumb1)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("left_handIndex1_joint"), ARKitJoint.leftHandIndex1)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_handMiddle2_joint"), ARKitJoint.rightHandMiddle2)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("right_handPinky3_joint"), ARKitJoint.rightHandPinky3)
    }

    func testToARKitJointUnknownJoint() {
        // Test unknown joints return nil
        XCTAssertNil(ARKitDataConverter.toARKitJoint("unknown_joint"))
        XCTAssertNil(ARKitDataConverter.toARKitJoint(""))
        XCTAssertNil(ARKitDataConverter.toARKitJoint("nonexistent_bone_joint"))
    }

    func testToARKitJointRoot() {
        // Root is a valid ARKitJoint
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("root"), ARKitJoint.root)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("root_joint"), ARKitJoint.root)
    }

    func testToARKitJointWithoutJointSuffix() {
        // Test that joints without _joint suffix also work
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("hips"), ARKitJoint.hips)
        XCTAssertEqual(ARKitDataConverter.toARKitJoint("head"), ARKitJoint.head)
    }

    // MARK: - Body Skeleton Conversion Tests

    func testToARKitBodySkeletonBasic() {
        let identityTransform: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]

        let metadata = ARBodyMetadata(
            joints: [
                ARBodyMetadata.Joint(name: "hips_joint", transform: identityTransform),
                ARBodyMetadata.Joint(name: "spine_1_joint", transform: identityTransform),
            ]
        )

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        XCTAssertTrue(skeleton.isTracked, "Skeleton should be tracked when joints exist")
        XCTAssertEqual(skeleton.joints.count, 2, "Should have 2 joints")
        XCTAssertNotNil(skeleton.joints[ARKitJoint.hips], "Should have hips joint")
        XCTAssertNotNil(skeleton.joints[ARKitJoint.spine], "Should have spine joint")
    }

    func testToARKitBodySkeletonWithRotation() {
        // Create a rotation transform using the helper (consistent column-major format)
        let rotatedTransform = createRotationTransform(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))

        let metadata = ARBodyMetadata(
            joints: [
                ARBodyMetadata.Joint(name: "hips_joint", transform: rotatedTransform),
            ]
        )

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        XCTAssertNotNil(skeleton.joints[ARKitJoint.hips])
        let hipsMatrix = skeleton.joints[ARKitJoint.hips]!

        // Verify the transform has a valid rotation (determinant ≈ 1 for rotation matrix)
        let det = simd_determinant(hipsMatrix)
        XCTAssertEqual(det, 1.0, accuracy: 0.001, "Rotation matrix should have determinant of 1")

        // Verify it's not identity
        XCTAssertNotEqual(hipsMatrix.columns.0.x, 1.0, accuracy: 0.0001, "Should not be identity")
    }

    func testToARKitBodySkeletonFiltersUnmappedJoints() {
        let identity: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]

        let metadata = ARBodyMetadata(
            joints: [
                ARBodyMetadata.Joint(name: "hips_joint", transform: identity),
                ARBodyMetadata.Joint(name: "unknown_bone_joint", transform: identity), // Should be filtered
                ARBodyMetadata.Joint(name: "totally_fake_joint", transform: identity), // Should be filtered
            ]
        )

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        // Only hips should be mapped (unknown joints filtered out)
        XCTAssertEqual(skeleton.joints.count, 1, "Only mapped joints should be included")
        XCTAssertNotNil(skeleton.joints[ARKitJoint.hips])
    }

    func testToARKitBodySkeletonEmptyJoints() {
        let metadata = ARBodyMetadata(joints: [])

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        XCTAssertFalse(skeleton.isTracked, "Empty skeleton should not be tracked")
        XCTAssertTrue(skeleton.joints.isEmpty)
    }

    func testToARKitBodySkeletonTimestamp() {
        let testDate = Date(timeIntervalSinceReferenceDate: 12345.67)
        let metadata = ARBodyMetadata(joints: [])

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: testDate)

        XCTAssertEqual(skeleton.timestamp, 12345.67, accuracy: 0.001)
    }

    // MARK: - Face Blend Shape Conversion Tests

    func testBlendShapeKeyConversionLeftSuffix() {
        let metadata = ARFaceMetadata(
            blendShapes: ["eyeBlink_L": 0.5, "mouthSmile_L": 0.8],
            trackingState: .normal,
            headTransform: nil
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(metadata, timestamp: Date())

        // _L should become Left
        XCTAssertEqual(blendShapes.weight(for: "eyeBlinkLeft"), 0.5, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "mouthSmileLeft"), 0.8, accuracy: 0.001)

        // Original keys should not exist
        XCTAssertEqual(blendShapes.weight(for: "eyeBlink_L"), 0.0, accuracy: 0.001)
    }

    func testBlendShapeKeyConversionRightSuffix() {
        let metadata = ARFaceMetadata(
            blendShapes: ["eyeBlink_R": 0.3, "browDown_R": 0.6],
            trackingState: .normal,
            headTransform: nil
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(metadata, timestamp: Date())

        // _R should become Right
        XCTAssertEqual(blendShapes.weight(for: "eyeBlinkRight"), 0.3, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "browDownRight"), 0.6, accuracy: 0.001)
    }

    func testBlendShapeKeyConversionNoSuffix() {
        let metadata = ARFaceMetadata(
            blendShapes: ["jawOpen": 0.7, "tongueOut": 0.2],
            trackingState: .normal,
            headTransform: nil
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(metadata, timestamp: Date())

        // Keys without suffix should remain unchanged
        XCTAssertEqual(blendShapes.weight(for: "jawOpen"), 0.7, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "tongueOut"), 0.2, accuracy: 0.001)
    }

    func testBlendShapeWithHeadTransform() {
        let headTransform: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0.1, 0.2, 0.3, 1, // Translation
        ]

        let metadata = ARFaceMetadata(
            blendShapes: ["jawOpen": 0.5],
            trackingState: .normal,
            headTransform: headTransform
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(metadata, timestamp: Date())

        XCTAssertNotNil(blendShapes.headTransform, "Head transform should be present")
        XCTAssertEqual(blendShapes.headTransform!.columns.3.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(blendShapes.headTransform!.columns.3.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(blendShapes.headTransform!.columns.3.z, 0.3, accuracy: 0.0001)
    }

    func testBlendShapeWithoutHeadTransform() {
        let metadata = ARFaceMetadata(
            blendShapes: ["jawOpen": 0.5],
            trackingState: .normal,
            headTransform: nil
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(metadata, timestamp: Date())

        XCTAssertNil(blendShapes.headTransform, "Head transform should be nil")
    }

    // MARK: - CameraMetadataEvent Conversion Tests

    func testToARKitBodySkeletonFromEvent() {
        let identityTransform: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]

        let bodyMetadata = ARBodyMetadata(
            joints: [ARBodyMetadata.Joint(name: "hips_joint", transform: identityTransform)]
        )

        let event = CameraMetadataEvent(
            sourceID: "test-source",
            metadata: .arBody(bodyMetadata),
            timestamp: Date()
        )

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(event)

        XCTAssertNotNil(skeleton, "Should convert body event to skeleton")
        XCTAssertNotNil(skeleton?.joints[ARKitJoint.hips])
    }

    func testToARKitBodySkeletonFromFaceEventReturnsNil() {
        let faceMetadata = ARFaceMetadata(
            blendShapes: ["jawOpen": 0.5],
            trackingState: .normal,
            headTransform: nil
        )

        let event = CameraMetadataEvent(
            sourceID: "test-source",
            metadata: .arFace(faceMetadata),
            timestamp: Date()
        )

        let skeleton = ARKitDataConverter.toARKitBodySkeleton(event)

        XCTAssertNil(skeleton, "Face event should not convert to body skeleton")
    }

    func testToARKitFaceBlendShapesFromEvent() {
        let faceMetadata = ARFaceMetadata(
            blendShapes: ["eyeBlink_L": 0.5],
            trackingState: .normal,
            headTransform: nil
        )

        let event = CameraMetadataEvent(
            sourceID: "test-source",
            metadata: .arFace(faceMetadata),
            timestamp: Date()
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(event)

        XCTAssertNotNil(blendShapes, "Should convert face event to blend shapes")
        XCTAssertEqual(Double(blendShapes!.weight(for: "eyeBlinkLeft")), 0.5, accuracy: 0.001)
    }

    func testToARKitFaceBlendShapesFromBodyEventReturnsNil() {
        let bodyMetadata = ARBodyMetadata(joints: [])

        let event = CameraMetadataEvent(
            sourceID: "test-source",
            metadata: .arBody(bodyMetadata),
            timestamp: Date()
        )

        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(event)

        XCTAssertNil(blendShapes, "Body event should not convert to face blend shapes")
    }

    // MARK: - Full Pipeline Integration Tests

    func testFullBodyTrackingPipeline() {
        // Simulate a realistic body tracking frame from ARKit
        let hipsTransform = createRotationTransform(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0))
        let spineTransform = createRotationTransform(angle: .pi / 12, axis: SIMD3<Float>(1, 0, 0))
        let leftArmTransform = createRotationTransform(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1))

        let metadata = ARBodyMetadata(
            joints: [
                ARBodyMetadata.Joint(name: "hips_joint", transform: hipsTransform),
                ARBodyMetadata.Joint(name: "spine_1_joint", transform: spineTransform),
                ARBodyMetadata.Joint(name: "left_arm_joint", transform: leftArmTransform),
            ]
        )

        let event = CameraMetadataEvent(
            sourceID: "test-device-\(UUID().uuidString)",
            metadata: .arBody(metadata),
            timestamp: Date()
        )

        // Convert through the full pipeline
        guard let skeleton = ARKitDataConverter.toARKitBodySkeleton(event) else {
            XCTFail("Failed to convert body metadata to skeleton")
            return
        }

        // Verify all expected joints are present
        XCTAssertTrue(skeleton.isTracked)
        XCTAssertEqual(skeleton.joints.count, 3)
        XCTAssertNotNil(skeleton.joints[ARKitJoint.hips])
        XCTAssertNotNil(skeleton.joints[ARKitJoint.spine])
        XCTAssertNotNil(skeleton.joints[ARKitJoint.leftUpperArm])

        // Verify transforms are valid (non-zero determinant)
        for (joint, transform) in skeleton.joints {
            let det = simd_determinant(transform)
            XCTAssertNotEqual(det, 0, accuracy: 0.001, "Joint \(joint) should have valid transform")
        }
    }

    func testFullFaceTrackingPipeline() {
        // Simulate a realistic face tracking frame from ARKit
        let headTransform: [Float] = createRotationTransform(
            angle: .pi / 12,
            axis: SIMD3<Float>(1, 0, 0)
        )

        let metadata = ARFaceMetadata(
            blendShapes: [
                "eyeBlink_L": 0.1,
                "eyeBlink_R": 0.15,
                "mouthSmile_L": 0.4,
                "mouthSmile_R": 0.35,
                "jawOpen": 0.2,
                "browInnerUp": 0.3,
            ],
            trackingState: .normal,
            headTransform: headTransform
        )

        let event = CameraMetadataEvent(
            sourceID: "test-face-device",
            metadata: .arFace(metadata),
            timestamp: Date()
        )

        // Convert through the full pipeline
        guard let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(event) else {
            XCTFail("Failed to convert face metadata to blend shapes")
            return
        }

        // Verify key conversions
        XCTAssertEqual(blendShapes.weight(for: "eyeBlinkLeft"), 0.1, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "eyeBlinkRight"), 0.15, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "mouthSmileLeft"), 0.4, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "mouthSmileRight"), 0.35, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "jawOpen"), 0.2, accuracy: 0.001)
        XCTAssertEqual(blendShapes.weight(for: "browInnerUp"), 0.3, accuracy: 0.001)

        // Verify head transform is present
        XCTAssertNotNil(blendShapes.headTransform)
    }

    // MARK: - Performance Tests

    func testBodySkeletonConversionPerformance() {
        // Create a full skeleton with many joints
        let joints = createFullSkeletonJoints()
        let metadata = ARBodyMetadata(joints: joints)

        measure {
            for _ in 0..<100 {
                _ = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())
            }
        }
    }

    func testFaceBlendShapeConversionPerformance() {
        // Create full set of blend shapes
        let blendShapes = createFullBlendShapes()
        let metadata = ARFaceMetadata(
            blendShapes: blendShapes,
            trackingState: .normal,
            headTransform: nil
        )

        measure {
            for _ in 0..<100 {
                _ = ARKitDataConverter.toARKitFaceBlendShapes(metadata, timestamp: Date())
            }
        }
    }

    // MARK: - Helpers

    private func createRotationTransform(angle: Float, axis: SIMD3<Float>) -> [Float] {
        let quaternion = simd_quatf(angle: angle, axis: normalize(axis))
        let matrix = simd_float4x4(quaternion)

        // Convert to column-major array
        return [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w,
        ]
    }

    private func createFullSkeletonJoints() -> [ARBodyMetadata.Joint] {
        let identity: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]

        let jointNames = [
            "hips_joint", "spine_1_joint", "spine_3_joint", "spine_7_joint",
            "neck_1_joint", "head_joint",
            "left_shoulder_joint", "left_arm_joint", "left_forearm_joint", "left_hand_joint",
            "right_shoulder_joint", "right_arm_joint", "right_forearm_joint", "right_hand_joint",
            "left_upLeg_joint", "left_leg_joint", "left_foot_joint", "left_toes_joint",
            "right_upLeg_joint", "right_leg_joint", "right_foot_joint", "right_toes_joint",
        ]

        return jointNames.map { ARBodyMetadata.Joint(name: $0, transform: identity) }
    }

    private func createFullBlendShapes() -> [String: Float] {
        return [
            "eyeBlink_L": 0.1, "eyeBlink_R": 0.1,
            "eyeLookDown_L": 0.0, "eyeLookDown_R": 0.0,
            "eyeLookIn_L": 0.0, "eyeLookIn_R": 0.0,
            "eyeLookOut_L": 0.0, "eyeLookOut_R": 0.0,
            "eyeLookUp_L": 0.0, "eyeLookUp_R": 0.0,
            "eyeSquint_L": 0.0, "eyeSquint_R": 0.0,
            "eyeWide_L": 0.0, "eyeWide_R": 0.0,
            "jawForward": 0.0, "jawLeft": 0.0, "jawRight": 0.0, "jawOpen": 0.2,
            "mouthClose": 0.0, "mouthFunnel": 0.0, "mouthPucker": 0.0,
            "mouthLeft": 0.0, "mouthRight": 0.0,
            "mouthSmile_L": 0.3, "mouthSmile_R": 0.3,
            "mouthFrown_L": 0.0, "mouthFrown_R": 0.0,
            "mouthDimple_L": 0.0, "mouthDimple_R": 0.0,
            "mouthStretch_L": 0.0, "mouthStretch_R": 0.0,
            "mouthRollLower": 0.0, "mouthRollUpper": 0.0,
            "mouthShrugLower": 0.0, "mouthShrugUpper": 0.0,
            "mouthPress_L": 0.0, "mouthPress_R": 0.0,
            "mouthLowerDown_L": 0.0, "mouthLowerDown_R": 0.0,
            "mouthUpperUp_L": 0.0, "mouthUpperUp_R": 0.0,
            "browDown_L": 0.0, "browDown_R": 0.0,
            "browInnerUp": 0.1, "browOuterUp_L": 0.0, "browOuterUp_R": 0.0,
            "cheekPuff": 0.0, "cheekSquint_L": 0.0, "cheekSquint_R": 0.0,
            "noseSneer_L": 0.0, "noseSneer_R": 0.0,
            "tongueOut": 0.0,
        ]
    }
}
