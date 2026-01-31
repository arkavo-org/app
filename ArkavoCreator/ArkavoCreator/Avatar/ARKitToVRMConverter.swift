//
//  ARKitToVRMConverter.swift
//  ArkavoCreator
//
//  Converts ARKit body tracking data to VRM humanoid bone rotations.
//
//  This converter bridges ARKit's skeleton representation (from ARBodyTracking)
//  to VRM's humanoid bone system. It handles:
//  - Coordinate system conversion (ARKit → glTF/VRM)
//  - Local rotation computation from model-space transforms
//  - Joint name mapping
//  - Left/right side mirroring for symmetrical poses
//

import Foundation
import simd
import VRMMetalKit

/// Converts ARKit skeleton data to VRM humanoid bone rotations
enum ARKitToVRMConverter {
    
    // MARK: - Types
    
    /// Errors during conversion
    enum ConversionError: Error {
        case invalidTransform
        case missingParent(ARKitJoint)
        case unsupportedJoint
    }
    
    // MARK: - Configuration
    
    /// Whether to apply rest pose calibration (subtract T-pose offset)
    @MainActor
    static var restPoseCalibrationEnabled: Bool = false
    
    /// Current calibration state
    @MainActor
    static private(set) var isCalibrated: Bool = false
    
    /// Calibration offsets for each joint (T-pose reference)
    @MainActor
    static private var calibrationOffsets: [ARKitJoint: simd_quatf] = [:]
    
    /// Root rotation correction: ARKit faces -Z, VRM faces +Z
    /// Both are Y-up right-handed, so we only need 180° Y rotation
    static let rootRotationCorrection: simd_quatf = {
        // 180° rotation around Y axis flips forward from -Z to +Z
        simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
    }()
    
    // MARK: - Joint Hierarchy
    
    /// ARKit skeleton parent-child relationships
    /// Used to compute local rotations from model-space transforms
    static let arkitParentMap: [ARKitJoint: ARKitJoint] = [
        // Spine chain
        .spine: .hips,
        .chest: .spine,
        .upperChest: .chest,
        .neck: .upperChest,
        .head: .neck,
        
        // Left arm
        .leftShoulder: .upperChest,
        .leftUpperArm: .leftShoulder,
        .leftLowerArm: .leftUpperArm,
        .leftHand: .leftLowerArm,
        
        // Right arm
        .rightShoulder: .upperChest,
        .rightUpperArm: .rightShoulder,
        .rightLowerArm: .rightUpperArm,
        .rightHand: .rightLowerArm,
        
        // Left leg
        .leftUpperLeg: .hips,
        .leftLowerLeg: .leftUpperLeg,
        .leftFoot: .leftLowerLeg,
        .leftToes: .leftFoot,
        
        // Right leg
        .rightUpperLeg: .hips,
        .rightLowerLeg: .rightUpperLeg,
        .rightFoot: .rightLowerLeg,
        .rightToes: .rightFoot
    ]
    
    /// ARKit joint to VRM humanoid bone mapping
    static let jointToBoneMap: [ARKitJoint: VRMHumanoidBone] = [
        // Core
        .hips: .hips,
        .spine: .spine,
        .chest: .chest,
        .upperChest: .upperChest,
        .neck: .neck,
        .head: .head,
        
        // Arms
        .leftShoulder: .leftShoulder,
        .leftUpperArm: .leftUpperArm,
        .leftLowerArm: .leftLowerArm,
        .leftHand: .leftHand,
        .rightShoulder: .rightShoulder,
        .rightUpperArm: .rightUpperArm,
        .rightLowerArm: .rightLowerArm,
        .rightHand: .rightHand,
        
        // Legs
        .leftUpperLeg: .leftUpperLeg,
        .leftLowerLeg: .leftLowerLeg,
        .leftFoot: .leftFoot,
        .leftToes: .leftToes,
        .rightUpperLeg: .rightUpperLeg,
        .rightLowerLeg: .rightLowerLeg,
        .rightFoot: .rightFoot,
        .rightToes: .rightToes
    ]
    
    // MARK: - Main Conversion API
    
