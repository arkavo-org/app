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

import simd
import VRMMetalKit
import XCTest

/// Diagnostic tests for ARKitToVRMConverter
///
/// These tests verify the conversion pipeline from ARKit to VRM coordinates.
/// Key invariants:
/// - Identity matrices → T-pose (no rotation from rest)
/// - Single-axis rotations map correctly
/// - Arms rotate in correct plane (Y axis for raising, not Z)
///
/// Note: These tests use ARKitToVRMConverter which is now part of ArkavoCreator
/// (not VRMMetalKit) to keep ARKit-specific logic separate from general VRM rendering.
final class ARKitToVRMConverterTests: XCTestCase {
    // MARK: - Test Helpers

    /// Create a rotation matrix from axis-angle
    private func rotationMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        return simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }

    /// Check if a quaternion is approximately identity (no rotation)
    private func isNearIdentity(_ q: simd_quatf, tolerance: Float = 0.01) -> Bool {
        // Identity quaternion: (0, 0, 0, 1) or (-0, -0, -0, -1)
        let identity1 = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let identity2 = simd_quatf(ix: 0, iy: 0, iz: 0, r: -1)

        let diff1 = abs(q.real - identity1.real) + simd_length(q.imag - identity1.imag)
        let diff2 = abs(q.real - identity2.real) + simd_length(q.imag - identity2.imag)

        return min(diff1, diff2) < tolerance
    }

    /// Get the angle in degrees from a quaternion
    private func angleDegrees(_ q: simd_quatf) -> Float {
        let angle = 2 * acos(min(abs(q.real), 1.0))
        return angle * 180.0 / .pi
    }

    /// Extract rotation axis from quaternion (unit vector)
    private func rotationAxis(_ q: simd_quatf) -> SIMD3<Float> {
        let sinAngle = simd_length(q.imag)
        if sinAngle < 0.0001 {
            return SIMD3<Float>(0, 1, 0) // Default axis for near-identity
        }
        return q.imag / sinAngle
    }

    /// Print quaternion details for debugging
    private func printQuaternion(_ name: String, _ q: simd_quatf) {
        print("\(name): w=\(String(format: "%.4f", q.real)), " +
              "x=\(String(format: "%.4f", q.imag.x)), " +
              "y=\(String(format: "%.4f", q.imag.y)), " +
              "z=\(String(format: "%.4f", q.imag.z)) " +
              "[angle=\(String(format: "%.1f", angleDegrees(q)))°]")
    }

    /// Create a skeleton with all joints at identity
    private func createIdentitySkeleton() -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]
        let identity = simd_float4x4(1) // Identity matrix

        // Add all main joints
        let mainJoints: [ARKitJoint] = [
            .hips, .spine, .chest, .upperChest, .neck, .head,
            .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
            .rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand,
            .leftUpperLeg, .leftLowerLeg, .leftFoot, .leftToes,
            .rightUpperLeg, .rightLowerLeg, .rightFoot, .rightToes
        ]

        for joint in mainJoints {
            joints[joint] = identity
        }

        return ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true
        )
    }

    // MARK: - Identity Matrix Tests

    /// Test: All joints at identity should produce T-pose (minimal rotation from rest)
    func testIdentityMatricesProduceTpose() {
        // Disable rest pose calibration for this test
        let originalCalibration = ARKitToVRMConverter.restPoseCalibrationEnabled
        ARKitToVRMConverter.restPoseCalibrationEnabled = false
        defer { ARKitToVRMConverter.restPoseCalibrationEnabled = originalCalibration }

        let skeleton = createIdentitySkeleton()

        print("\n=== Identity Matrix Test ===")
        print("All joints at identity matrix, rest pose calibration DISABLED\n")

        // Test hips (root) - should have root correction applied
        if let hipsTransform = skeleton.joints[.hips] {
            let hipsRotation = ARKitToVRMConverter.computeVRMRotation(
                joint: .hips,
                childTransform: hipsTransform,
                skeleton: skeleton
            )
            XCTAssertNotNil(hipsRotation, "Hips rotation should not be nil")
            if let rot = hipsRotation {
                printQuaternion("Hips (root with correction)", rot)
                // Hips should have root correction, so NOT identity
                // But we can verify the angle is approximately 90° or 180°
            }
        }

        // Test non-root joints - should be near identity (no rotation from T-pose)
        let nonRootJoints: [ARKitJoint] = [
            .spine, .chest, .upperChest, .neck, .head,
            .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
            .rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand,
            .leftUpperLeg, .leftLowerLeg, .leftFoot,
            .rightUpperLeg, .rightLowerLeg, .rightFoot
        ]

        print("\nNon-root joints (should be near identity):")
        var nonIdentityJoints: [(ARKitJoint, Float)] = []

        for joint in nonRootJoints {
            guard let transform = skeleton.joints[joint] else { continue }
            let rotation = ARKitToVRMConverter.computeVRMRotation(
                joint: joint,
                childTransform: transform,
                skeleton: skeleton
            )

            if let rot = rotation {
                let angle = angleDegrees(rot)
                if angle > 5.0 { // More than 5 degrees from identity
                    nonIdentityJoints.append((joint, angle))
                }
                printQuaternion("  \(joint.rawValue)", rot)
            } else {
                print("  \(joint.rawValue): nil (parent missing)")
            }
        }

        // Report non-identity joints
        if !nonIdentityJoints.isEmpty {
            print("\n⚠️  Joints with significant rotation from identity:")
            for (joint, angle) in nonIdentityJoints {
                print("  - \(joint.rawValue): \(String(format: "%.1f", angle))°")
            }
        }

        // Assert that spine chain joints are near identity
        for joint in [ARKitJoint.spine, .chest, .upperChest, .neck, .head] {
            guard let transform = skeleton.joints[joint] else { continue }
            if let rot = ARKitToVRMConverter.computeVRMRotation(
                joint: joint,
                childTransform: transform,
                skeleton: skeleton
            ) {
                XCTAssertTrue(
                    isNearIdentity(rot, tolerance: 0.1),
                    "\(joint.rawValue) should be near identity, got angle: \(angleDegrees(rot))°"
                )
            }
        }
    }

    // MARK: - Root Rotation Tests

    /// Test: Root rotation correction analysis
    func testRootRotationCorrectionAnalysis() {
        let correction = ARKitToVRMConverter.rootRotationCorrection

        // Decompose the correction
        let angle = angleDegrees(correction)
        let axis = rotationAxis(correction)

        // Test what happens to forward vector
        let forward = SIMD3<Float>(0, 0, -1) // ARKit forward
        let rotatedForward = correction.act(forward)

        // Test what happens to up vector
        let up = SIMD3<Float>(0, 1, 0) // ARKit up
        let rotatedUp = correction.act(up)

        // Test alternative: just 180° Y rotation
        let alternative = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        let altForward = alternative.act(forward)
        let altUp = alternative.act(up)

        // Document findings in test output
        var report = """
        === Root Rotation Correction Analysis ===

        Current correction quaternion: w=\(String(format: "%.4f", correction.real)), x=\(String(format: "%.4f", correction.imag.x)), y=\(String(format: "%.4f", correction.imag.y)), z=\(String(format: "%.4f", correction.imag.z))
        Total rotation angle: \(String(format: "%.1f", angle))°
        Rotation axis: (\(String(format: "%.3f", axis.x)), \(String(format: "%.3f", axis.y)), \(String(format: "%.3f", axis.z)))

        Effect on ARKit vectors:
        - ARKit forward (0,0,-1) → (\(String(format: "%.3f", rotatedForward.x)), \(String(format: "%.3f", rotatedForward.y)), \(String(format: "%.3f", rotatedForward.z)))
        - ARKit up (0,1,0) → (\(String(format: "%.3f", rotatedUp.x)), \(String(format: "%.3f", rotatedUp.y)), \(String(format: "%.3f", rotatedUp.z)))

        Alternative (180° Y rotation only):
        - Forward (0,0,-1) → (\(String(format: "%.3f", altForward.x)), \(String(format: "%.3f", altForward.y)), \(String(format: "%.3f", altForward.z)))
        - Up (0,1,0) → (\(String(format: "%.3f", altUp.x)), \(String(format: "%.3f", altUp.y)), \(String(format: "%.3f", altUp.z)))
        """

        // Issue detected: The current correction rotates the up vector to point along +X
        // This means a person standing upright would have their "up" pointing sideways
        let upRotatedToX = abs(rotatedUp.x) > 0.9
        let upStaysUp = abs(rotatedUp.y) > 0.9

        if upRotatedToX {
            report += """


            ⚠️  BUG DETECTED: Root correction rotates UP to point along X axis!
            This would cause the avatar to appear rotated 90° sideways.

            FIX: The -90° X rotation is likely incorrect.
            Both ARKit and VRM are Y-up, so we only need to flip facing direction.
            Recommend changing to 180° Y rotation only (flip forward from -Z to +Z).
            """
        }

        XCTAssertTrue(upStaysUp,
            "Root correction should preserve Y-up orientation.\n\nDiagnostic Report:\n\(report)")
    }

    // MARK: - Single-Axis Rotation Tests

    /// Test: Hips yaw rotation (turn left/right)
    func testHipsYawRotation() {
        let originalCalibration = ARKitToVRMConverter.restPoseCalibrationEnabled
        ARKitToVRMConverter.restPoseCalibrationEnabled = false
        defer { ARKitToVRMConverter.restPoseCalibrationEnabled = originalCalibration }

        print("\n=== Hips Yaw (Turn) Test ===")

        // Create skeleton with hips rotated 45° around Y (yaw/turn)
        var skeleton = createIdentitySkeleton()
        let yaw45 = rotationMatrix(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        skeleton = ARKitBodySkeleton(
            timestamp: skeleton.timestamp,
            joints: skeleton.joints.merging([.hips: yaw45]) { _, new in new },
            isTracked: true
        )

        let inputQuat = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        printQuaternion("Input (45° Y)", inputQuat)

        if let result = ARKitToVRMConverter.computeVRMRotation(
            joint: .hips,
            childTransform: yaw45,
            skeleton: skeleton
        ) {
            printQuaternion("Output", result)
            let outputAngle = angleDegrees(result)
            print("  Output angle: \(String(format: "%.1f", outputAngle))°")

            // The rotation should be preserved (though axis may change due to coordinate conversion)
            // We expect roughly 45° of rotation
            // Note: Due to root correction, the actual angle may differ
        }
    }

    /// Test: Arm raise direction analysis
    ///
    /// In VRM T-pose:
    /// - Left arm points along +X (to the avatar's left)
    /// - Raising the arm (rotating toward +Y) requires rotation around Z
    /// - Arm forward/back (toward +Z/-Z) requires rotation around Y
    ///
    /// The test verifies that ARKit arm rotations map to correct VRM directions.
    func testArmRaiseDirection() {
        let originalCalibration = ARKitToVRMConverter.restPoseCalibrationEnabled
        ARKitToVRMConverter.restPoseCalibrationEnabled = false
        defer { ARKitToVRMConverter.restPoseCalibrationEnabled = originalCalibration }

        var skeleton = createIdentitySkeleton()

        // Test 1: Rotate left upper arm 90° around Z (should raise arm toward Y)
        let armRaiseZ = rotationMatrix(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        skeleton = ARKitBodySkeleton(
            timestamp: skeleton.timestamp,
            joints: skeleton.joints.merging([.leftUpperArm: armRaiseZ]) { _, new in new },
            isTracked: true
        )

        guard let resultZ = ARKitToVRMConverter.computeVRMRotation(
            joint: .leftUpperArm,
            childTransform: armRaiseZ,
            skeleton: skeleton
        ) else {
            XCTFail("Left arm rotation computation returned nil - parent (upperChest) missing")
            return
        }

        let axisZ = rotationAxis(resultZ)
        let angleZ = angleDegrees(resultZ)

        // Test 2: Rotate left upper arm 90° around Y (should move arm forward/back)
        let armRotateY = rotationMatrix(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        skeleton = ARKitBodySkeleton(
            timestamp: skeleton.timestamp,
            joints: skeleton.joints.merging([.leftUpperArm: armRotateY]) { _, new in new },
            isTracked: true
        )

        guard let resultY = ARKitToVRMConverter.computeVRMRotation(
            joint: .leftUpperArm,
            childTransform: armRotateY,
            skeleton: skeleton
        ) else {
            XCTFail("Left arm Y rotation computation returned nil")
            return
        }

        let axisY = rotationAxis(resultY)
        let angleY = angleDegrees(resultY)

        // Document findings
        let report = """
        === Arm Axis Direction Analysis ===

        Input 1: 90° rotation around Z (arm raise)
        Output axis: (\(String(format: "%.3f", axisZ.x)), \(String(format: "%.3f", axisZ.y)), \(String(format: "%.3f", axisZ.z)))
        Output angle: \(String(format: "%.1f", angleZ))°

        Input 2: 90° rotation around Y (arm forward/back)
        Output axis: (\(String(format: "%.3f", axisY.x)), \(String(format: "%.3f", axisY.y)), \(String(format: "%.3f", axisY.z)))
        Output angle: \(String(format: "%.1f", angleY))°

        For VRM left arm:
        - Z rotation should raise/lower arm (toward +Y/-Y)
        - Y rotation should move arm forward/back (toward +Z/-Z)
        - X rotation should twist the arm

        Analysis:
        - Input Z rotation → Output primarily \(abs(axisZ.z) > abs(axisZ.y) ? "Z" : "Y") axis
        - Input Y rotation → Output primarily \(abs(axisY.y) > abs(axisY.z) ? "Y" : "Z") axis
        """

        // Verify that axes are preserved (no swapping)
        // Z input should still be primarily Z output
        // Y input should still be primarily Y output
        let zPreserved = abs(axisZ.z) > 0.5
        let yPreserved = abs(axisY.y) > 0.5

        if !zPreserved {
            XCTFail("Z-axis rotation not preserved for arm.\n\n\(report)\n\n" +
                    "The current axis swap (x,z,y) may be swapping Y and Z incorrectly.")
        }

        if !yPreserved {
            XCTFail("Y-axis rotation not preserved for arm.\n\n\(report)")
        }
    }

    /// Test: Spine forward bend
    func testSpineForwardBend() {
        let originalCalibration = ARKitToVRMConverter.restPoseCalibrationEnabled
        ARKitToVRMConverter.restPoseCalibrationEnabled = false
        defer { ARKitToVRMConverter.restPoseCalibrationEnabled = originalCalibration }

        print("\n=== Spine Forward Bend Test ===")

        var skeleton = createIdentitySkeleton()

        // Bend spine 30° forward (around X axis)
        let spineBend = rotationMatrix(angle: .pi / 6, axis: SIMD3<Float>(1, 0, 0))
        skeleton = ARKitBodySkeleton(
            timestamp: skeleton.timestamp,
            joints: skeleton.joints.merging([.spine: spineBend]) { _, new in new },
            isTracked: true
        )

        let inputQuat = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(1, 0, 0))
        printQuaternion("Input (30° X - forward bend)", inputQuat)

        if let result = ARKitToVRMConverter.computeVRMRotation(
            joint: .spine,
            childTransform: spineBend,
            skeleton: skeleton
        ) {
            printQuaternion("Output", result)

            let axis = rotationAxis(result)
            print("  Output rotation axis: (\(String(format: "%.3f", axis.x)), \(String(format: "%.3f", axis.y)), \(String(format: "%.3f", axis.z)))")

            // Forward bend should be around X axis
            let xComponent = abs(axis.x)
            print("  X component: \(String(format: "%.3f", xComponent))")

            if xComponent > 0.9 {
                print("  ✓ Spine bends around X axis (correct for forward bend)")
            } else {
                print("  ⚠️ Spine rotation axis is not X (may cause sideways or twist)")
            }
        }
    }

    // MARK: - Left-Side Mirroring Tests

    /// Test: Left-side mirroring is applied correctly
    func testLeftSideMirroring() {
        let originalCalibration = ARKitToVRMConverter.restPoseCalibrationEnabled
        ARKitToVRMConverter.restPoseCalibrationEnabled = false
        defer { ARKitToVRMConverter.restPoseCalibrationEnabled = originalCalibration }

        print("\n=== Left-Side Mirroring Test ===")

        // Test with a simple rotation to see mirroring effect
        let testRotation = simd_quatf(angle: .pi / 4, axis: simd_normalize(SIMD3<Float>(1, 1, 0)))

        // Apply to left arm
        let leftResult = ARKitToVRMConverter.convertLocalRotation(testRotation, joint: .leftUpperArm)
        // Apply to right arm
        let rightResult = ARKitToVRMConverter.convertLocalRotation(testRotation, joint: .rightUpperArm)

        printQuaternion("Input rotation", testRotation)
        printQuaternion("Left arm result", leftResult)
        printQuaternion("Right arm result", rightResult)

        // Check that left and right produce different results (mirroring applied)
        let diff = simd_length(leftResult.imag - rightResult.imag) + abs(leftResult.real - rightResult.real)
        print("\n  Difference between left and right: \(String(format: "%.4f", diff))")

        if diff > 0.01 {
            print("  ✓ Left-side mirroring is being applied")
        } else {
            print("  ⚠️ Left and right produce same result - mirroring may not be working")
        }
    }

    // MARK: - Conversion Pipeline Detailed Analysis

    /// Test: Print detailed conversion pipeline for each step
    func testConversionPipelineDetailedAnalysis() {
        print("\n=== Conversion Pipeline Detailed Analysis ===")

        let testRotation = simd_quatf(angle: .pi / 4, axis: simd_normalize(SIMD3<Float>(1, 0, 0)))
        print("\nInput rotation (45° around X):")
        printQuaternion("  Original", testRotation)

        // Step 1: Normalize to positive w
        var q = testRotation
        if q.real < 0 {
            q = simd_quatf(real: -q.real, imag: -q.imag)
        }
        printQuaternion("  After positive-w normalization", q)

        // Step 2: Left-side mirroring (for left arm)
        let leftMirrored = simd_quatf(real: q.real, imag: SIMD3<Float>(-q.imag.x, q.imag.y, -q.imag.z))
        printQuaternion("  After left-side mirroring (-x, y, -z)", leftMirrored)

        // Step 3: Arm axis swap (x, z, y)
        let axisSwapped = simd_quatf(real: leftMirrored.real, imag: SIMD3<Float>(leftMirrored.imag.x, leftMirrored.imag.z, leftMirrored.imag.y))
        printQuaternion("  After arm axis swap (x, z, y)", axisSwapped)

        print("\nCompare with direct convertLocalRotation:")
        let directResult = ARKitToVRMConverter.convertLocalRotation(testRotation, joint: .leftUpperArm)
        printQuaternion("  convertLocalRotation result", directResult)
    }

    // MARK: - Extract Rotation Tests

    /// Test: extractRotation handles scale correctly
    func testExtractRotationWithScale() {
        print("\n=== Extract Rotation with Scale Test ===")

        // Create a rotation matrix with non-uniform scale
        let rotation = simd_quatf(angle: .pi / 3, axis: simd_normalize(SIMD3<Float>(1, 1, 1)))
        var matrix = simd_float4x4(rotation)

        // Apply non-uniform scale (2x on X, 0.5x on Y, 1.5x on Z)
        matrix.columns.0 *= 2.0
        matrix.columns.1 *= 0.5
        matrix.columns.2 *= 1.5

        let extracted = ARKitToVRMConverter.extractRotation(from: matrix)

        printQuaternion("Original rotation", rotation)
        printQuaternion("Extracted from scaled matrix", extracted)

        // The extracted rotation should be very close to the original
        let diff = simd_length(extracted.imag - rotation.imag) + abs(extracted.real - rotation.real)
        print("  Difference: \(String(format: "%.6f", diff))")

        XCTAssertLessThan(diff, 0.01, "Extracted rotation should match original despite scale")
    }

    // MARK: - Parent Hierarchy Tests

    /// Test: Parent hierarchy is correctly defined
    func testParentHierarchyCompleteness() {
        print("\n=== Parent Hierarchy Completeness Test ===")

        let parentMap = ARKitToVRMConverter.arkitParentMap

        // All non-root joints should have a parent
        let jointsWithParents: [ARKitJoint] = [
            .spine, .chest, .upperChest, .neck, .head,
            .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
            .rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand,
            .leftUpperLeg, .leftLowerLeg, .leftFoot, .leftToes,
            .rightUpperLeg, .rightLowerLeg, .rightFoot, .rightToes
        ]

        var missingParents: [ARKitJoint] = []

        for joint in jointsWithParents {
            if parentMap[joint] == nil {
                missingParents.append(joint)
            }
        }

        if missingParents.isEmpty {
            print("  ✓ All non-root joints have parents defined")
        } else {
            print("  ⚠️ Missing parents for: \(missingParents.map { $0.rawValue })")
        }

        XCTAssertTrue(missingParents.isEmpty, "All non-root joints should have parents")

        // Hips should NOT have a parent (it's the root)
        XCTAssertNil(parentMap[.hips], "Hips should not have a parent (it's root)")
    }

    // MARK: - Integration Test

    /// Test: Full pipeline with realistic skeleton data
    func testFullPipelineWithRealisticData() {
        print("\n=== Full Pipeline Integration Test ===")

        // Create a skeleton representing a person standing with arms slightly raised
        var joints: [ARKitJoint: simd_float4x4] = [:]

        // Hips: slight yaw (turned 10°)
        joints[.hips] = rotationMatrix(angle: .pi / 18, axis: SIMD3<Float>(0, 1, 0))

        // Spine chain: identity (standing straight)
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)

        // Head: nodding down slightly (10°)
        joints[.neck] = simd_float4x4(1)
        joints[.head] = rotationMatrix(angle: .pi / 18, axis: SIMD3<Float>(1, 0, 0))

        // Arms: raised 30° from sides
        let leftArmRaise = rotationMatrix(angle: .pi / 6, axis: SIMD3<Float>(0, 0, 1))
        let rightArmRaise = rotationMatrix(angle: -.pi / 6, axis: SIMD3<Float>(0, 0, 1))
        joints[.leftShoulder] = simd_float4x4(1)
        joints[.leftUpperArm] = leftArmRaise
        joints[.leftLowerArm] = simd_float4x4(1)
        joints[.leftHand] = simd_float4x4(1)
        joints[.rightShoulder] = simd_float4x4(1)
        joints[.rightUpperArm] = rightArmRaise
        joints[.rightLowerArm] = simd_float4x4(1)
        joints[.rightHand] = simd_float4x4(1)

        // Legs: standing straight
        joints[.leftUpperLeg] = simd_float4x4(1)
        joints[.leftLowerLeg] = simd_float4x4(1)
        joints[.leftFoot] = simd_float4x4(1)
        joints[.rightUpperLeg] = simd_float4x4(1)
        joints[.rightLowerLeg] = simd_float4x4(1)
        joints[.rightFoot] = simd_float4x4(1)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true
        )

        print("Input pose: Standing, turned 10° right, head nodding 10°, arms raised 30°")
        print("\nConverted rotations:")

        let keyJoints: [ARKitJoint] = [
            .hips, .spine, .head, .leftUpperArm, .rightUpperArm
        ]

        for joint in keyJoints {
            guard let transform = skeleton.joints[joint] else { continue }
            if let rotation = ARKitToVRMConverter.computeVRMRotation(
                joint: joint,
                childTransform: transform,
                skeleton: skeleton
            ) {
                printQuaternion("  \(joint.rawValue)", rotation)
            } else {
                print("  \(joint.rawValue): nil")
            }
        }
    }
}
