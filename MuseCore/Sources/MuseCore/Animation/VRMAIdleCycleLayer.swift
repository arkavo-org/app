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

/// Animation layer that cycles through idle VRMA clips with crossfade transitions.
/// Replaces the procedural BlendSpaceIdleLayer with professional mocap idle animations.
/// Uses dual-slot (A/B) ping-pong for seamless crossfading between clips.
///
/// VRMA values from VRMAnimationLoader are absolute (already retargeted).
/// The compositor applies `basePose * layerOutput`, so this layer converts
/// absolute values to deltas: `delta = inverse(basePose) * absolute`.
public class VRMAIdleCycleLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.idle.cycle"
    public let priority = 0
    public var isEnabled = true

    public var affectedBones: Set<VRMHumanoidBone> {
        if let clip = clipA {
            return Set(clip.jointTracks.map { $0.bone })
        }
        return [.hips, .spine, .chest, .head, .neck,
                .leftShoulder, .rightShoulder,
                .leftUpperArm, .rightUpperArm,
                .leftLowerArm, .rightLowerArm,
                .leftHand, .rightHand,
                .leftUpperLeg, .rightUpperLeg]
    }

    // MARK: - State

    private var idleClips: [AnimationClip] = []
    private var clipA: AnimationClip?
    private var clipB: AnimationClip?
    private var timeA: Float = 0
    private var timeB: Float = 0
    private var crossfade: Float = 0       // 0 = all A, 1 = all B
    private var isTransitioning = false
    private var crossfadeDuration: Float = 1.0
    private var shuffleBag: [Int] = []
    private var lastClipIndex: Int = -1

    /// Bind-pose transforms per bone (same values the compositor captured).
    /// Used to convert absolute VRMA values to deltas for the compositor.
    private var bindRotations: [VRMHumanoidBone: simd_quatf] = [:]
    private var bindTranslations: [VRMHumanoidBone: SIMD3<Float>] = [:]
    private var bindScales: [VRMHumanoidBone: SIMD3<Float>] = [:]

    private var cachedOutput = LayerOutput(blendMode: .replace)

    // MARK: - Initialization

    public init() {}

    // MARK: - Setup

    /// Capture bind-pose transforms from the VRM model.
    /// Must use the same model instance passed to compositor.setup() so values match.
    public func captureBindPose(model: VRMModel) {
        guard let humanoid = model.humanoid else { return }
        for bone in VRMHumanoidBone.allCases {
            if let nodeIndex = humanoid.getBoneNode(bone), nodeIndex < model.nodes.count {
                let node = model.nodes[nodeIndex]
                bindRotations[bone] = node.rotation
                bindTranslations[bone] = node.translation
                bindScales[bone] = node.scale
            }
        }
    }

    /// Configure with loaded idle clips
    public func setup(clips: [AnimationClip]) {
        idleClips = clips
        guard !clips.isEmpty else {
            print("[VRMAIdleCycleLayer] No idle clips provided")
            return
        }

        let index = Int.random(in: 0..<clips.count)
        clipA = clips[index]
        lastClipIndex = index
        timeA = 0
        crossfade = 0
        isTransitioning = false

        print("[VRMAIdleCycleLayer] Setup with \(clips.count) idle clips, starting with index \(index)")
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        guard !idleClips.isEmpty, let currentClipA = clipA else { return }

        timeA += deltaTime

        if isTransitioning {
            timeB += deltaTime
            crossfade += deltaTime / crossfadeDuration
            if crossfade >= 1.0 {
                crossfade = 0
                clipA = clipB
                timeA = timeB
                clipB = nil
                timeB = 0
                isTransitioning = false
            }
        }

        if !isTransitioning {
            let timeRemaining = currentClipA.duration - timeA
            if timeRemaining <= crossfadeDuration && idleClips.count > 1 {
                startTransition()
            } else if timeA >= currentClipA.duration {
                if idleClips.count == 1 {
                    timeA = timeA.truncatingRemainder(dividingBy: currentClipA.duration)
                } else {
                    startTransition()
                }
            }
        }
    }

    public func evaluate() -> LayerOutput {
        cachedOutput.bones.removeAll(keepingCapacity: true)
        cachedOutput.morphWeights.removeAll(keepingCapacity: true)

        guard !idleClips.isEmpty, let currentClipA = clipA else {
            return cachedOutput
        }

        if isTransitioning, let currentClipB = clipB {
            let weightA = 1.0 - crossfade
            let weightB = crossfade
            sampleClipBlended(currentClipA, at: timeA, weight: weightA,
                              currentClipB, at: timeB, weight: weightB)
        } else {
            sampleClip(currentClipA, at: timeA, weight: 1.0)
        }

        return cachedOutput
    }

    // MARK: - Private Methods

    private func startTransition() {
        guard idleClips.count > 1 else { return }
        let nextIndex = nextFromShuffleBag()

        clipB = idleClips[nextIndex]
        timeB = 0
        crossfade = 0
        isTransitioning = true
        lastClipIndex = nextIndex
        print("[VRMAIdleCycleLayer] Transitioning to clip \(nextIndex) (duration: \(String(format: "%.1f", idleClips[nextIndex].duration))s)")
    }

    /// Shuffle bag ensures all clips play before any repeats
    private func nextFromShuffleBag() -> Int {
        if shuffleBag.isEmpty {
            shuffleBag = Array(0..<idleClips.count).filter { $0 != lastClipIndex }.shuffled()
        }
        return shuffleBag.removeFirst()
    }

    /// Convert absolute VRMA rotation to compositor delta: `inverse(bindPose) * absolute`
    private func rotationDelta(for bone: VRMHumanoidBone, absolute: simd_quatf) -> simd_quatf {
        let bind = bindRotations[bone] ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        return simd_mul(simd_inverse(bind), absolute)
    }

    /// Convert absolute VRMA translation to compositor delta: `absolute - bindPose`
    /// Skips hips translation (matches AnimationPlayer default behavior)
    private func translationDelta(for bone: VRMHumanoidBone, absolute: SIMD3<Float>) -> SIMD3<Float>? {
        if bone == .hips { return nil }  // Skip hips translation like AnimationPlayer
        let bind = bindTranslations[bone] ?? .zero
        return absolute - bind
    }

    /// Convert absolute VRMA scale to compositor delta: `absolute / bindPose`
    private func scaleDelta(for bone: VRMHumanoidBone, absolute: SIMD3<Float>) -> SIMD3<Float> {
        let bind = bindScales[bone] ?? SIMD3<Float>(1, 1, 1)
        return SIMD3<Float>(
            bind.x > 1e-6 ? absolute.x / bind.x : 1,
            bind.y > 1e-6 ? absolute.y / bind.y : 1,
            bind.z > 1e-6 ? absolute.z / bind.z : 1
        )
    }

    private func sampleClip(_ clip: AnimationClip, at time: Float, weight: Float) {
        let clampedTime = min(time, clip.duration)
        let identityQuat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let identityScale = SIMD3<Float>(1, 1, 1)

        for track in clip.jointTracks {
            let (rotation, translation, scale) = track.sample(at: clampedTime)
            var transform = ProceduralBoneTransform.identity

            if let rot = rotation {
                let delta = rotationDelta(for: track.bone, absolute: rot)
                transform.rotation = simd_slerp(identityQuat, delta, weight)
            }

            if let trans = translation, let delta = translationDelta(for: track.bone, absolute: trans) {
                transform.translation = delta * weight
            }

            if let scl = scale {
                let delta = scaleDelta(for: track.bone, absolute: scl)
                transform.scale = simd_mix(identityScale, delta, SIMD3<Float>(repeating: weight))
            }

            cachedOutput.bones[track.bone] = transform
        }

        for track in clip.morphTracks {
            let w = track.sample(at: clampedTime) * weight
            if w > 0.001 {
                cachedOutput.morphWeights[track.key] = w
            }
        }
    }

    private func sampleClipBlended(
        _ clipA: AnimationClip, at timeA: Float, weight weightA: Float,
        _ clipB: AnimationClip, at timeB: Float, weight weightB: Float
    ) {
        let clampedTimeA = min(timeA, clipA.duration)
        let clampedTimeB = min(timeB, clipB.duration)

        var allBones = Set<VRMHumanoidBone>()
        for track in clipA.jointTracks { allBones.insert(track.bone) }
        for track in clipB.jointTracks { allBones.insert(track.bone) }

        // Sample clip A (convert to deltas)
        var transformsA: [VRMHumanoidBone: ProceduralBoneTransform] = [:]
        for track in clipA.jointTracks {
            let (rotation, translation, scale) = track.sample(at: clampedTimeA)
            var t = ProceduralBoneTransform.identity
            if let rot = rotation { t.rotation = rotationDelta(for: track.bone, absolute: rot) }
            if let trans = translation, let delta = translationDelta(for: track.bone, absolute: trans) {
                t.translation = delta
            }
            if let scl = scale { t.scale = scaleDelta(for: track.bone, absolute: scl) }
            transformsA[track.bone] = t
        }

        // Sample clip B (convert to deltas)
        var transformsB: [VRMHumanoidBone: ProceduralBoneTransform] = [:]
        for track in clipB.jointTracks {
            let (rotation, translation, scale) = track.sample(at: clampedTimeB)
            var t = ProceduralBoneTransform.identity
            if let rot = rotation { t.rotation = rotationDelta(for: track.bone, absolute: rot) }
            if let trans = translation, let delta = translationDelta(for: track.bone, absolute: trans) {
                t.translation = delta
            }
            if let scl = scale { t.scale = scaleDelta(for: track.bone, absolute: scl) }
            transformsB[track.bone] = t
        }

        let identity = ProceduralBoneTransform.identity

        for bone in allBones {
            let a = transformsA[bone] ?? identity
            let b = transformsB[bone] ?? identity

            var blended = ProceduralBoneTransform.identity
            blended.rotation = simd_slerp(a.rotation, b.rotation, weightB)
            blended.translation = a.translation * weightA + b.translation * weightB
            blended.scale = simd_mix(a.scale, b.scale, SIMD3<Float>(repeating: weightB))

            cachedOutput.bones[bone] = blended
        }

        var allMorphKeys = Set<String>()
        for track in clipA.morphTracks { allMorphKeys.insert(track.key) }
        for track in clipB.morphTracks { allMorphKeys.insert(track.key) }

        var morphsA: [String: Float] = [:]
        for track in clipA.morphTracks { morphsA[track.key] = track.sample(at: clampedTimeA) }
        var morphsB: [String: Float] = [:]
        for track in clipB.morphTracks { morphsB[track.key] = track.sample(at: clampedTimeB) }

        for key in allMorphKeys {
            let vA = morphsA[key] ?? 0
            let vB = morphsB[key] ?? 0
            let blended = vA * weightA + vB * weightB
            if blended > 0.001 {
                cachedOutput.morphWeights[key] = blended
            }
        }
    }
}
