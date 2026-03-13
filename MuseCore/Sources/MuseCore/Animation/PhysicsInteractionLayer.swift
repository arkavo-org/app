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
import simd
import VRMMetalKit

/// Animation layer for physics-driven reactions (recoil, lean, balance)
/// Priority 6.5 (between emotes at 6 and eye tracking at 7)
public class PhysicsInteractionLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.physics.interaction"
    public let priority = 7  // Just before eye tracking (priority 7 -> moved to 8)
    public var isEnabled = true

    public var affectedBones: Set<VRMHumanoidBone> {
        [.hips, .spine, .chest, .head, .neck]
    }

    // MARK: - Spring Physics Parameters

    /// Spring stiffness for recoil (higher = faster return)
    private let recoilStiffness: Float = 150.0

    /// Damping coefficient (higher = less oscillation)
    private let recoilDamping: Float = 12.0

    /// Maximum recoil angle in radians
    private let maxRecoilAngle: Float = 0.15

    /// Minimum recoil angle in radians
    private let minRecoilAngle: Float = 0.05

    // MARK: - Recoil State

    /// Current recoil rotation offset
    private var recoilRotation: SIMD3<Float> = .zero  // Euler angles (pitch, yaw, roll)

    /// Current recoil angular velocity
    private var recoilVelocity: SIMD3<Float> = .zero

    /// Target recoil rotation (decays to zero)
    private var recoilTarget: SIMD3<Float> = .zero

    // MARK: - Lean State (Device Tilt)

    /// Current lean offset from device gravity
    private var leanOffset: SIMD3<Float> = .zero

    /// Smoothed device gravity vector
    private var smoothedGravity: SIMD3<Float> = SIMD3<Float>(0, -1, 0)

    /// Maximum lean angle in radians (for device tilt)
    public var maxLeanAngle: Float = 0.08

    // MARK: - Cached Output

    private var cachedOutput = LayerOutput(blendMode: .additive)

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Trigger recoil from impact
    /// - Parameters:
    ///   - impactPoint: World-space point where impact occurred
    ///   - surfaceNormal: Surface normal at impact point
    ///   - intensity: Impact intensity (0.0 - 1.0)
    public func triggerRecoil(
        impactPoint: SIMD3<Float>,
        surfaceNormal: SIMD3<Float>,
        intensity: Float = 1.0
    ) {
        // Calculate recoil direction from surface normal
        // Avatar leans away from impact direction
        let recoilAmount = simd_clamp(intensity, 0.0, 1.0) * (maxRecoilAngle - minRecoilAngle) + minRecoilAngle

        // Convert surface normal to local rotation
        // Assuming avatar faces -Z, surface normal gives us the lean direction
        let pitch = surfaceNormal.z * recoilAmount  // Forward/back lean
        let roll = surfaceNormal.x * recoilAmount   // Side lean

        // Add to current recoil target (accumulates for rapid hits)
        recoilTarget.x += pitch
        recoilTarget.z += roll

        // Clamp total recoil
        recoilTarget.x = simd_clamp(recoilTarget.x, -maxRecoilAngle * 1.5, maxRecoilAngle * 1.5)
        recoilTarget.z = simd_clamp(recoilTarget.z, -maxRecoilAngle * 1.5, maxRecoilAngle * 1.5)

        // Add initial velocity impulse for more dynamic response
        recoilVelocity.x += pitch * 3.0
        recoilVelocity.z += roll * 3.0
    }

    /// Update lean offset from device gravity
    /// - Parameter deviceGravity: Normalized gravity vector from CoreMotion
    public func updateLean(deviceGravity: SIMD3<Float>) {
        // Smooth the gravity input
        let smoothing: Float = 0.1
        smoothedGravity = simd_mix(smoothedGravity, deviceGravity, SIMD3<Float>(repeating: smoothing))

        // Convert gravity to lean angles
        // X gravity -> roll (side lean)
        // Z gravity -> pitch (forward/back lean) - clamped to prevent extreme values
        let clampedZ = simd_clamp(smoothedGravity.z, -0.7, 0.7)

        leanOffset.x = clampedZ * maxLeanAngle  // Pitch from Z gravity
        leanOffset.z = smoothedGravity.x * maxLeanAngle  // Roll from X gravity
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        // Spring physics for recoil decay
        // F = -k*x - b*v (spring force - damping force)
        let springForce = -recoilStiffness * (recoilRotation - recoilTarget)
        let dampingForce = -recoilDamping * recoilVelocity

        // Update velocity
        recoilVelocity += (springForce + dampingForce) * deltaTime

        // Update position
        recoilRotation += recoilVelocity * deltaTime

        // Decay recoil target back to zero (elastic return)
        let targetDecay = 1.0 - min(1.0, deltaTime * 3.0)
        recoilTarget *= targetDecay

        // If recoil is very small, zero it out
        if simd_length(recoilRotation) < 0.001 && simd_length(recoilVelocity) < 0.001 {
            recoilRotation = .zero
            recoilVelocity = .zero
        }
    }

    public func evaluate() -> LayerOutput {
        cachedOutput.bones.removeAll(keepingCapacity: true)
        cachedOutput.morphWeights.removeAll(keepingCapacity: true)

        // Combine recoil and lean
        let combinedPitch = recoilRotation.x + leanOffset.x
        let combinedRoll = recoilRotation.z + leanOffset.z

        // Apply to spine chain with decreasing influence up the chain
        // Hips get least movement, head gets most

        // Hips - subtle rotation (15% of total)
        if abs(combinedPitch) > 0.001 || abs(combinedRoll) > 0.001 {
            var hips = ProceduralBoneTransform.identity
            let hipsPitch = simd_quatf(angle: combinedPitch * 0.15, axis: SIMD3<Float>(1, 0, 0))
            let hipsRoll = simd_quatf(angle: combinedRoll * 0.15, axis: SIMD3<Float>(0, 0, 1))
            hips.rotation = hipsRoll * hipsPitch
            cachedOutput.bones[.hips] = hips
        }

        // Spine - moderate rotation (30% of total)
        if abs(combinedPitch) > 0.001 || abs(combinedRoll) > 0.001 {
            var spine = ProceduralBoneTransform.identity
            let spinePitch = simd_quatf(angle: combinedPitch * 0.30, axis: SIMD3<Float>(1, 0, 0))
            let spineRoll = simd_quatf(angle: combinedRoll * 0.30, axis: SIMD3<Float>(0, 0, 1))
            spine.rotation = spineRoll * spinePitch
            cachedOutput.bones[.spine] = spine
        }

        // Chest - more rotation (35% of total)
        if abs(combinedPitch) > 0.001 || abs(combinedRoll) > 0.001 {
            var chest = ProceduralBoneTransform.identity
            let chestPitch = simd_quatf(angle: combinedPitch * 0.35, axis: SIMD3<Float>(1, 0, 0))
            let chestRoll = simd_quatf(angle: combinedRoll * 0.35, axis: SIMD3<Float>(0, 0, 1))
            chest.rotation = chestRoll * chestPitch
            cachedOutput.bones[.chest] = chest
        }

        // Head - counter-rotation for stability (20% opposite direction)
        // This creates a natural "balance" response
        if abs(combinedPitch) > 0.001 || abs(combinedRoll) > 0.001 {
            var head = ProceduralBoneTransform.identity
            let headPitch = simd_quatf(angle: -combinedPitch * 0.20, axis: SIMD3<Float>(1, 0, 0))
            let headRoll = simd_quatf(angle: -combinedRoll * 0.20, axis: SIMD3<Float>(0, 0, 1))
            head.rotation = headRoll * headPitch
            cachedOutput.bones[.head] = head
        }

        return cachedOutput
    }

    // MARK: - Debug

    /// Check if currently in recoil animation
    public var isRecoiling: Bool {
        simd_length(recoilRotation) > 0.01 || simd_length(recoilVelocity) > 0.01
    }

    /// Reset all physics state
    public func reset() {
        recoilRotation = .zero
        recoilVelocity = .zero
        recoilTarget = .zero
        leanOffset = .zero
        smoothedGravity = SIMD3<Float>(0, -1, 0)
    }
}