    /// Convert ARKit skeleton to VRM bone rotations
    /// - Parameter skeleton: ARKit body skeleton with model-space joint transforms
    /// - Returns: Dictionary mapping VRM bones to local rotations
    @MainActor
    static func convert(skeleton: ARKitBodySkeleton) -> [VRMHumanoidBone: simd_quatf] {
        var rotations: [VRMHumanoidBone: simd_quatf] = [:]
        
        for (arkitJoint, vrmBone) in jointToBoneMap {
            guard let transform = skeleton.joints[arkitJoint] else { continue }
            
            if let rotation = computeVRMRotation(
                joint: arkitJoint,
                childTransform: transform,
                skeleton: skeleton
            ) {
                rotations[vrmBone] = rotation
            }
        }
        
        return rotations
    }
    
    /// Compute VRM rotation for a specific joint
    /// - Parameters:
    ///   - joint: The ARKit joint to convert
    ///   - childTransform: Model-space transform of the joint
    ///   - skeleton: Full skeleton for parent lookup
    /// - Returns: Local rotation in VRM coordinate space, or nil if parent is missing
    @MainActor
    static func computeVRMRotation(
        joint: ARKitJoint,
        childTransform: simd_float4x4,
        skeleton: ARKitBodySkeleton
    ) -> simd_quatf? {
        // Extract rotation from transform matrix
        let childWorldRot = extractRotation(from: childTransform)
        
        // Check if this joint has a parent defined in the hierarchy
        if let parentJoint = arkitParentMap[joint] {
            // Has a parent - parent MUST be present in skeleton
            guard let parentTransform = skeleton.joints[parentJoint] else {
                return nil  // Parent missing - can't compute local rotation
            }
            let parentWorldRot = extractRotation(from: parentTransform)
            // localRot = inverse(parentWorld) * childWorld
            let localRot = simd_mul(simd_inverse(parentWorldRot), childWorldRot)
            return convertLocalRotation(localRot, joint: joint)
        } else {
            // No parent (hips/root) - apply root correction only
            return convertLocalRotation(childWorldRot, joint: joint)
        }
    }
    
    /// Convert hips translation from ARKit to VRM space
    /// - Parameter transform: Hips model-space transform
    /// - Returns: Translation in VRM coordinate space
    static func convertHipsTranslation(from transform: simd_float4x4) -> simd_float3 {
        // ARKit and VRM are both Y-up, but facing opposite directions
        // We only need to negate Z to flip from -Z to +Z forward
        return simd_float3(
            transform.columns.3.x,
            transform.columns.3.y,
            -transform.columns.3.z  // Flip Z for forward direction
        )
    }
    
    // MARK: - Rotation Processing
    
    /// Convert a local rotation from ARKit to VRM conventions
    /// - Parameters:
    ///   - rotation: Local rotation in ARKit space
    ///   - joint: The joint being converted (for side-specific handling)
    /// - Returns: Rotation in VRM space
    @MainActor
    static func convertLocalRotation(_ rotation: simd_quatf, joint: ARKitJoint) -> simd_quatf {
        var result = rotation
        
        // Normalize to positive W for consistency
        if result.real < 0 {
            result = simd_quatf(real: -result.real, imag: -result.imag)
        }
        
        // Apply T-pose calibration if enabled
        result = applyCalibration(result, for: joint)
        
        // Apply root correction for hips
        if joint == .hips {
            result = simd_mul(rootRotationCorrection, result)
        }
        
        // Apply left-side mirroring for symmetrical poses
        if isLeftSide(joint) {
            result = applyLeftSideMirroring(result)
        }
        
        return simd_normalize(result)
    }
    
    /// Check if joint is on the left side of the body
    private static func isLeftSide(_ joint: ARKitJoint) -> Bool {
        let leftJoints: [ARKitJoint] = [
            .leftShoulder, .leftUpperArm, .leftLowerArm, .leftHand,
            .leftUpperLeg, .leftLowerLeg, .leftFoot, .leftToes
        ]
        return leftJoints.contains(joint)
    }
    
