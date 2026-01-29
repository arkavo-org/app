//
// RealARKitDataTests.swift
// ArkavoCreatorTests
//
// Tests using real ARKit data captured from pipeline diagnostics session.
// Verifies VRMARecorder conversion matches ARKitBodyDriver (live preview).
//

import XCTest
import simd
import VRMMetalKit
@testable import ArkavoCreator

@MainActor
final class RealARKitDataTests: XCTestCase {

    // MARK: - Test with Real Captured Data

    /// Test conversion using real ARKit transforms from captured session
    func testRealARKitDataConversion() throws {
        // Sample real transforms from captured session (first frame)
        // These are actual ARKit joint transforms from a body tracking session

        // left_shoulder_1_joint transform (real ARKit data)
        let leftShoulderTransform: [Float] = [
            0.59065187, 0.16904375, 0.7890214, 0,
            0.27553624, -0.9612907, -0.00031154818, 0,
            0.7584262, 0.21758798, -0.61436576, 0,
            0.6982431, 0.61384857, 0.34776688, 1
        ]

        // hips_joint transform (real ARKit data)
        let hipsTransform: [Float] = [
            0.9970515, 0.072551645, -0.0249928, 0,
            -0.07259704, 0.99735737, 0.0047571384, 0,
            0.025271352, -0.0029234567, 0.9996762, 0,
            0.09999701, -0.008894193, -0.00025986493, 1
        ]

        // spine_1_joint transform
        let spineTransform: [Float] = [
            0.09836091, -0.84357136, -0.5279323, 0,
            -0.04326178, 0.5263786, -0.849149, 0,
            0.99421, 0.10636239, 0.015280708, 0,
            0.13185877, -0.42316395, 0.06823381, 1
        ]

        // Build skeleton from real data
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = toMatrix(hipsTransform)
        joints[.spine] = toMatrix(spineTransform)
        joints[.leftShoulder] = toMatrix(leftShoulderTransform)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )

        // Test hips conversion
        if let hipsRotation = ARKitCoordinateConverter.computeVRMRotation(
            joint: .hips,
            childTransform: joints[.hips]!,
            skeleton: skeleton
        ) {
            // Hips should have coordinate correction applied
            XCTAssertFalse(isIdentity(hipsRotation),
                "Hips should have coordinate correction, not be identity")

            // Verify quaternion is normalized
            let length = sqrt(
                hipsRotation.imag.x * hipsRotation.imag.x +
                hipsRotation.imag.y * hipsRotation.imag.y +
                hipsRotation.imag.z * hipsRotation.imag.z +
                hipsRotation.real * hipsRotation.real
            )
            XCTAssertEqual(length, 1.0, accuracy: 0.01,
                "Quaternion should be normalized")

            print("Hips rotation: (\(hipsRotation.imag.x), \(hipsRotation.imag.y), \(hipsRotation.imag.z), \(hipsRotation.real))")
        } else {
            XCTFail("Failed to compute hips rotation")
        }

