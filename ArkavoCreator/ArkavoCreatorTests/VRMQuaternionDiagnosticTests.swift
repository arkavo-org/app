//
// VRMQuaternionDiagnosticTests.swift
// ArkavoCreatorTests
//
// Diagnostic tests to identify VRM quaternion conversion issues.
// These tests compare expected vs actual quaternion outputs for known poses.
//
// IMPORTANT: These tests are designed to FAIL to help diagnose
// what's wrong with the VRM rendering pipeline.
//

import XCTest
import simd
import ArkavoKit
import VRMMetalKit
@testable import ArkavoCreator

@MainActor
final class VRMQuaternionDiagnosticTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var recorder: VRMARecorder!

    override func setUp() {
        super.setUp()
        recorder = VRMARecorder(frameRate: 30)
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    // MARK: - T-Pose (Rest Pose) Tests

    /// T-pose with identity matrices should produce identity or near-identity quaternions
    /// for local rotations (when rest pose calibration is disabled).
    ///
    /// Note: This test uses synthetic identity matrices, not real ARKit data.
    /// Rest pose calibration is designed for real ARKit data, so we disable it here.
    func testTPoseProducesIdentityQuaternions() {
        // Disable rest pose calibration for this test
        // (rest pose calibration is for real ARKit data, not synthetic identity matrices)
        let originalSetting = ARKitCoordinateConverter.restPoseCalibrationEnabled
        ARKitCoordinateConverter.restPoseCalibrationEnabled = false
        defer { ARKitCoordinateConverter.restPoseCalibrationEnabled = originalSetting }

        // T-pose: all joints at identity (no rotation from parent)
        let tPoseSkeleton = makeTPoseSkeleton()

        var capturedRotations: [VRMHumanoidBone: simd_quatf] = [:]
        var capturedHipsTranslation: simd_float3?
        var inputJoints: [ARKitJoint: simd_float4x4] = [:]
        var callbackInvoked = false

        recorder.diagnosticsCallback = { joints, rotations, missing, fallback, hipsTranslation in
            callbackInvoked = true
            inputJoints = joints
            capturedRotations = rotations
            capturedHipsTranslation = hipsTranslation
        }

        // Verify skeleton has expected joints
        XCTAssertEqual(tPoseSkeleton.joints.count, 20, "T-pose skeleton should have 20 joints")

        recorder.startRecording()
        // Add small delay to pass rate limiting (minFrameInterval = 1/30 ≈ 0.033s)
        let timestamp = Date().addingTimeInterval(0.05)
        recorder.appendBodyFrame(body: tPoseSkeleton, timestamp: timestamp)
        _ = recorder.stopRecording()

        // Build diagnostic output
        var output = "\n=== T-POSE QUATERNION ANALYSIS ===\n"
        output += "Expected: All quaternions should be identity (0, 0, 0, 1) or very close\n"
        output += "Input joints count: \(inputJoints.count)\n"
        output += "Output rotations count: \(capturedRotations.count)\n\n"

        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        for bone in VRMHumanoidBone.allCases {
            guard let rotation = capturedRotations[bone] else { continue }

            let angleFromIdentity = angleBetween(rotation, identity)
            let isNearIdentity = angleFromIdentity < 5.0 // 5 degrees tolerance

            output += "\(bone.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)): " +
                  "(\(f(rotation.imag.x)), \(f(rotation.imag.y)), \(f(rotation.imag.z)), \(f(rotation.real))) " +
                  "angle=\(String(format: "%.1f°", angleFromIdentity)) " +
                  (isNearIdentity ? "✓" : "✗ UNEXPECTED") + "\n"
        }

        if let hips = capturedHipsTranslation {
            output += "\nHips translation: (\(f(hips.x)), \(f(hips.y)), \(f(hips.z)))\n"
        }

        // Print diagnostics in test output
        print(output)

        // Verify callback was invoked
        XCTAssertTrue(callbackInvoked, "Diagnostics callback was not invoked!")

        // First, verify we have rotations at all
        XCTAssertFalse(capturedRotations.isEmpty,
            "No rotations captured! Callback invoked: \(callbackInvoked). Input joints: \(inputJoints.count). Full output:\n\(output)")

        // Verify bones have expected rotations
        // - Hips: Gets world coordinate correction (ARKit → glTF), NOT identity
        // - Child bones: Local rotations should be identity for T-pose
        let childBones: [VRMHumanoidBone] = [.spine, .chest, .neck, .head,
                                              .leftShoulder, .rightShoulder,
                                              .leftUpperArm, .rightUpperArm]

        var allBoneInfo = ""
        for bone in [VRMHumanoidBone.hips] + childBones {
            if let rotation = capturedRotations[bone] {
                let angle = angleBetween(rotation, identity)
                allBoneInfo += "\(bone.rawValue): angle=\(String(format: "%.1f", angle))° quat=(\(f(rotation.imag.x)),\(f(rotation.imag.y)),\(f(rotation.imag.z)),\(f(rotation.real)))\n"
            } else {
                allBoneInfo += "\(bone.rawValue): MISSING\n"
            }
        }

        // Verify hips has coordinate correction applied (should be ~120° from identity)
        // This is the -90° X × -90° Y rotation that converts ARKit to glTF coordinates
        if let hipsRotation = capturedRotations[.hips] {
            let expectedHipsQuat = ARKitCoordinateConverter.rootRotationCorrection
            let angleFromExpected = angleBetween(hipsRotation, expectedHipsQuat)
            XCTAssertLessThan(angleFromExpected, 5.0,
                "hips should have coordinate correction applied. Got angle \(angleFromExpected)° from expected")
        } else {
            XCTFail("Missing rotation for hips")
        }

        // Verify child bones are near identity (local rotations in T-pose)
        for bone in childBones {
            guard let rotation = capturedRotations[bone] else {
                XCTFail("Missing rotation for \(bone.rawValue). Captured bones: \(capturedRotations.keys.map { $0.rawValue })")
                continue
            }
            let angle = angleBetween(rotation, identity)
            XCTAssertLessThan(angle, 10.0,
                "\(bone.rawValue) should be near identity in T-pose, but angle is \(angle)°. All bones:\n\(allBoneInfo)")
        }
    }

    // MARK: - Arm Rotation Tests

    /// Right arm raised 90° should produce specific shoulder/upper arm rotation
    func testRightArmRaised90Degrees() {
        // Create skeleton with right arm raised 90° (pointing up)
        let skeleton = makeSkeletonWithRightArmRaised()

        var capturedRotations: [VRMHumanoidBone: simd_quatf] = [:]

        recorder.diagnosticsCallback = { _, rotations, _, _, _ in
            capturedRotations = rotations
        }

        recorder.startRecording()
        recorder.appendBodyFrame(body: skeleton, timestamp: Date().addingTimeInterval(0.05))
        _ = recorder.stopRecording()

        print("\n=== RIGHT ARM RAISED 90° ANALYSIS ===")
        print("Expected: rightUpperArm should have ~90° rotation around Z axis (in VRM space)")
        print("")

        let armBones: [VRMHumanoidBone] = [.rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand]

        for bone in armBones {
            guard let rotation = capturedRotations[bone] else {
                print("\(bone.rawValue): NOT CAPTURED")
                continue
            }

            let euler = quaternionToEuler(rotation)
            print("\(bone.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)): " +
                  "quat=(\(f(rotation.imag.x)), \(f(rotation.imag.y)), \(f(rotation.imag.z)), \(f(rotation.real))) " +
                  "euler=(x:\(String(format: "%.1f°", euler.x)), y:\(String(format: "%.1f°", euler.y)), z:\(String(format: "%.1f°", euler.z)))")
        }

        // The right upper arm should have rotation around Z (or the axis that raises it)
        if let rightUpperArm = capturedRotations[.rightUpperArm] {
            let euler = quaternionToEuler(rightUpperArm)
            // In VRM, raising right arm should be rotation around Z axis (frontal plane)
            let hasSignificantRotation = abs(euler.x) > 45 || abs(euler.y) > 45 || abs(euler.z) > 45
            XCTAssertTrue(hasSignificantRotation,
                "rightUpperArm should have significant rotation when raised, got euler: \(euler)")
        }
    }

    /// Left arm raised 90° should mirror right arm
    func testLeftArmRaised90Degrees() {
        let skeleton = makeSkeletonWithLeftArmRaised()

        var capturedRotations: [VRMHumanoidBone: simd_quatf] = [:]

        recorder.diagnosticsCallback = { _, rotations, _, _, _ in
            capturedRotations = rotations
        }

        recorder.startRecording()
        recorder.appendBodyFrame(body: skeleton, timestamp: Date().addingTimeInterval(0.05))
        _ = recorder.stopRecording()

        print("\n=== LEFT ARM RAISED 90° ANALYSIS ===")

        let armBones: [VRMHumanoidBone] = [.leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand]

        for bone in armBones {
            guard let rotation = capturedRotations[bone] else {
                print("\(bone.rawValue): NOT CAPTURED")
                continue
            }

            let euler = quaternionToEuler(rotation)
            print("\(bone.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)): " +
                  "quat=(\(f(rotation.imag.x)), \(f(rotation.imag.y)), \(f(rotation.imag.z)), \(f(rotation.real))) " +
                  "euler=(x:\(String(format: "%.1f°", euler.x)), y:\(String(format: "%.1f°", euler.y)), z:\(String(format: "%.1f°", euler.z)))")
        }
    }

    // MARK: - Head Rotation Tests

    /// Head turned right 45° should produce neck/head rotation around Y axis
    func testHeadTurnedRight45Degrees() {
        let skeleton = makeSkeletonWithHeadTurned(yawDegrees: 45)

        var capturedRotations: [VRMHumanoidBone: simd_quatf] = [:]

        recorder.diagnosticsCallback = { _, rotations, _, _, _ in
            capturedRotations = rotations
        }

        recorder.startRecording()
        recorder.appendBodyFrame(body: skeleton, timestamp: Date().addingTimeInterval(0.05))
        _ = recorder.stopRecording()

        print("\n=== HEAD TURNED RIGHT 45° ANALYSIS ===")
        print("Expected: head/neck should have ~45° rotation around Y axis")
        print("")

        let headBones: [VRMHumanoidBone] = [.neck, .head]

        for bone in headBones {
            guard let rotation = capturedRotations[bone] else {
                print("\(bone.rawValue): NOT CAPTURED")
                continue
            }

            let euler = quaternionToEuler(rotation)
            print("\(bone.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)): " +
                  "quat=(\(f(rotation.imag.x)), \(f(rotation.imag.y)), \(f(rotation.imag.z)), \(f(rotation.real))) " +
                  "euler=(x:\(String(format: "%.1f°", euler.x)), y:\(String(format: "%.1f°", euler.y)), z:\(String(format: "%.1f°", euler.z)))")
        }

        // Head should have Y rotation around 45 degrees
        if let head = capturedRotations[.head] {
            let euler = quaternionToEuler(head)
            // Y axis is yaw in VRM
            XCTAssertTrue(abs(euler.y) > 20,
                "Head should have significant Y rotation for yaw, got: \(euler.y)°")
        }
    }

    // MARK: - Coordinate System Tests

    /// Test the ARKit to VRM coordinate conversion formula
    func testCoordinateSystemConversion() {
        print("\n=== COORDINATE SYSTEM CONVERSION ANALYSIS ===")
        print("ARKit: Y-up, right-handed, camera faces -Z")
        print("VRM/glTF: Y-up, right-handed, forward is +Z")
        print("")

        // Test rotation around each axis
        let testAngles: [(axis: String, quat: simd_quatf)] = [
            ("X +90°", simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1, 0, 0))),
            ("X -90°", simd_quatf(angle: -.pi/2, axis: SIMD3<Float>(1, 0, 0))),
            ("Y +90°", simd_quatf(angle: .pi/2, axis: SIMD3<Float>(0, 1, 0))),
            ("Y -90°", simd_quatf(angle: -.pi/2, axis: SIMD3<Float>(0, 1, 0))),
            ("Z +90°", simd_quatf(angle: .pi/2, axis: SIMD3<Float>(0, 0, 1))),
            ("Z -90°", simd_quatf(angle: -.pi/2, axis: SIMD3<Float>(0, 0, 1))),
        ]

        print("Input (ARKit) -> Output (VRM) conversion:")
        print("Current formula: (x, y, z, w) -> (-x, -y, z, w)")
        print("")

        for (axis, inputQuat) in testAngles {
            // Apply current conversion: negate X and Y
            let outputQuat = simd_quatf(
                ix: -inputQuat.imag.x,
                iy: -inputQuat.imag.y,
                iz: inputQuat.imag.z,
                r: inputQuat.real
            )

            let inputEuler = quaternionToEuler(inputQuat)
            let outputEuler = quaternionToEuler(outputQuat)

            print("\(axis.padding(toLength: 8, withPad: " ", startingAt: 0)): " +
                  "in=(\(f(inputQuat.imag.x)), \(f(inputQuat.imag.y)), \(f(inputQuat.imag.z)), \(f(inputQuat.real))) " +
                  "-> out=(\(f(outputQuat.imag.x)), \(f(outputQuat.imag.y)), \(f(outputQuat.imag.z)), \(f(outputQuat.real)))")
            print("         euler: in=(x:\(String(format: "%.0f", inputEuler.x))°, y:\(String(format: "%.0f", inputEuler.y))°, z:\(String(format: "%.0f", inputEuler.z))°) " +
                  "-> out=(x:\(String(format: "%.0f", outputEuler.x))°, y:\(String(format: "%.0f", outputEuler.y))°, z:\(String(format: "%.0f", outputEuler.z))°)")
        }

        // This test is informational - check output manually
        XCTAssertTrue(true, "Check output above to verify coordinate conversion is correct")
    }

    // MARK: - Parent-Child Relationship Tests

    /// Test that local rotations are computed correctly from world transforms
    func testLocalRotationComputation() {
        print("\n=== LOCAL ROTATION COMPUTATION ANALYSIS ===")
        print("Testing: localRot = inverse(parentWorldRot) * childWorldRot")
        print("")

        // Parent at identity, child rotated 45° around Y
        let parentWorld = simd_float4x4(1) // identity
        let childWorld = makeRotationMatrix(angle: .pi/4, axis: SIMD3<Float>(0, 1, 0))

        let parentRot = extractRotation(from: parentWorld)
        let childRot = extractRotation(from: childWorld)
        let localRot = simd_mul(simd_inverse(parentRot), childRot)

        print("Parent world rotation: identity")
        print("Child world rotation: 45° around Y")
        print("Computed local rotation: (\(f(localRot.imag.x)), \(f(localRot.imag.y)), \(f(localRot.imag.z)), \(f(localRot.real)))")

        let localEuler = quaternionToEuler(localRot)
        print("Local euler: (x:\(String(format: "%.1f", localEuler.x))°, y:\(String(format: "%.1f", localEuler.y))°, z:\(String(format: "%.1f", localEuler.z))°)")

        // Local should be same as child when parent is identity
        XCTAssertEqual(localEuler.y, 45, accuracy: 1.0, "Local Y rotation should be 45°")

        // Now test with rotated parent
        print("\n--- With rotated parent ---")
        let parentWorld2 = makeRotationMatrix(angle: .pi/4, axis: SIMD3<Float>(0, 1, 0)) // 45° Y
        let childWorld2 = makeRotationMatrix(angle: .pi/2, axis: SIMD3<Float>(0, 1, 0))  // 90° Y

        let parentRot2 = extractRotation(from: parentWorld2)
        let childRot2 = extractRotation(from: childWorld2)
        let localRot2 = simd_mul(simd_inverse(parentRot2), childRot2)

        let localEuler2 = quaternionToEuler(localRot2)
        print("Parent: 45° Y, Child: 90° Y")
        print("Local should be: 45° Y")
        print("Computed local: (x:\(String(format: "%.1f", localEuler2.x))°, y:\(String(format: "%.1f", localEuler2.y))°, z:\(String(format: "%.1f", localEuler2.z))°)")

        XCTAssertEqual(localEuler2.y, 45, accuracy: 1.0, "Local Y rotation should be 45°")
    }

    // MARK: - Skeleton Builders

    private func makeTPoseSkeleton() -> ARKitBodySkeleton {
        // T-pose: arms out to sides (horizontal), standing straight
        //
        // IMPORTANT: ARKit's reference pose is A-pose (arms ~35° below horizontal).
        // To simulate T-pose in ARKit, arms must be rotated UP from the A-pose reference.
        // - Left arm: +35° around Z (raise from A-pose to T-pose)
        // - Right arm: -35° around Z (mirrored)
        //
        var joints: [ARKitJoint: simd_float4x4] = [:]

        let identity = simd_float4x4(1)

        // A-pose to T-pose offset: arms raised 35° from A-pose reference
        let armAngle: Float = 35 * .pi / 180
        let leftArmTPose = makeRotationMatrix(angle: armAngle, axis: SIMD3<Float>(0, 0, 1))
        let rightArmTPose = makeRotationMatrix(angle: -armAngle, axis: SIMD3<Float>(0, 0, 1))

        joints[.hips] = identity
        joints[.spine] = identity
        joints[.chest] = identity
        joints[.upperChest] = identity
        joints[.neck] = identity
        joints[.head] = identity
        joints[.leftShoulder] = identity
        joints[.leftUpperArm] = leftArmTPose    // Raised to T-pose
        joints[.leftLowerArm] = leftArmTPose    // Follows upper arm
        joints[.leftHand] = leftArmTPose
        joints[.rightShoulder] = identity
        joints[.rightUpperArm] = rightArmTPose  // Raised to T-pose
        joints[.rightLowerArm] = rightArmTPose  // Follows upper arm
        joints[.rightHand] = rightArmTPose
        joints[.leftUpperLeg] = identity
        joints[.leftLowerLeg] = identity
        joints[.leftFoot] = identity
        joints[.rightUpperLeg] = identity
        joints[.rightLowerLeg] = identity
        joints[.rightFoot] = identity

        return ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
    }

    private func makeSkeletonWithRightArmRaised() -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]

        let identity = simd_float4x4(1)

        // Body at identity
        joints[.hips] = identity
        joints[.spine] = identity
        joints[.chest] = identity
        joints[.upperChest] = identity
        joints[.neck] = identity
        joints[.head] = identity

        // Left arm at identity (T-pose)
        joints[.leftShoulder] = identity
        joints[.leftUpperArm] = identity
        joints[.leftLowerArm] = identity
        joints[.leftHand] = identity

        // Right arm raised 90° (rotation around Z in ARKit = frontal plane)
        // In ARKit, +Z rotation raises the right arm
        joints[.rightShoulder] = identity
        joints[.rightUpperArm] = makeRotationMatrix(angle: .pi/2, axis: SIMD3<Float>(0, 0, 1))
        joints[.rightLowerArm] = makeRotationMatrix(angle: .pi/2, axis: SIMD3<Float>(0, 0, 1))
        joints[.rightHand] = makeRotationMatrix(angle: .pi/2, axis: SIMD3<Float>(0, 0, 1))

        // Legs at identity
        joints[.leftUpperLeg] = identity
        joints[.leftLowerLeg] = identity
        joints[.leftFoot] = identity
        joints[.rightUpperLeg] = identity
        joints[.rightLowerLeg] = identity
        joints[.rightFoot] = identity

        return ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
    }

    private func makeSkeletonWithLeftArmRaised() -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]

        let identity = simd_float4x4(1)

        joints[.hips] = identity
        joints[.spine] = identity
        joints[.chest] = identity
        joints[.upperChest] = identity
        joints[.neck] = identity
        joints[.head] = identity

        // Left arm raised 90° (negative Z rotation in ARKit)
        joints[.leftShoulder] = identity
        joints[.leftUpperArm] = makeRotationMatrix(angle: -.pi/2, axis: SIMD3<Float>(0, 0, 1))
        joints[.leftLowerArm] = makeRotationMatrix(angle: -.pi/2, axis: SIMD3<Float>(0, 0, 1))
        joints[.leftHand] = makeRotationMatrix(angle: -.pi/2, axis: SIMD3<Float>(0, 0, 1))

        // Right arm at identity
        joints[.rightShoulder] = identity
        joints[.rightUpperArm] = identity
        joints[.rightLowerArm] = identity
        joints[.rightHand] = identity

        joints[.leftUpperLeg] = identity
        joints[.leftLowerLeg] = identity
        joints[.leftFoot] = identity
        joints[.rightUpperLeg] = identity
        joints[.rightLowerLeg] = identity
        joints[.rightFoot] = identity

        return ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
    }

    private func makeSkeletonWithHeadTurned(yawDegrees: Float) -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]

        let identity = simd_float4x4(1)
        let headRotation = makeRotationMatrix(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))

        joints[.hips] = identity
        joints[.spine] = identity
        joints[.chest] = identity
        joints[.upperChest] = identity
        joints[.neck] = identity
        joints[.head] = headRotation

        joints[.leftShoulder] = identity
        joints[.leftUpperArm] = identity
        joints[.leftLowerArm] = identity
        joints[.leftHand] = identity
        joints[.rightShoulder] = identity
        joints[.rightUpperArm] = identity
        joints[.rightLowerArm] = identity
        joints[.rightHand] = identity
        joints[.leftUpperLeg] = identity
        joints[.leftLowerLeg] = identity
        joints[.leftFoot] = identity
        joints[.rightUpperLeg] = identity
        joints[.rightLowerLeg] = identity
        joints[.rightFoot] = identity

        return ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
    }

    // MARK: - Math Helpers

    private func makeRotationMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let quat = simd_quatf(angle: angle, axis: normalize(axis))
        return simd_float4x4(quat)
    }

    private func extractRotation(from matrix: simd_float4x4) -> simd_quatf {
        // Extract 3x3 rotation matrix
        let col0 = SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let col1 = SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let col2 = SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)

        let rotMatrix = simd_float3x3(col0, col1, col2)
        return simd_quatf(rotMatrix)
    }

    private func angleBetween(_ q1: simd_quatf, _ q2: simd_quatf) -> Float {
        let dot = abs(simd_dot(q1, q2))
        let clampedDot = min(1.0, dot)
        return 2.0 * acos(clampedDot) * 180.0 / .pi
    }

    private func quaternionToEuler(_ q: simd_quatf) -> (x: Float, y: Float, z: Float) {
        // Convert quaternion to Euler angles (in degrees)
        let x = q.imag.x
        let y = q.imag.y
        let z = q.imag.z
        let w = q.real

        // Roll (X)
        let sinr_cosp = 2.0 * (w * x + y * z)
        let cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
        let roll = atan2(sinr_cosp, cosr_cosp)

        // Pitch (Y)
        let sinp = 2.0 * (w * y - z * x)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }

        // Yaw (Z)
        let siny_cosp = 2.0 * (w * z + x * y)
        let cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        let yaw = atan2(siny_cosp, cosy_cosp)

        return (roll * 180 / .pi, pitch * 180 / .pi, yaw * 180 / .pi)
    }

    private func f(_ value: Float) -> String {
        String(format: "%6.3f", value)
    }
}
