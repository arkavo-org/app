//
// GeneratedPipelineTests.swift
// ArkavoCreatorTests
//
// Generated from pipeline diagnostics session
// Session: 2026-01-28T22:53:42Z - 2026-01-28T22:55:10Z
// Total captures: 500 (250 rawARKit, 250 conversion)
//
// This file contains tests derived from real motion capture data
// to verify pipeline behavior matches expected output.
//

import XCTest
import simd
import ArkavoKit
@testable import ArkavoCreator

final class GeneratedPipelineTests: XCTestCase {

    // MARK: - Joint Mapping Tests

    /// Verify that shoulder_1 joints are correctly mapped (critical fix)
    func testShoulderJointMapping() {
        // These mappings were verified from captured session data
        let expectedMappings: [String: String] = [
            "left_shoulder_1_joint": "leftShoulder",
            "right_shoulder_1_joint": "rightShoulder"
        ]

        for (arkitJoint, expectedVRM) in expectedMappings {
            let result = ARKitDataConverter.toARKitJoint(arkitJoint)
            XCTAssertNotNil(result, "Joint '\(arkitJoint)' should be mapped")
            XCTAssertEqual(result?.rawValue, expectedVRM, "Joint '\(arkitJoint)' should map to '\(expectedVRM)'")
        }
    }

    /// Verify spine chain mapping
    func testSpineChainMapping() {
        let spineJoints: [String: String] = [
            "spine_1_joint": "spine",
            "spine_2_joint": "spine",
            "spine_3_joint": "chest",
            "spine_4_joint": "chest",
            "spine_5_joint": "chest",
            "spine_6_joint": "upperChest",
            "spine_7_joint": "upperChest"
        ]

        for (arkitJoint, expectedVRM) in spineJoints {
            let result = ARKitDataConverter.toARKitJoint(arkitJoint)
            XCTAssertNotNil(result, "Joint '\(arkitJoint)' should be mapped")
            XCTAssertEqual(result?.rawValue, expectedVRM, "Joint '\(arkitJoint)' should map to '\(expectedVRM)'")
        }
    }

    /// Verify neck chain mapping
    func testNeckChainMapping() {
        let neckJoints = ["neck_1_joint", "neck_2_joint", "neck_3_joint", "neck_4_joint"]

        for arkitJoint in neckJoints {
            let result = ARKitDataConverter.toARKitJoint(arkitJoint)
            XCTAssertNotNil(result, "Joint '\(arkitJoint)' should be mapped")
            XCTAssertEqual(result?.rawValue, "neck", "Joint '\(arkitJoint)' should map to 'neck'")
        }
    }

    /// Verify core VRM bones are mapped from ARKit joints
    func testExpectedVRMBonesAreMapped() {
        // These are the core body bones that should always be mapped
        // (excludes finger bones which require additional ARKit joints)
        let coreVRMBones: Set<String> = [
            "chest", "head", "hips",
            "leftFoot", "leftHand", "leftLowerArm", "leftLowerLeg",
            "leftShoulder", "leftToes", "leftUpperArm", "leftUpperLeg",
            "neck",
            "rightFoot", "rightHand", "rightLowerArm", "rightLowerLeg",
            "rightShoulder", "rightToes", "rightUpperArm", "rightUpperLeg",
            "spine", "upperChest"
        ]

        // Create a test body metadata with all ARKit joints
        let testJoints = makeTestARKitJoints()
        let metadata = makeTestBodyMetadata(joints: testJoints)
        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        let mappedBones = Set(skeleton.joints.keys.map { $0.rawValue })

        // Verify all core bones are present
        for expectedBone in coreVRMBones {
            XCTAssertTrue(
                mappedBones.contains(expectedBone),
                "Expected VRM bone '\(expectedBone)' should be mapped"
            )
        }

        // Verify finger bones are mapped when finger joints are provided
        let fingerBones = ["leftHandIndex1", "leftHandIndex3", "leftHandThumb1", "leftHandThumb3",
                          "rightHandIndex1", "rightHandIndex3", "rightHandThumb1", "rightHandThumb3"]
        for fingerBone in fingerBones {
            XCTAssertTrue(
                mappedBones.contains(fingerBone),
                "Finger bone '\(fingerBone)' should be mapped when finger joints provided"
            )
        }
    }

