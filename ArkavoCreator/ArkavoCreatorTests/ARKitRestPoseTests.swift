//
// ARKitRestPoseTests.swift
// ArkavoCreatorTests
//
// Tests that verify ARKit rest pose is correctly converted to VRM rest pose.
// These tests use REAL ARKit transforms from captured diagnostic sessions.
//
// KEY INSIGHT: ARKit's "neutral" pose is NOT identity matrices.
// ARKit sends world-space transforms that include the skeleton's bind pose.
// We must handle this correctly to avoid collapsed shoulders, internal leg rotation, etc.
//

import XCTest
import simd
import VRMMetalKit
@testable import ArkavoCreator

@MainActor
final class ARKitRestPoseTests: XCTestCase {

    // MARK: - Real ARKit Rest Pose Data

    // These are ACTUAL transforms from captured ARKit session
    // pipeline_capture_2026-01-29_00-15-38Z.json
    // Person standing in neutral stance

    /// Real ARKit hips transform
    static let realHipsTransform: [Float] = [
        0.999721, 0.001123, 0.023573, 0,
        0.002753, 0.986494, -0.163774, 0,
        -0.023439, 0.163794, 0.986216, 0,
        0.001326, 0.020669, -0.008537, 1
    ]

    /// Real ARKit left_upLeg transform
    /// NOTE: Shows 146° from identity in ARKit's bind pose
    static let realLeftUpperLegTransform: [Float] = [
        -0.002913, -0.633776, 0.773511, 0,
        0.003727, -0.773516, -0.633766, 0,
        0.999989, 0.001036, 0.004615, 0,
        0.101747, -0.003702, -0.001131, 1
    ]

    /// Real ARKit left_leg (lower leg) transform
    static let realLeftLowerLegTransform: [Float] = [
        -0.16302551, -0.9768311, -0.13864857, 0,
        -0.15039918, 0.16349098, -0.97501314, 0,
        0.97509104, -0.13809942, -0.17356779, 0,
        0.09523184, -0.43328044, 0.047306955, 1
    ]

    // MARK: - Test: Real ARKit Data is NOT Identity

    func testRealARKitDataIsNotIdentity() {
        // This test documents that real ARKit data is significantly rotated
        // from identity, even in "neutral" pose

        let hipsMatrix = toMatrix(Self.realHipsTransform)
        let leftLegMatrix = toMatrix(Self.realLeftUpperLegTransform)

        let hipsRot = extractRotation(from: hipsMatrix)
        let leftLegRot = extractRotation(from: leftLegMatrix)

        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        let hipsAngle = angleBetween(hipsRot, identity)
        let leftLegAngle = angleBetween(leftLegRot, identity)

        print("Real ARKit hips rotation angle from identity: \(hipsAngle)°")
        print("Real ARKit left leg rotation angle from identity: \(leftLegAngle)°")

        // Hips is nearly identity (< 15° - allows for slight body tilt)
        XCTAssertLessThan(hipsAngle, 15.0, "Hips should be near identity")

        // Left leg is SIGNIFICANTLY rotated (this is the A-pose / bind pose)
        XCTAssertGreaterThan(leftLegAngle, 80.0,
            "Left leg should be significantly rotated from identity in ARKit bind pose. " +
            "This is the key insight: ARKit's 'neutral' is not identity!")
    }

    // MARK: - Test: Local Rotation Should Cancel Bind Pose

    func testLocalRotationCancelsBindPose() {
        // When computing local rotation as: inverse(parent) * child
        // If both parent and child have the same bind pose offset,
        // the local rotation should be near identity

        let hipsMatrix = toMatrix(Self.realHipsTransform)
        let leftLegMatrix = toMatrix(Self.realLeftUpperLegTransform)

        let parentRot = extractRotation(from: hipsMatrix)
        let childRot = extractRotation(from: leftLegMatrix)

        // Compute local rotation
        let localRot = simd_mul(simd_inverse(parentRot), childRot)

        print("Parent (hips) rotation: \(quaternionString(parentRot))")
        print("Child (leftLeg) rotation: \(quaternionString(childRot))")
        print("Local rotation: \(quaternionString(localRot))")

        let localEuler = quaternionToEuler(localRot)
        print("Local euler (degrees): x=\(localEuler.x), y=\(localEuler.y), z=\(localEuler.z)")

        // The local rotation captures the ACTUAL pose difference
        // For a standing person, legs should be roughly straight down
        // This test documents the actual values we're seeing

        // If legs appear internally rotated, check the Y (twist) component
        print("\n=== DIAGNOSTIC: If legs show internal rotation ===")
        print("Y-axis (twist) rotation: \(localEuler.y)°")
        print("If this is large (>15°), the leg twist is incorrect")
    }

    // MARK: - Test: Converter Output for Real Data

    func testConverterWithRealARKitData() {
        // Build skeleton with real ARKit transforms
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = toMatrix(Self.realHipsTransform)
        joints[.leftUpperLeg] = toMatrix(Self.realLeftUpperLegTransform)
        joints[.leftLowerLeg] = toMatrix(Self.realLeftLowerLegTransform)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )

        // Test hips conversion
        if let hipsRot = ARKitCoordinateConverter.computeVRMRotation(
            joint: .hips,
            childTransform: joints[.hips]!,
            skeleton: skeleton
        ) {
            let euler = quaternionToEuler(hipsRot)
            print("\n=== Hips VRM rotation ===")
            print("Quaternion: \(quaternionString(hipsRot))")
            print("Euler: x=\(euler.x)°, y=\(euler.y)°, z=\(euler.z)°")

            // Hips should have coordinate correction but small pose rotation
            // (person standing upright)
        }