        // Test spine local rotation
        if let spineRotation = ARKitCoordinateConverter.computeVRMRotation(
            joint: .spine,
            childTransform: joints[.spine]!,
            skeleton: skeleton
        ) {
            // Spine is child of hips - should be local rotation
            let length = sqrt(
                spineRotation.imag.x * spineRotation.imag.x +
                spineRotation.imag.y * spineRotation.imag.y +
                spineRotation.imag.z * spineRotation.imag.z +
                spineRotation.real * spineRotation.real
            )
            XCTAssertEqual(length, 1.0, accuracy: 0.01,
                "Quaternion should be normalized")

            print("Spine local rotation: (\(spineRotation.imag.x), \(spineRotation.imag.y), \(spineRotation.imag.z), \(spineRotation.real))")
        } else {
            XCTFail("Failed to compute spine rotation")
        }
    }

    /// Test that conversion produces valid quaternions for both sides
    ///
    /// With rest pose calibration, left and right have DIFFERENT calibration values
    /// because ARKit's local coordinate systems are asymmetric (left arm ~166° from identity,
    /// right arm ~40° from identity). The calibration normalizes both to a common space.
    func testLeftRightConversionProducesValidQuaternions() {
        // Create skeleton with identity matrices (tests conversion with rest pose subtraction)
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)
        joints[.leftShoulder] = simd_float4x4(1)
        joints[.rightShoulder] = simd_float4x4(1)
        joints[.leftUpperArm] = simd_float4x4(1)
        joints[.rightUpperArm] = simd_float4x4(1)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )

        let leftArmRot = ARKitCoordinateConverter.computeVRMRotation(
            joint: .leftUpperArm,
            childTransform: joints[.leftUpperArm]!,
            skeleton: skeleton
        )

        let rightArmRot = ARKitCoordinateConverter.computeVRMRotation(
            joint: .rightUpperArm,
            childTransform: joints[.rightUpperArm]!,
            skeleton: skeleton
        )

        XCTAssertNotNil(leftArmRot, "Left arm rotation should be computed")
        XCTAssertNotNil(rightArmRot, "Right arm rotation should be computed")

        if let left = leftArmRot, let right = rightArmRot {
            // Verify quaternions are normalized
            let leftLength = sqrt(left.imag.x * left.imag.x + left.imag.y * left.imag.y +
                                  left.imag.z * left.imag.z + left.real * left.real)
            let rightLength = sqrt(right.imag.x * right.imag.x + right.imag.y * right.imag.y +
                                   right.imag.z * right.imag.z + right.real * right.real)

            XCTAssertEqual(leftLength, 1.0, accuracy: 0.01, "Left quaternion should be normalized")
            XCTAssertEqual(rightLength, 1.0, accuracy: 0.01, "Right quaternion should be normalized")

            print("Left arm: (\(left.imag.x), \(left.imag.y), \(left.imag.z), \(left.real))")
            print("Right arm: (\(right.imag.x), \(right.imag.y), \(right.imag.z), \(right.real))")

            // Note: Left and right outputs will be DIFFERENT because they have different
            // rest pose calibration values. This is correct - ARKit's skeleton is asymmetric.
        }
    }

    /// Test VRMARecorder produces same output as direct ARKitCoordinateConverter
    func testRecorderMatchesConverter() {
        let recorder = VRMARecorder(frameRate: 30)

        // Create test skeleton
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)
        joints[.neck] = simd_float4x4(1)
        joints[.head] = simd_float4x4(1)
        joints[.leftShoulder] = simd_float4x4(1)
        joints[.rightShoulder] = simd_float4x4(1)
        joints[.leftUpperArm] = simd_float4x4(1)
        joints[.rightUpperArm] = simd_float4x4(1)
        joints[.leftUpperLeg] = simd_float4x4(1)
        joints[.rightUpperLeg] = simd_float4x4(1)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )

        var capturedRotations: [VRMHumanoidBone: simd_quatf] = [:]

        recorder.diagnosticsCallback = { _, rotations, _, _, _ in
            capturedRotations = rotations
        }

        recorder.startRecording()
        recorder.appendBodyFrame(body: skeleton, timestamp: Date().addingTimeInterval(0.05))
        _ = recorder.stopRecording()

        // Verify hips matches direct converter call
        let expectedHips = ARKitCoordinateConverter.computeVRMRotation(
            joint: .hips,
            childTransform: joints[.hips]!,
            skeleton: skeleton
        )

        if let hips = capturedRotations[.hips], let expected = expectedHips {
            let angle = angleBetween(hips, expected)
            XCTAssertLessThan(angle, 1.0,
                "Recorder hips should match converter. Angle diff: \(angle)°")
        } else {
            XCTFail("Missing hips rotation")
        }

        // Verify spine matches
        let expectedSpine = ARKitCoordinateConverter.computeVRMRotation(
            joint: .spine,
            childTransform: joints[.spine]!,
            skeleton: skeleton
        )

        if let spine = capturedRotations[.spine], let expected = expectedSpine {
            let angle = angleBetween(spine, expected)
            XCTAssertLessThan(angle, 1.0,
                "Recorder spine should match converter. Angle diff: \(angle)°")
        } else {
            XCTFail("Missing spine rotation")
        }
    }

    // MARK: - Helpers

    private func toMatrix(_ values: [Float]) -> simd_float4x4 {
        precondition(values.count == 16)
        return simd_float4x4(
            simd_float4(values[0], values[1], values[2], values[3]),
            simd_float4(values[4], values[5], values[6], values[7]),
            simd_float4(values[8], values[9], values[10], values[11]),
            simd_float4(values[12], values[13], values[14], values[15])
        )
    }

    private func isIdentity(_ q: simd_quatf) -> Bool {
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        return angleBetween(q, identity) < 1.0
    }

    private func angleBetween(_ q1: simd_quatf, _ q2: simd_quatf) -> Float {
        let dot = abs(simd_dot(q1, q2))
        let clampedDot = min(1.0, dot)
        return 2.0 * acos(clampedDot) * 180.0 / .pi
    }
}