    /// Apply mirroring for left-side joints
    /// This ensures symmetrical poses produce symmetrical outputs
    private static func applyLeftSideMirroring(_ rotation: simd_quatf) -> simd_quatf {
        // Mirror across XZ plane (negate Y components of rotation axis)
        return simd_quatf(
            real: rotation.real,
            imag: SIMD3<Float>(rotation.imag.x, -rotation.imag.y, rotation.imag.z)
        )
    }
    
    // MARK: - Matrix Operations
    
    /// Extract rotation quaternion from a 4x4 transform matrix
    /// Handles matrices with scale by normalizing basis vectors
    /// - Parameter transform: 4x4 column-major transform matrix
    /// - Returns: Rotation as unit quaternion
    static func extractRotation(from transform: simd_float4x4) -> simd_quatf {
        let col0 = simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let col1 = simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        let col2 = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        
        // Normalize columns to remove scale
        let x = simd_normalize(col0)
        let y = simd_normalize(col1)
        let z = simd_normalize(col2)
        
        let rotationMatrix = simd_float3x3(x, y, z)
        return simd_quatf(rotationMatrix)
    }
    
    // MARK: - T-Pose Calibration
    
    /// Calibrate using the provided skeleton as T-pose reference
    /// - Parameter skeleton: Skeleton in T-pose (arms out to sides)
    @MainActor
    static func calibrateTpose(_ skeleton: ARKitBodySkeleton) {
        calibrationOffsets.removeAll()
        
        // Compute the offset for each joint from its raw ARKit rotation
        for (joint, _) in jointToBoneMap {
            guard let transform = skeleton.joints[joint],
                  let parentJoint = arkitParentMap[joint],
                  let parentTransform = skeleton.joints[parentJoint] else { continue }
            
            // Compute what the "raw" local rotation would be
            let childWorldRot = extractRotation(from: transform)
            let parentWorldRot = extractRotation(from: parentTransform)
            let localRot = simd_mul(simd_inverse(parentWorldRot), childWorldRot)
            
            // Store the inverse as the calibration offset
            // When we apply: raw × inverse(offset) = identity (for T-pose)
            calibrationOffsets[joint] = simd_inverse(localRot)
        }
        
        isCalibrated = true
        restPoseCalibrationEnabled = true
    }
    
    /// Clear T-pose calibration
    @MainActor
    static func clearCalibration() {
        calibrationOffsets.removeAll()
        isCalibrated = false
        restPoseCalibrationEnabled = false
    }
    
    /// Apply calibration offset to a rotation
    @MainActor
    private static func applyCalibration(_ rotation: simd_quatf, for joint: ARKitJoint) -> simd_quatf {
        guard restPoseCalibrationEnabled,
              isCalibrated,
              let offset = calibrationOffsets[joint] else {
            return rotation
        }
        
        // Apply calibration: raw × offset = calibrated rotation
        return simd_mul(rotation, offset)
    }
    
    // MARK: - Full Skeleton Conversion
    
    /// Convert complete skeleton with diagnostics
    /// - Parameters:
    ///   - skeleton: ARKit body skeleton
    ///   - onUnmappedJoint: Callback for joints that couldn't be mapped
    /// - Returns: Conversion result with rotations and any errors
    @MainActor
    static func convertWithDiagnostics(
        skeleton: ARKitBodySkeleton,
        onUnmappedJoint: ((ARKitJoint) -> Void)? = nil
    ) -> (rotations: [VRMHumanoidBone: simd_quatf], hipsTranslation: simd_float3?) {
        var rotations: [VRMHumanoidBone: simd_quatf] = [:]
        var hipsTranslation: simd_float3?
        
        for (arkitJoint, vrmBone) in jointToBoneMap {
            guard let transform = skeleton.joints[arkitJoint] else {
                onUnmappedJoint?(arkitJoint)
                continue
            }
            
            // Extract hips translation for root motion
            if arkitJoint == .hips {
                hipsTranslation = convertHipsTranslation(from: transform)
            }
            
            if let rotation = computeVRMRotation(
                joint: arkitJoint,
                childTransform: transform,
                skeleton: skeleton
            ) {
                rotations[vrmBone] = rotation
            } else {
                onUnmappedJoint?(arkitJoint)
            }
        }
        
        return (rotations, hipsTranslation)
    }
}
