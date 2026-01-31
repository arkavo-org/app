//
// PoseCalibrationDiagnosticTests.swift
// ArkavoCreatorTests
//
// Diagnostic tests to capture and analyze real ARKit data for pose calibration.
// Run these interactively while striking specific poses to determine correct
// A-pose → T-pose compensation values.
//
// Usage:
// 1. Run testCaptureAPose - stand naturally with arms relaxed
// 2. Run testCaptureTPose - hold arms out horizontally
// 3. Compare the output to calculate the offset
//

import simd
import VRMMetalKit
import XCTest
@testable import ArkavoCreator

@MainActor
final class PoseCalibrationDiagnosticTests: XCTestCase {

    // MARK: - Quaternion Analysis Helpers

    /// Get angle in degrees from quaternion
    private func angleDegrees(_ q: simd_quatf) -> Float {
        return 2 * acos(min(abs(q.real), 1.0)) * 180.0 / .pi
    }

    /// Get rotation axis from quaternion
    private func rotationAxis(_ q: simd_quatf) -> SIMD3<Float> {
        let sinAngle = simd_length(q.imag)
        if sinAngle < 0.0001 {
            return SIMD3<Float>(0, 1, 0)
        }
        return q.imag / sinAngle
    }

    /// Format quaternion for display
    private func formatQuat(_ q: simd_quatf) -> String {
        let angle = angleDegrees(q)
        let axis = rotationAxis(q)
        return String(format: "%.1f° around (%.2f, %.2f, %.2f) | w=%.3f xyz=(%.3f, %.3f, %.3f)",
                      angle, axis.x, axis.y, axis.z,
                      q.real, q.imag.x, q.imag.y, q.imag.z)
    }

    // MARK: - Pose Analysis

    /// Analyze a captured skeleton and print rotation details for key joints
    private func analyzeSkeleton(_ skeleton: ARKitBodySkeleton, poseName: String) {
        print("\n" + String(repeating: "=", count: 60))
        print("POSE: \(poseName)")
        print("Timestamp: \(skeleton.timestamp)")
        print("Tracked: \(skeleton.isTracked)")
        print(String(repeating: "=", count: 60))

        let keyJoints: [ARKitJoint] = [
            .hips, .spine, .chest, .upperChest,
            .leftShoulder, .leftUpperArm, .leftLowerArm,
            .rightShoulder, .rightUpperArm, .rightLowerArm
        ]

        print("\nRAW WORLD ROTATIONS (extracted from transforms):")
        for joint in keyJoints {
            guard let transform = skeleton.joints[joint] else {
                print("  \(joint.rawValue): MISSING")
                continue
            }
            let worldRot = ARKitToVRMConverter.extractRotation(from: transform)
            print("  \(joint.rawValue): \(formatQuat(worldRot))")
        }

        print("\nLOCAL ROTATIONS (relative to parent):")
        for joint in keyJoints {
            guard let childTransform = skeleton.joints[joint] else { continue }

            if let parentJoint = ARKitToVRMConverter.arkitParentMap[joint],
               let parentTransform = skeleton.joints[parentJoint] {
                let parentRot = ARKitToVRMConverter.extractRotation(from: parentTransform)
                let childRot = ARKitToVRMConverter.extractRotation(from: childTransform)
                let localRot = simd_mul(simd_inverse(parentRot), childRot)
                print("  \(joint.rawValue): \(formatQuat(localRot))")
            } else if joint == .hips {
                let worldRot = ARKitToVRMConverter.extractRotation(from: childTransform)
                print("  \(joint.rawValue) (root): \(formatQuat(worldRot))")
            }
        }

        print("\nCONVERTED VRM ROTATIONS (after all corrections):")
        for joint in keyJoints {
            guard let transform = skeleton.joints[joint] else { continue }
            if let vrmRot = ARKitToVRMConverter.computeVRMRotation(
                joint: joint,
                childTransform: transform,
                skeleton: skeleton
            ) {
                print("  \(joint.rawValue): \(formatQuat(vrmRot))")
            }
        }
    }

    // MARK: - Interactive Diagnostic Tests