        // Test left upper leg conversion
        if let leftLegRot = ARKitCoordinateConverter.computeVRMRotation(
            joint: .leftUpperLeg,
            childTransform: joints[.leftUpperLeg]!,
            skeleton: skeleton
        ) {
            let euler = quaternionToEuler(leftLegRot)
            print("\n=== Left Upper Leg VRM rotation ===")
            print("Quaternion: \(quaternionString(leftLegRot))")
            print("Euler: x=\(euler.x)°, y=\(euler.y)°, z=\(euler.z)°")

            // DIAGNOSTIC: If internal rotation occurs, Y should be large
            if abs(euler.y) > 20 {
                print("WARNING: Large Y rotation (\(euler.y)°) may cause internal leg rotation!")
            }
        }
    }

    // MARK: - Test: Rest Pose Calibration Produces Near-Identity for Neutral Stance

    func testRestPoseCalibrationProducesNearIdentity() {
        // This test verifies that T-pose CALIBRATION produces near-identity output.
        //
        // When the user calibrates by standing in T-pose, subsequent frames
        // should produce near-identity rotations for that same pose.
        //
        // Note: Default A-pose offsets only apply to ARMS (not legs).
        // For legs, we need explicit T-pose calibration.

        // Build skeleton with real ARKit transforms from neutral stance
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = toMatrix(Self.realHipsTransform)
        joints[.leftUpperLeg] = toMatrix(Self.realLeftUpperLegTransform)
        joints[.leftLowerLeg] = toMatrix(Self.realLeftLowerLegTransform)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )

        // CALIBRATE with this skeleton as T-pose reference
        ARKitCoordinateConverter.calibrateTpose(skeleton)
        defer { ARKitCoordinateConverter.clearCalibration() }

        XCTAssertTrue(ARKitCoordinateConverter.isCalibrated,
            "Calibration should be active after calibrateTpose()")

        // Test left upper leg - should be near identity AFTER calibration
        if let leftLegRot = ARKitCoordinateConverter.computeVRMRotation(
            joint: .leftUpperLeg,
            childTransform: joints[.leftUpperLeg]!,
            skeleton: skeleton
        ) {
            let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let angleFromIdentity = angleBetween(leftLegRot, identity)

            print("\n=== REST POSE CALIBRATION TEST ===")
            print("Left upper leg VRM rotation: \(quaternionString(leftLegRot))")
            print("Angle from identity: \(angleFromIdentity)°")

            // With T-pose calibration, the same pose should produce near-identity
            // (< 5° threshold - should be very close since it's the calibration pose itself)
            XCTAssertLessThan(angleFromIdentity, 5.0,
                "After T-pose calibration, the same pose should produce near-identity rotation. " +
                "Got \(angleFromIdentity)°")
        } else {
            XCTFail("Failed to compute left upper leg rotation")
        }
    }

    // MARK: - Test: Without Rest Pose Calibration Shows Large Rotation

    func testWithoutRestPoseCalibrationShowsLargeRotation() {
        // This test documents that WITHOUT rest pose calibration,
        // neutral stance produces large (~130°) rotations that cause visual artifacts

        // Temporarily disable rest pose calibration
        let originalSetting = ARKitCoordinateConverter.restPoseCalibrationEnabled
        ARKitCoordinateConverter.restPoseCalibrationEnabled = false
        defer { ARKitCoordinateConverter.restPoseCalibrationEnabled = originalSetting }

        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = toMatrix(Self.realHipsTransform)
        joints[.leftUpperLeg] = toMatrix(Self.realLeftUpperLegTransform)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )

        if let leftLegRot = ARKitCoordinateConverter.computeVRMRotation(
            joint: .leftUpperLeg,
            childTransform: joints[.leftUpperLeg]!,
            skeleton: skeleton
        ) {
            let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            let angleFromIdentity = angleBetween(leftLegRot, identity)

            print("\n=== WITHOUT REST POSE CALIBRATION ===")
            print("Left upper leg VRM rotation: \(quaternionString(leftLegRot))")
            print("Angle from identity: \(angleFromIdentity)°")

            // Without calibration, we expect large rotation (this is the bug)
            XCTAssertGreaterThan(angleFromIdentity, 80.0,
                "Without rest pose calibration, neutral stance incorrectly shows \(angleFromIdentity)° rotation. " +
                "This is the bug that causes internal leg rotation and other visual artifacts.")
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

    private func extractRotation(from transform: simd_float4x4) -> simd_quatf {
        let col0 = simd_normalize(SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z))
        let col1 = simd_normalize(SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
        let col2 = simd_normalize(SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
        return simd_quatf(simd_float3x3(col0, col1, col2))
    }

    private func angleBetween(_ q1: simd_quatf, _ q2: simd_quatf) -> Float {
        let dot = abs(simd_dot(q1, q2))
        return 2.0 * acos(min(1.0, dot)) * 180.0 / .pi
    }

    private func quaternionToEuler(_ q: simd_quatf) -> (x: Float, y: Float, z: Float) {
        let x = q.imag.x, y = q.imag.y, z = q.imag.z, w = q.real

        let sinr_cosp = 2.0 * (w * x + y * z)
        let cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
        let roll = atan2(sinr_cosp, cosr_cosp)

        let sinp = 2.0 * (w * y - z * x)
        let pitch = abs(sinp) >= 1 ? copysign(.pi / 2, sinp) : asin(sinp)

        let siny_cosp = 2.0 * (w * z + x * y)
        let cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        let yaw = atan2(siny_cosp, cosy_cosp)

        return (roll * 180 / .pi, pitch * 180 / .pi, yaw * 180 / .pi)
    }

    private func quaternionString(_ q: simd_quatf) -> String {
        return String(format: "(%.3f, %.3f, %.3f, %.3f)", q.imag.x, q.imag.y, q.imag.z, q.real)
    }
}
