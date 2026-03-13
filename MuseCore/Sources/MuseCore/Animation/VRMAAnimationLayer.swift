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

/// Animation layer that plays VRMA clips (emotes, walk, etc).
/// Uses `.blend(weight)` mode so the compositor smoothly SLERPs between
/// the idle cycle layer and this layer's output during transitions.
///
/// Supports dual-slot A/B crossfade for seamless emote-to-emote transitions.
///
/// VRMA values from VRMAnimationLoader are absolute (already retargeted).
/// The compositor applies `basePose * layerOutput`, so this layer converts
/// absolute values to deltas: `delta = inverse(basePose) * absolute`.
public class VRMAAnimationLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.vrma"
    public let priority = 6  // Same priority as EmoteAnimationLayer (can replace it)
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

    /// Bind-pose transforms per bone (same values the compositor captured).
    private var bindRotations: [VRMHumanoidBone: simd_quatf] = [:]
    private var bindTranslations: [VRMHumanoidBone: SIMD3<Float>] = [:]
    private var bindScales: [VRMHumanoidBone: SIMD3<Float>] = [:]

    // Dual-slot A/B for crossfade between clips
    private var clipA: AnimationClip?
    private var clipB: AnimationClip?
    private var timeA: Float = 0
    private var timeB: Float = 0
    private var crossfade: Float = 0           // 0 = all A, 1 = all B
    private var isCrossfading = false
    private var crossfadeDuration: Float = 0.2

    private var isPlaying = false
    private var isLooping = false

    // Blend weight with easing for smooth transitions to/from idle
    private var blendWeight: Float = 0
    private var blendProgress: Float = 0       // 0..1 linear progress for easing
    private var blendDirection: BlendDirection = .none
    private var blendDuration: Float = 0.2

    private enum BlendDirection {
        case none, blendingIn, blendingOut
    }

    /// Cached output — uses .blend(weight) so compositor SLERPs with idle layer
    private var cachedOutput = LayerOutput(blendMode: .blend(0))

    // MARK: - Callbacks

    /// Called when clip finishes playing (non-looping only)
    public var onClipEnded: ((AnimationClip) -> Void)?

    // MARK: - Initialization

    public init() {}

    /// Capture bind-pose transforms from the VRM model.
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

    // MARK: - Public API

    /// Play a motion capture clip with optional blend-in and crossfade from current clip
    public func play(clip: AnimationClip, blendIn: Float = 0.2, loop: Bool = false) {
        if clipA != nil && isPlaying && blendWeight > 0.1 {
            // Crossfade from current clip to new clip
            // If already crossfading, snap A to current blend position
            if isCrossfading, let cB = clipB {
                clipA = cB
                timeA = timeB
            }
            clipB = clip
            timeB = 0
            crossfade = 0
            isCrossfading = true
            crossfadeDuration = max(blendIn, 0.05)
        } else {
            // Fresh start — no active clip to crossfade from
            clipA = clip
            timeA = 0
            clipB = nil
            isCrossfading = false
            crossfade = 0
        }

        isPlaying = true
        isLooping = loop

        // Start blend-in (or stay at full weight if already playing)
        if blendDirection != .none || blendWeight < 0.99 {
            blendDirection = .blendingIn
            blendProgress = 0
            blendDuration = max(blendIn, 0.05)
            // If already partially blended in, start progress partway through
            if blendWeight > 0.01 {
                blendProgress = blendWeight
            }
        }

        print("[VRMAAnimationLayer] Playing clip: duration=\(clip.duration)s, tracks=\(clip.jointTracks.count), loop=\(loop)")
    }

    /// Stop the current clip with optional blend-out
    public func stop(blendOut: Float = 0.2) {
        if blendOut > 0 {
            blendDirection = .blendingOut
            blendProgress = 0
            blendDuration = blendOut
        } else {
            blendWeight = 0
            blendDirection = .none
            isPlaying = false
            clipA = nil
            clipB = nil
            isCrossfading = false
        }
    }

    /// Check if currently playing a clip
    public var isActive: Bool {
        isPlaying && blendWeight > 0.01
    }

    /// Get current playback progress (0-1)
    public var progress: Float {
        guard let clip = clipA, clip.duration > 0 else { return 0 }
        return timeA / clip.duration
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        // Update blend weight with easing
        switch blendDirection {
        case .blendingIn:
            blendProgress = min(1.0, blendProgress + deltaTime / blendDuration)
            blendWeight = AnimationTimingConfig.easeInOutQuadratic(blendProgress)
            if blendProgress >= 1.0 {
                blendWeight = 1.0
                blendDirection = .none
            }

        case .blendingOut:
            blendProgress = min(1.0, blendProgress + deltaTime / blendDuration)
            blendWeight = 1.0 - AnimationTimingConfig.easeOutQuadratic(blendProgress)
            if blendProgress >= 1.0 {
                blendWeight = 0
                blendDirection = .none
                isPlaying = false
                let endedClip = clipA
                clipA = nil
                clipB = nil
                isCrossfading = false
                if let clip = endedClip {
                    onClipEnded?(clip)
                }
            }

        case .none:
            break
        }

        guard isPlaying, clipA != nil else { return }

        // Advance playback time for slot A
        timeA += deltaTime

        // Handle crossfade between clips
        if isCrossfading {
            timeB += deltaTime
            crossfade += deltaTime / crossfadeDuration
            if crossfade >= 1.0 {
                // Crossfade complete: B becomes the active clip
                clipA = clipB
                timeA = timeB
                clipB = nil
                timeB = 0
                crossfade = 0
                isCrossfading = false
            }
        }

        // Check for clip end on active slot
        let activeClip = isCrossfading ? clipB : clipA
        let activeTime = isCrossfading ? timeB : timeA
        if let clip = activeClip, activeTime >= clip.duration {
            if isLooping {
                if isCrossfading {
                    timeB = timeB.truncatingRemainder(dividingBy: clip.duration)
                } else {
                    timeA = timeA.truncatingRemainder(dividingBy: clip.duration)
                }
            } else if !isCrossfading {
                // Non-looping clip ended — smooth blend-out to idle
                if blendDirection != .blendingOut {
                    timeA = clip.duration  // clamp at end frame
                    blendDirection = .blendingOut
                    blendProgress = 0
                    blendDuration = 0.3
                }
            }
        }
    }

    public func evaluate() -> LayerOutput {
        cachedOutput.bones.removeAll(keepingCapacity: true)
        cachedOutput.morphWeights.removeAll(keepingCapacity: true)

        guard isPlaying, let currentClipA = clipA, blendWeight > 0.01 else {
            cachedOutput.blendMode = .blend(0)
            return cachedOutput
        }

        // Set dynamic blend weight — compositor SLERPs between idle and this layer
        cachedOutput.blendMode = .blend(blendWeight)

        if isCrossfading, let currentClipB = clipB {
            // Dual-slot crossfade: sample both clips and SLERP between them
            evaluateCrossfade(currentClipA, at: timeA, currentClipB, at: timeB)
        } else {
            // Single clip: output full-strength deltas
            evaluateSingleClip(currentClipA, at: timeA)
        }

        return cachedOutput
    }

    // MARK: - Private Evaluation

    private let identityQuat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private let identityScale = SIMD3<Float>(1, 1, 1)

    /// Sample a single clip and write full-strength deltas to cachedOutput
    private func evaluateSingleClip(_ clip: AnimationClip, at time: Float) {
        let clampedTime = min(time, clip.duration)

        for track in clip.jointTracks {
            let (rotation, translation, scale) = track.sample(at: clampedTime)
            var transform = ProceduralBoneTransform.identity

            if let rot = rotation {
                let bind = bindRotations[track.bone] ?? identityQuat
                transform.rotation = simd_mul(simd_inverse(bind), rot)
            }

            if let trans = translation, track.bone != .hips {
                let bind = bindTranslations[track.bone] ?? .zero
                transform.translation = trans - bind
            }

            if let scl = scale {
                let bind = bindScales[track.bone] ?? identityScale
                transform.scale = SIMD3<Float>(
                    bind.x > 1e-6 ? scl.x / bind.x : 1,
                    bind.y > 1e-6 ? scl.y / bind.y : 1,
                    bind.z > 1e-6 ? scl.z / bind.z : 1
                )
            }

            cachedOutput.bones[track.bone] = transform
        }

        // Morphs accumulate additively in compositor — scale by blendWeight manually
        for track in clip.morphTracks {
            let weight = track.sample(at: clampedTime) * blendWeight
            if weight > 0.001 {
                cachedOutput.morphWeights[track.key] = weight
            }
        }
    }

    /// Sample two clips with crossfade and write blended deltas to cachedOutput
    private func evaluateCrossfade(
        _ clipA: AnimationClip, at timeA: Float,
        _ clipB: AnimationClip, at timeB: Float
    ) {
        let clampedTimeA = min(timeA, clipA.duration)
        let clampedTimeB = min(timeB, clipB.duration)

        // Collect all bones from both clips
        var allBones = Set<VRMHumanoidBone>()
        for track in clipA.jointTracks { allBones.insert(track.bone) }
        for track in clipB.jointTracks { allBones.insert(track.bone) }

        // Sample clip A deltas
        var transformsA: [VRMHumanoidBone: ProceduralBoneTransform] = [:]
        for track in clipA.jointTracks {
            transformsA[track.bone] = sampleTrackDelta(track, at: clampedTimeA)
        }

        // Sample clip B deltas
        var transformsB: [VRMHumanoidBone: ProceduralBoneTransform] = [:]
        for track in clipB.jointTracks {
            transformsB[track.bone] = sampleTrackDelta(track, at: clampedTimeB)
        }

        // SLERP between A and B for each bone
        let identity = ProceduralBoneTransform.identity
        for bone in allBones {
            let a = transformsA[bone] ?? identity
            let b = transformsB[bone] ?? identity

            var blended = ProceduralBoneTransform.identity
            blended.rotation = simd_slerp(a.rotation, b.rotation, crossfade)
            blended.translation = simd_mix(a.translation, b.translation, SIMD3(repeating: crossfade))
            blended.scale = simd_mix(a.scale, b.scale, SIMD3(repeating: crossfade))

            cachedOutput.bones[bone] = blended
        }

        // Blend morph weights (scale by blendWeight since morphs accumulate additively)
        var allMorphKeys = Set<String>()
        for track in clipA.morphTracks { allMorphKeys.insert(track.key) }
        for track in clipB.morphTracks { allMorphKeys.insert(track.key) }

        var morphsA: [String: Float] = [:]
        for track in clipA.morphTracks { morphsA[track.key] = track.sample(at: clampedTimeA) }
        var morphsB: [String: Float] = [:]
        for track in clipB.morphTracks { morphsB[track.key] = track.sample(at: clampedTimeB) }

        let weightA = 1.0 - crossfade
        let weightB = crossfade
        for key in allMorphKeys {
            let vA = morphsA[key] ?? 0
            let vB = morphsB[key] ?? 0
            let blended = (vA * weightA + vB * weightB) * blendWeight
            if blended > 0.001 {
                cachedOutput.morphWeights[key] = blended
            }
        }
    }

    /// Sample a single joint track and return its full-strength delta transform
    private func sampleTrackDelta(_ track: JointTrack, at time: Float) -> ProceduralBoneTransform {
        let (rotation, translation, scale) = track.sample(at: time)
        var transform = ProceduralBoneTransform.identity

        if let rot = rotation {
            let bind = bindRotations[track.bone] ?? identityQuat
            transform.rotation = simd_mul(simd_inverse(bind), rot)
        }

        if let trans = translation, track.bone != .hips {
            let bind = bindTranslations[track.bone] ?? .zero
            transform.translation = trans - bind
        }

        if let scl = scale {
            let bind = bindScales[track.bone] ?? identityScale
            transform.scale = SIMD3<Float>(
                bind.x > 1e-6 ? scl.x / bind.x : 1,
                bind.y > 1e-6 ? scl.y / bind.y : 1,
                bind.z > 1e-6 ? scl.z / bind.z : 1
            )
        }

        return transform
    }
}