    /// Test with hardcoded sample data (from previous capture)
    /// Replace these values with actual captured data
    func testAnalyzeSampleData() {
        // Sample transforms from real ARKit capture
        // Replace with actual captured data from your iOS device

        var joints: [ARKitJoint: simd_float4x4] = [:]

        // Hips transform (sample - replace with real data)
        joints[.hips] = simd_float4x4(
            simd_float4(0.997, 0.073, -0.025, 0),
            simd_float4(-0.073, 0.997, 0.005, 0),
            simd_float4(0.025, -0.003, 1.000, 0),
            simd_float4(0.1, -0.009, -0.0003, 1)
        )

        // Left shoulder transform (sample)
        joints[.leftShoulder] = simd_float4x4(
            simd_float4(0.591, 0.169, 0.789, 0),
            simd_float4(0.276, -0.961, -0.0003, 0),
            simd_float4(0.758, 0.218, -0.614, 0),
            simd_float4(0.698, 0.614, 0.348, 1)
        )

        // Left upper arm - this is what we need to analyze
        joints[.leftUpperArm] = simd_float4x4(1) // Replace with real data

        // Right upper arm
        joints[.rightUpperArm] = simd_float4x4(1) // Replace with real data

        // Add spine chain for parent lookups
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)

        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true
        )

        analyzeSkeleton(skeleton, poseName: "Sample Data (replace with real capture)")

        // This test always passes - it's for diagnostic output only
        XCTAssertTrue(true, "See console output for analysis")
    }

    /// Calculate offset between two poses
    func testCalculateAposeToTposeOffset() {
        print("\n" + String(repeating: "=", count: 60))
        print("A-POSE TO T-POSE OFFSET CALCULATION")
        print(String(repeating: "=", count: 60))

        // TODO: Replace with actual captured quaternions
        // Capture A-pose local rotation for leftUpperArm
        let aposeLeftArm = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // Replace

        // Capture T-pose local rotation for leftUpperArm
        let tposeLeftArm = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // Replace

        // Calculate offset: offset = inv(apose) * tpose
        // So that: apose * offset = tpose
        let offset = simd_mul(simd_inverse(aposeLeftArm), tposeLeftArm)

        print("\nLeft Upper Arm:")
        print("  A-pose local: \(formatQuat(aposeLeftArm))")
        print("  T-pose local: \(formatQuat(tposeLeftArm))")
        print("  Offset needed: \(formatQuat(offset))")

        // For VRM: we want identity when in T-pose
        // So we need: tpose * correction = identity
        // Therefore: correction = inv(tpose)
        // Or equivalently: when in A-pose, output = apose * correction = apose * inv(tpose)
        let correction = simd_inverse(tposeLeftArm)
        print("\n  VRM correction (to make T-pose → identity):")
        print("  \(formatQuat(correction))")

        XCTAssertTrue(true, "See console output for calculated offsets")
    }

    // MARK: - Current Code Analysis

    /// Print what the current code does - outputs via XCTFail for visibility
    func testShowCurrentOffsets() {
        var report = """
        ============================================================
        CURRENT A-POSE TO T-POSE OFFSETS IN CODE
        ============================================================

        """

        let offsets = ARKitToVRMConverter.aposeToTposeOffsets

        report += "\nConfigured offsets:\n"
        for (joint, offset) in offsets.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            report += "  \(joint.rawValue): \(formatQuat(offset))\n"
        }

        report += "\nEffect on identity input (simulating A-pose):\n"
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        for joint in [ARKitJoint.leftUpperArm, .rightUpperArm] {
            if let offset = offsets[joint] {
                let result = simd_mul(identity, offset)
                report += "  \(joint.rawValue): identity × offset = \(formatQuat(result))\n"
            }
        }

        report += "\nEffect on +45° Z input (simulating T-pose in ARKit):\n"
        let tposeInput = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1))
        report += "  Input: \(formatQuat(tposeInput))\n"

        if let offset = offsets[.leftUpperArm] {
            let result = simd_mul(tposeInput, offset)
            report += "  leftUpperArm: input × offset = \(formatQuat(result))\n"
        }

        report += "\nEffect on -45° Z input (simulating arms below A-pose):\n"
        let belowApose = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(0, 0, 1))
        report += "  Input: \(formatQuat(belowApose))\n"

        if let offset = offsets[.leftUpperArm] {
            let result = simd_mul(belowApose, offset)
            report += "  leftUpperArm: input × offset = \(formatQuat(result))\n"
        }

        // Use XCTFail to make output visible in test results
        XCTFail("DIAGNOSTIC OUTPUT (not a real failure):\n\n\(report)")
    }
}