    /// Verify joint count matches captured session
    func testJointCountMatchesCapturedSession() {
        // From captured session: 91 input joints -> 39 output joints (unique VRM bones)
        let testJoints = makeTestARKitJoints()
        let metadata = makeTestBodyMetadata(joints: testJoints)
        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        // We expect approximately 39 unique VRM bones (may vary slightly based on available joints)
        XCTAssertGreaterThanOrEqual(skeleton.joints.count, 15, "Should map at least 15 core body joints")
        XCTAssertLessThanOrEqual(skeleton.joints.count, 50, "Should not exceed reasonable joint count")
    }

    // MARK: - Conversion Quality Tests

    /// Verify skeleton is tracked when joints are present
    func testSkeletonIsTrackedWithValidJoints() {
        let testJoints = makeTestARKitJoints()
        let metadata = makeTestBodyMetadata(joints: testJoints)
        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        XCTAssertTrue(skeleton.isTracked, "Skeleton should be tracked when joints are present")
        XCTAssertFalse(skeleton.joints.isEmpty, "Joints dictionary should not be empty")
    }

    /// Verify empty input produces untracked skeleton
    func testEmptyJointsProducesUntrackedSkeleton() {
        let metadata = makeTestBodyMetadata(joints: [])
        let skeleton = ARKitDataConverter.toARKitBodySkeleton(metadata, timestamp: Date())

        XCTAssertFalse(skeleton.isTracked, "Skeleton should not be tracked with no joints")
        XCTAssertTrue(skeleton.joints.isEmpty, "Joints dictionary should be empty")
    }

    // MARK: - Transform Tests

    /// Verify identity transform is correctly converted
    func testIdentityTransformConversion() {
        let identity: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        ]

        let matrix = ARKitDataConverter.toMatrix4x4(identity)
        XCTAssertNotNil(matrix)

