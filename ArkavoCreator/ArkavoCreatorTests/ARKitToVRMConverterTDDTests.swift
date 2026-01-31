//
//  ARKitToVRMConverterTDDTests.swift
//  ArkavoCreatorTests
//
//  TDD test suite for ARKitToVRMConverter.
//  Following TDD cycle: RED → GREEN → REFACTOR
//

import XCTest
import simd
import VRMMetalKit
@testable import ArkavoCreator

/// TDD Test Suite for ARKitToVRMConverter
/// 
/// These tests define the expected behavior of the coordinate conversion.
/// Each test follows AAA pattern: Arrange, Act, Assert
@MainActor
final class ARKitToVRMConverterTDDTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    /// Create a rotation matrix from axis-angle
    private func rotationMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        return simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }
    
    /// Create identity skeleton with all joints at rest
    private func createIdentitySkeleton() -> ARKitBodySkeleton {
        var joints: [ARKitJoint: simd_float4x4] = [:]
        let identity = simd_float4x4(1)
        
        let allJoints: [ARKitJoint] = [
            .hips, .spine, .chest, .upperChest, .neck, .head,
            .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
            .rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand,
            .leftUpperLeg, .leftLowerLeg, .leftFoot, .leftToes,
            .rightUpperLeg, .rightLowerLeg, .rightFoot, .rightToes
        ]
        
        for joint in allJoints {
            joints[joint] = identity
        }
        
        return ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
    }
    
    /// Check if quaternion is approximately identity
    private func isNearIdentity(_ q: simd_quatf, tolerance: Float = 0.01) -> Bool {
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let diff = abs(q.real - identity.real) + simd_length(q.imag - identity.imag)
        return diff < tolerance
    }
    
    /// Get angle in degrees from quaternion
    private func angleDegrees(_ q: simd_quatf) -> Float {
        let angle = 2 * acos(min(abs(q.real), 1.0))
        return angle * 180.0 / .pi
    }
    
    // MARK: - RED Phase Tests (These will initially fail)
    
    // ====================
    // HAPPY PATH TESTS
    // ====================
    
    /// TEST 1: Identity skeleton should produce valid rotations
    /// 
    /// Given: All joints at identity matrices
    /// When: Converting to VRM
    /// Then: All bones should have valid (non-nil) rotations
    func test_identitySkeleton_producesValidRotations() {
        // Arrange
        let skeleton = createIdentitySkeleton()
        
        // Act
        let rotations = ARKitToVRMConverter.convert(skeleton: skeleton)
        
        // Assert
        XCTAssertFalse(rotations.isEmpty, "Should produce at least one rotation")
        XCTAssertNotNil(rotations[.hips], "Hips should be mapped")
        XCTAssertNotNil(rotations[.head], "Head should be mapped")
        XCTAssertNotNil(rotations[.leftUpperArm], "Left arm should be mapped")
        XCTAssertNotNil(rotations[.rightUpperArm], "Right arm should be mapped")
    }
    
    /// TEST 2: Hips rotation should apply root correction
    /// 
    /// Given: Hips at identity (standing straight, facing -Z in ARKit)
    /// When: Converting to VRM
    /// Then: Hips should have 180° Y rotation (to face +Z in VRM)
    func test_hipsIdentity_appliesRootCorrection() {
        // Arrange
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)  // Identity
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        guard let hipsRot = ARKitToVRMConverter.computeVRMRotation(
            joint: .hips,
            childTransform: joints[.hips]!,
            skeleton: skeleton
        ) else {
            XCTFail("Should compute hips rotation")
            return
        }
        
        // Assert
        // Root correction should rotate 180° around Y
        let expectedCorrection = ARKitToVRMConverter.rootRotationCorrection
        XCTAssertEqual(angleDegrees(hipsRot), angleDegrees(expectedCorrection), accuracy: 1.0,
                      "Hips should have 180° Y rotation (root correction)")
    }
    
    /// TEST 3: Spine rotation should be local (relative to parent)
    /// 
    /// Given: Spine bent 30° forward (around X axis)
    /// When: Converting to VRM
    /// Then: Spine rotation should be approximately 30° around X
    func test_spineBend_producesLocalRotation() {
        // Arrange
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = rotationMatrix(angle: .pi / 6, axis: SIMD3<Float>(1, 0, 0))  // 30° forward bend
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        guard let spineRot = ARKitToVRMConverter.computeVRMRotation(
            joint: .spine,
            childTransform: joints[.spine]!,
            skeleton: skeleton
        ) else {
            XCTFail("Should compute spine rotation")
            return
        }
        
        // Assert
        let angle = angleDegrees(spineRot)
        XCTAssertEqual(angle, 30.0, accuracy: 5.0,
                      "Spine should have ~30° rotation (forward bend)")
        
        // Should primarily be around X axis (forward/back)
        let axis = normalize(spineRot.imag)
        XCTAssertGreaterThan(abs(axis.x), 0.8,
                            "Spine rotation axis should be primarily X (forward/back)")
    }
    
    /// TEST 4: Arm raise should rotate around correct axis
    /// 
    /// Given: Left arm raised 90° (around Z in ARKit)
    /// When: Converting to VRM
    /// Then: Left arm should rotate ~90° with correct axis
    func test_leftArmRaise_producesCorrectRotation() {
        // Arrange
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)
        joints[.leftShoulder] = simd_float4x4(1)
        joints[.leftUpperArm] = rotationMatrix(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))  // 90° raise
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        guard let armRot = ARKitToVRMConverter.computeVRMRotation(
            joint: .leftUpperArm,
            childTransform: joints[.leftUpperArm]!,
            skeleton: skeleton
        ) else {
            XCTFail("Should compute arm rotation")
            return
        }
        
        // Assert
        let angle = angleDegrees(armRot)
        XCTAssertEqual(angle, 90.0, accuracy: 5.0,
                      "Left arm should have ~90° rotation")
    }
    
    /// TEST 5: Hips translation converts correctly
    /// 
    /// Given: Hips at position (1, 2, -3) in ARKit space
    /// When: Converting translation
    /// Then: Result should be (1, 2, 3) - Z flipped for VRM
    func test_hipsTranslation_flipsZAxis() {
        // Arrange
        var transform = simd_float4x4(1)
        transform.columns.3 = SIMD4<Float>(1, 2, -3, 1)  // Position (1, 2, -3)
        
        // Act
        let translation = ARKitToVRMConverter.convertHipsTranslation(from: transform)
        
        // Assert
        XCTAssertEqual(translation.x, 1.0, accuracy: 0.001, "X should stay same")
        XCTAssertEqual(translation.y, 2.0, accuracy: 0.001, "Y should stay same")
        XCTAssertEqual(translation.z, 3.0, accuracy: 0.001, "Z should be flipped (sign reversed)")
    }
    
    /// TEST 6: Full skeleton conversion produces all expected bones
    /// 
    /// Given: Complete skeleton with all joints
    /// When: Converting entire skeleton
    /// Then: Should produce rotations for all VRM humanoid bones
    func test_fullSkeleton_producesAllBones() {
        // Arrange
        let skeleton = createIdentitySkeleton()
        
        // Act
        let rotations = ARKitToVRMConverter.convert(skeleton: skeleton)
        
        // Assert - Should have all major bones
        let expectedBones: [VRMHumanoidBone] = [
            .hips, .spine, .chest, .upperChest, .neck, .head,
            .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
            .rightShoulder, .rightUpperArm, .rightLowerArm, .rightHand,
            .leftUpperLeg, .leftLowerLeg, .leftFoot,
            .rightUpperLeg, .rightLowerLeg, .rightFoot
        ]
        
        for bone in expectedBones {
            XCTAssertNotNil(rotations[bone], "Should have rotation for \(bone)")
        }
    }
    
    // ====================
    // EDGE CASE TESTS
    // ====================
    
    /// TEST 7: Missing parent joint returns nil
    /// 
    /// Given: Joint without parent in skeleton
    /// When: Computing rotation
    /// Then: Should return nil (can't compute local rotation)
    func test_missingParent_returnsNil() {
        // Arrange - spine without hips parent
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.spine] = simd_float4x4(1)
        // Note: hips is NOT in joints, so spine has no parent
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        let rotation = ARKitToVRMConverter.computeVRMRotation(
            joint: .spine,
            childTransform: joints[.spine]!,
            skeleton: skeleton
        )
        
        // Assert
        XCTAssertNil(rotation, "Should return nil when parent is missing")
    }
    
    /// TEST 8: Empty skeleton produces empty rotations
    /// 
    /// Given: Skeleton with no joints
    /// When: Converting
    /// Then: Should return empty dictionary
    func test_emptySkeleton_producesEmptyRotations() {
        // Arrange
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: [:],
            isTracked: false,
            confidence: nil
        )
        
        // Act
        let rotations = ARKitToVRMConverter.convert(skeleton: skeleton)
        
        // Assert
        XCTAssertTrue(rotations.isEmpty, "Empty skeleton should produce empty rotations")
    }
    
    /// TEST 9: Partial skeleton (only upper body)
    /// 
    /// Given: Skeleton with only upper body joints
    /// When: Converting
    /// Then: Should produce rotations for available joints only
    func test_partialSkeleton_producesPartialRotations() {
        // Arrange - only upper body with complete parent chains
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)
        joints[.leftShoulder] = simd_float4x4(1)
        joints[.rightShoulder] = simd_float4x4(1)
        joints[.leftUpperArm] = simd_float4x4(1)
        joints[.rightUpperArm] = simd_float4x4(1)
        // No legs
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        let rotations = ARKitToVRMConverter.convert(skeleton: skeleton)
        
        // Assert - upper body should work
        XCTAssertNotNil(rotations[.hips], "Hips should have rotation")
        XCTAssertNotNil(rotations[.leftUpperArm], "Left arm should have rotation (with complete chain)")
        XCTAssertNotNil(rotations[.rightUpperArm], "Right arm should have rotation (with complete chain)")
        
        // Missing legs should not have rotations
        XCTAssertNil(rotations[.leftUpperLeg], "Missing leg should not have rotation")
        XCTAssertNil(rotations[.rightUpperLeg], "Missing leg should not have rotation")
    }
    
    /// TEST 10: Quaternion normalization
    /// 
    /// Given: Rotation resulting in non-unit quaternion
    /// When: Converting
    /// Then: Result should be normalized (unit length)
    func test_outputIsNormalized() {
        // Arrange
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        guard let rotation = ARKitToVRMConverter.computeVRMRotation(
            joint: .hips,
            childTransform: joints[.hips]!,
            skeleton: skeleton
        ) else {
            XCTFail("Should compute rotation")
            return
        }
        
        // Assert - quaternion should be unit length
        let length = sqrt(
            rotation.imag.x * rotation.imag.x +
            rotation.imag.y * rotation.imag.y +
            rotation.imag.z * rotation.imag.z +
            rotation.real * rotation.real
        )
        XCTAssertEqual(length, 1.0, accuracy: 0.001,
                      "Output quaternion should be normalized (unit length)")
    }
    
    // ====================
    // LEFT/RIGHT SYMMETRY
    // ====================
    
    /// TEST 11: Left and right arms produce mirrored results
    /// 
    /// Given: Left and right arms with same rotation
    /// When: Converting both
    /// Then: Results should be mirror images
    func test_leftRightSymmetry() {
        // Arrange
        let armRotation = rotationMatrix(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1))
        
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = simd_float4x4(1)
        joints[.chest] = simd_float4x4(1)
        joints[.upperChest] = simd_float4x4(1)
        joints[.leftShoulder] = simd_float4x4(1)
        joints[.rightShoulder] = simd_float4x4(1)
        joints[.leftUpperArm] = armRotation
        joints[.rightUpperArm] = armRotation
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        guard let leftRot = ARKitToVRMConverter.computeVRMRotation(
            joint: .leftUpperArm,
            childTransform: joints[.leftUpperArm]!,
            skeleton: skeleton
        ), let rightRot = ARKitToVRMConverter.computeVRMRotation(
            joint: .rightUpperArm,
            childTransform: joints[.rightUpperArm]!,
            skeleton: skeleton
        ) else {
            XCTFail("Should compute both rotations")
            return
        }
        
        // Assert - angles should be equal
        XCTAssertEqual(angleDegrees(leftRot), angleDegrees(rightRot), accuracy: 1.0,
                      "Left and right should have same angle magnitude")
    }
    
    // ====================
    // DIAGNOSTICS TESTS
    // ====================
    
    /// TEST 12: Diagnostics callback reports unmapped joints
    /// 
    /// Given: Skeleton with some joints missing
    /// When: Converting with diagnostics
    /// Then: Callback should be called for unmapped joints
    func test_diagnostics_reportsUnmappedJoints() {
        // Arrange
        var joints: [ARKitJoint: simd_float4x4] = [:]
        joints[.hips] = simd_float4x4(1)
        joints[.spine] = simd_float4x4(1)
        // leftUpperArm missing parent (leftShoulder)
        joints[.leftUpperArm] = simd_float4x4(1)
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        var unmappedJoints: [ARKitJoint] = []
        
        // Act
        _ = ARKitToVRMConverter.convertWithDiagnostics(
            skeleton: skeleton,
            onUnmappedJoint: { joint in
                unmappedJoints.append(joint)
            }
        )
        
        // Assert
        XCTAssertTrue(unmappedJoints.contains(.leftUpperArm),
                     "Should report leftUpperArm as unmapped (missing parent)")
    }
    
    /// TEST 13: Full diagnostics provides hips translation
    /// 
    /// Given: Skeleton with hips
    /// When: Converting with diagnostics
    /// Then: Should return hips translation
    func test_diagnostics_providesHipsTranslation() {
        // Arrange
        var joints: [ARKitJoint: simd_float4x4] = [:]
        var hipsTransform = simd_float4x4(1)
        hipsTransform.columns.3 = SIMD4<Float>(0.5, 1.0, -0.5, 1)
        joints[.hips] = hipsTransform
        
        let skeleton = ARKitBodySkeleton(
            timestamp: Date().timeIntervalSinceReferenceDate,
            joints: joints,
            isTracked: true,
            confidence: nil
        )
        
        // Act
        let (_, hipsTranslation) = ARKitToVRMConverter.convertWithDiagnostics(
            skeleton: skeleton,
            onUnmappedJoint: nil
        )
        
        // Assert
        XCTAssertNotNil(hipsTranslation)
        XCTAssertEqual(Double(hipsTranslation!.x), 0.5, accuracy: 0.001)
        XCTAssertEqual(Double(hipsTranslation!.y), 1.0, accuracy: 0.001)
        XCTAssertEqual(Double(hipsTranslation!.z), 0.5, accuracy: 0.001)  // Z flipped
    }
}

// MARK: - Test Extensions

extension simd_quatf {
    /// For debugging: description of quaternion
    var debugDescription: String {
        return String(format: "[w: %.3f, x: %.3f, y: %.3f, z: %.3f]",
                      real, imag.x, imag.y, imag.z)
    }
}
