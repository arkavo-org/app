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

/// Audio-driven gesticulation layer for natural speaking animation.
/// Adds procedural head bobs and chest emphasis based on speech volume.
///
/// Layer priority 4 - after fidgets, before eye tracking.
public class SpeakingDynamicsLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.speaking.dynamics"
    public let priority = 4
    public var isEnabled = true

    public var affectedBones: Set<VRMHumanoidBone> {
        guard isSpeaking else { return [] }
        return [.head, .neck, .chest]
    }

    // MARK: - Speaking State

    /// Whether the avatar is currently speaking
    private var isSpeaking: Bool = false

    /// Phase accumulator for head bob oscillation
    private var headBobPhase: Float = 0

    /// Phase accumulator for chest emphasis
    private var chestEmphasisPhase: Float = 0

    /// Smoothed RMS for gesture calculation
    private var smoothedRMS: Float = 0

    /// Previous frame's RMS for onset detection
    private var previousRMS: Float = 0

    /// Accumulated emphasis from volume peaks
    private var emphasisAccumulator: Float = 0

    // MARK: - Configuration

    /// Base head bob frequency (Hz)
    public var baseBobFrequency: Float = 2.0

    /// Maximum additional bob frequency at full volume
    public var maxBobFrequencyBoost: Float = 3.0

    /// Head pitch amplitude at full volume (radians, ~4.5 degrees)
    public var headPitchAmplitude: Float = 0.08

    /// Head yaw amplitude at full volume (radians, ~2 degrees)
    public var headYawAmplitude: Float = 0.03

    /// Chest pitch amplitude at full volume (radians, ~2 degrees)
    public var chestPitchAmplitude: Float = 0.04

    /// RMS threshold for emphasis detection
    public var emphasisThreshold: Float = 0.5

    /// Decay rate for emphasis accumulator
    public var emphasisDecay: Float = 2.0

    // MARK: - RMS Input

    /// Current audio RMS (set externally from AudioAnalyzer)
    public var currentRMS: Float = 0

    // MARK: - Cached Output

    private var cachedOutput = LayerOutput(blendMode: .additive)

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Set speaking state
    /// - Parameter speaking: Whether the avatar is speaking
    public func setSpeakingState(_ speaking: Bool) {
        if speaking && !isSpeaking {
            // Starting to speak - reset phases
            headBobPhase = 0
            chestEmphasisPhase = 0
            emphasisAccumulator = 0
        }
        isSpeaking = speaking

        if !speaking {
            // Stopped speaking - reset state
            smoothedRMS = 0
            previousRMS = 0
            currentRMS = 0
        }
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        guard isSpeaking else { return }

        // Smooth the RMS input
        smoothedRMS += (currentRMS - smoothedRMS) * min(deltaTime * 10.0, 1.0)

        // Detect volume onsets (sudden increases)
        let rmsDelta = smoothedRMS - previousRMS
        if rmsDelta > 0.1 {
            emphasisAccumulator = min(emphasisAccumulator + rmsDelta * 2.0, 1.0)
        }
        previousRMS = smoothedRMS

        // Decay emphasis accumulator
        emphasisAccumulator = max(0, emphasisAccumulator - emphasisDecay * deltaTime)

        // Update head bob phase - frequency increases with volume
        let bobFrequency = baseBobFrequency + smoothedRMS * maxBobFrequencyBoost
        headBobPhase += deltaTime * bobFrequency * 2.0 * .pi

        // Wrap phase to prevent overflow
        if headBobPhase > 2.0 * .pi {
            headBobPhase -= 2.0 * .pi
        }

        // Update chest emphasis phase on loud syllables
        if smoothedRMS > emphasisThreshold {
            chestEmphasisPhase += deltaTime * 4.0
        } else {
            // Decay chest phase when quiet
            chestEmphasisPhase = max(0, chestEmphasisPhase - deltaTime * 2.0)
        }
    }

    public func evaluate() -> LayerOutput {
        cachedOutput.bones.removeAll(keepingCapacity: true)

        guard isSpeaking && smoothedRMS > 0.01 else {
            return cachedOutput
        }

        // Head pitch (nodding) - varies with volume
        // Primary motion on speech
        let headPitch = sin(headBobPhase) * headPitchAmplitude * smoothedRMS

        // Slight head yaw variation (emphasis gestures)
        // Different frequency ratio for organic feel
        let headYaw = sin(headBobPhase * 0.7) * headYawAmplitude * smoothedRMS

        // Add emphasis-driven nod on volume peaks
        let emphasisNod = emphasisAccumulator * 0.05

        var head = ProceduralBoneTransform.identity
        let headPitchQuat = simd_quatf(angle: headPitch + emphasisNod, axis: SIMD3<Float>(1, 0, 0))
        let headYawQuat = simd_quatf(angle: headYaw, axis: SIMD3<Float>(0, 1, 0))
        head.rotation = headYawQuat * headPitchQuat
        cachedOutput.bones[.head] = head

        // Neck follows head at reduced intensity
        var neck = ProceduralBoneTransform.identity
        let neckPitch = headPitch * 0.3 + emphasisNod * 0.5
        neck.rotation = simd_quatf(angle: neckPitch, axis: SIMD3<Float>(1, 0, 0))
        cachedOutput.bones[.neck] = neck

        // Chest forward lean on emphasis
        let chestPitch = sin(chestEmphasisPhase * 4.0) * chestPitchAmplitude * smoothedRMS
        var chest = ProceduralBoneTransform.identity
        chest.rotation = simd_quatf(angle: chestPitch, axis: SIMD3<Float>(1, 0, 0))
        cachedOutput.bones[.chest] = chest

        return cachedOutput
    }
}