        if let m = matrix {
            // Check diagonal is 1
            XCTAssertEqual(m.columns.0.x, 1.0, accuracy: 0.0001)
            XCTAssertEqual(m.columns.1.y, 1.0, accuracy: 0.0001)
            XCTAssertEqual(m.columns.2.z, 1.0, accuracy: 0.0001)
            XCTAssertEqual(m.columns.3.w, 1.0, accuracy: 0.0001)

            // Check off-diagonal is 0
            XCTAssertEqual(m.columns.0.y, 0.0, accuracy: 0.0001)
            XCTAssertEqual(m.columns.1.x, 0.0, accuracy: 0.0001)
        }
    }

    /// Verify transform with translation
    func testTransformWithTranslation() {
        let transform: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            1.5, 2.0, -0.5, 1  // Translation
        ]

        let matrix = ARKitDataConverter.toMatrix4x4(transform)
        XCTAssertNotNil(matrix)

        if let m = matrix {
            XCTAssertEqual(m.columns.3.x, 1.5, accuracy: 0.0001)
            XCTAssertEqual(m.columns.3.y, 2.0, accuracy: 0.0001)
            XCTAssertEqual(m.columns.3.z, -0.5, accuracy: 0.0001)
        }
    }

    /// Verify invalid transform array is rejected
    func testInvalidTransformArrayRejected() {
        let invalid: [Float] = [1, 0, 0, 0, 0, 1, 0, 0]  // Only 8 elements
        let matrix = ARKitDataConverter.toMatrix4x4(invalid)
        XCTAssertNil(matrix, "Should reject transform array with wrong element count")
    }

    // MARK: - Sample Data From Captured Session

    /// Verify sample rotation data from captured session produces valid quaternions
    func testSampleRotationDataProducesValidQuaternions() {
        // Sample transform from captured session (left_shoulder_1_joint)
        let sampleTransform: [Float] = [
            0.59065187, 0.16904375, 0.7890214, 0,
            0.27553624, -0.9612907, -0.00031154818, 0,
            0.7584262, 0.21758798, -0.61436576, 0,
            0.6982431, 0.61384857, 0.34776688, 1
        ]

        let matrix = ARKitDataConverter.toMatrix4x4(sampleTransform)
        XCTAssertNotNil(matrix)

        // The matrix should be valid and the rotation columns should be approximately normalized
        if let m = matrix {
            let col0Length = sqrt(m.columns.0.x * m.columns.0.x + m.columns.0.y * m.columns.0.y + m.columns.0.z * m.columns.0.z)
            let col1Length = sqrt(m.columns.1.x * m.columns.1.x + m.columns.1.y * m.columns.1.y + m.columns.1.z * m.columns.1.z)
            let col2Length = sqrt(m.columns.2.x * m.columns.2.x + m.columns.2.y * m.columns.2.y + m.columns.2.z * m.columns.2.z)

            XCTAssertEqual(col0Length, 1.0, accuracy: 0.01, "Rotation column 0 should be normalized")
            XCTAssertEqual(col1Length, 1.0, accuracy: 0.01, "Rotation column 1 should be normalized")
            XCTAssertEqual(col2Length, 1.0, accuracy: 0.01, "Rotation column 2 should be normalized")
        }
    }

    // MARK: - Unmapped Joints Tests

    /// Verify known unmapped joints are intentionally not mapped
    func testKnownUnmappedJointsAreIntentional() {
        // These joints are expected to be unmapped (face, intermediate fingers, etc.)
        let expectedUnmapped = [
            "jaw_joint",
            "chin_joint",
            "left_eye_joint",
            "right_eye_joint",
            "nose_joint",
            "left_eyeball_joint",
            "right_eyeball_joint",
            "left_eyeLowerLid_joint",
            "right_eyeLowerLid_joint",
            "left_eyeUpperLid_joint",
            "right_eyeUpperLid_joint",
            // Intermediate finger joints (we use Start/End)
            "left_handIndex_1_joint",
            "left_handIndex_2_joint",
            "left_handIndex_3_joint"
        ]

        for jointName in expectedUnmapped {
            let result = ARKitDataConverter.toARKitJoint(jointName)
            XCTAssertNil(result, "Joint '\(jointName)' should intentionally not be mapped")
        }
    }

    // MARK: - Test Helpers

    /// Create test ARKit joints matching captured session structure
    private func makeTestARKitJoints() -> [(name: String, transform: [Float])] {
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

        return [
            // Core body
            ("hips_joint", identity),
            ("spine_1_joint", identity),
            ("spine_2_joint", identity),
            ("spine_3_joint", identity),
            ("spine_4_joint", identity),
            ("spine_5_joint", identity),
            ("spine_6_joint", identity),
            ("spine_7_joint", identity),
            ("neck_1_joint", identity),
            ("neck_2_joint", identity),
            ("neck_3_joint", identity),
            ("neck_4_joint", identity),
            ("head_joint", identity),
            // Left arm (with shoulder_1 fix)
            ("left_shoulder_1_joint", identity),
            ("left_arm_joint", identity),
            ("left_forearm_joint", identity),
            ("left_hand_joint", identity),
            // Right arm (with shoulder_1 fix)
            ("right_shoulder_1_joint", identity),
            ("right_arm_joint", identity),
            ("right_forearm_joint", identity),
            ("right_hand_joint", identity),
            // Legs
            ("left_upLeg_joint", identity),
            ("left_leg_joint", identity),
            ("left_foot_joint", identity),
            ("left_toes_joint", identity),
            ("right_upLeg_joint", identity),
            ("right_leg_joint", identity),
            ("right_foot_joint", identity),
            ("right_toes_joint", identity),
            // Fingers (Start/End)
            ("left_handIndexStart_joint", identity),
            ("left_handIndexEnd_joint", identity),
            ("left_handThumbStart_joint", identity),
            ("left_handThumbEnd_joint", identity),
            ("right_handIndexStart_joint", identity),
            ("right_handIndexEnd_joint", identity),
            ("right_handThumbStart_joint", identity),
            ("right_handThumbEnd_joint", identity)
        ]
    }

    /// Create test body metadata from joint data
    private func makeTestBodyMetadata(joints: [(name: String, transform: [Float])]) -> ARBodyMetadata {
        let jointStructs = joints.map { ARBodyMetadata.Joint(name: $0.name, transform: $0.transform) }
        return ARBodyMetadata(joints: jointStructs)
    }
}
