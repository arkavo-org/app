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

/// Animation layer for lip sync visemes.
/// Integrates with LipSyncCoordinator to drive mouth morphs based on speech.
///
/// Features:
/// - Real-time viseme output from scheduled timeline
/// - Smooth viseme transitions with configurable blend duration
/// - Silence detection with jaw relaxation
/// - Integration with expression system via morph weights
///
/// Priority 5 - same level as speaking dynamics, overrides lingering mood
/// expressions but allows emotes to take precedence during strong reactions.
public class LipSyncLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.lipsync"
    public let priority = 5  // Between moodLingering (4) and speakingDynamics (5)
    public var isEnabled = true

    /// This layer only outputs morph weights, no bone transforms
    public var affectedBones: Set<VRMHumanoidBone> {
        []
    }

    // MARK: - Injected State (set by ProceduralAnimationController on main thread)

    /// Whether lip sync coordinator is currently playing
    public var coordinatorIsPlaying: Bool = false

    /// Current morph weights from coordinator
    public var coordinatorMorphWeights: [String: Float] = [:]

    // MARK: - Lip Sync State

    /// Current viseme weights being output
    private var currentWeights: [String: Float] = [:]

    /// Target viseme weights (from LipSyncCoordinator)
    private var targetWeights: [String: Float] = [:]

    /// Previous frame's weights for smoothing
    private var previousWeights: [String: Float] = [:]

    /// Blend factor for viseme transitions (0 = previous, 1 = target)
    private var transitionBlend: Float = 0

    /// Whether lip sync is currently active
    private var isActive: Bool = false

    // MARK: - Configuration

    /// Smoothing factor for viseme transitions (0 = no smoothing, 1 = instant)
    /// Lower = smoother but more latency, Higher = more responsive but jerky
    /// Note: The VisemeScheduler already applies coarticulation blending,
    /// so this only needs light smoothing to avoid popping.
    public var smoothingFactor: Float = 0.35

    /// Jaw relaxation factor during silence (0 = keep mouth closed, 1 = fully relaxed)
    public var jawRelaxation: Float = 0.3

    /// Minimum weight threshold to include in output (reduces noise)
    public var weightThreshold: Float = 0.01

    /// Time to fully blend out when speech ends
    public var blendOutDuration: Float = 0.15

    // MARK: - Cached Output

    private var cachedOutput = LayerOutput(blendMode: .additive)

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Update lip sync weights from external source (LipSyncCoordinator)
    /// - Parameter weights: Dictionary of morph names to target weights
    public func setVisemeWeights(_ weights: [String: Float]) {
        targetWeights = weights
        isActive = !weights.isEmpty
    }

    /// Force immediate mouth closure (for interruption protocol)
    public func forceClose() {
        targetWeights.removeAll()
        currentWeights.removeAll()
        previousWeights.removeAll()
        transitionBlend = 0
        isActive = false
    }

    /// Check if lip sync is currently producing non-zero output
    public var hasActiveViseme: Bool {
        isActive || currentWeights.values.contains { $0 > weightThreshold }
    }

    // MARK: - AnimationLayer Protocol

    // Debug frame counter
    private var debugFrameCounter = 0

    public func update(deltaTime: Float, context: AnimationContext) {
        // Get current weights from coordinator (pushed by ProceduralAnimationController)
        if coordinatorIsPlaying {
            let weights = coordinatorMorphWeights

            // Debug logging
            debugFrameCounter += 1
            if debugFrameCounter % 60 == 0 {
                print("[LipSyncLayer] isPlaying=true, weights from coordinator: \(weights)")
            }

            setVisemeWeights(weights)
        } else if isActive {
            // Lip sync stopped - begin blend out
            print("[LipSyncLayer] Lip sync stopped, beginning blend out")
            targetWeights.removeAll()
            isActive = false
        }

        // Smooth transitions between viseme states
        updateSmoothing(deltaTime: deltaTime)
    }

    /// All viseme preset keys that must be explicitly managed
    private static let visemeKeys: [String] = [
        VRMExpressionPreset.aa.rawValue,
        VRMExpressionPreset.ih.rawValue,
        VRMExpressionPreset.ou.rawValue,
        VRMExpressionPreset.ee.rawValue,
        VRMExpressionPreset.oh.rawValue,
    ]

    public func evaluate() -> LayerOutput {
        cachedOutput.morphWeights.removeAll(keepingCapacity: true)

        // Always output all viseme presets (including zeros) to ensure
        // the VRMExpressionController clears stale weights from previous frames.
        // Without this, old viseme weights persist and accumulate, causing
        // the mouth to show multiple shapes simultaneously.
        for key in Self.visemeKeys {
            cachedOutput.morphWeights[key] = currentWeights[key, default: 0]
        }

        // Debug logging
        if debugFrameCounter % 60 == 0 {
            let nonZero = cachedOutput.morphWeights.filter { $0.value > weightThreshold }
            if !nonZero.isEmpty {
                print("[LipSyncLayer] Evaluating morphWeights: \(nonZero)")
            }
        }

        return cachedOutput
    }

    // MARK: - Private

    /// Smooth viseme transitions using exponential moving average
    private func updateSmoothing(deltaTime: Float) {
        // Store previous weights for interpolation
        previousWeights = currentWeights

        // Calculate target with jaw relaxation during silence
        var effectiveTarget = targetWeights
        if !isActive {
            // Apply relaxation - reduce all mouth-related weights
            for (key, value) in effectiveTarget {
                effectiveTarget[key] = value * (1.0 - jawRelaxation)
            }
        }

        // Smooth transition using exponential moving average
        let alpha = min(smoothingFactor * deltaTime * 60.0, 1.0)

        // Start with all keys from both current and target
        let allKeys = Set(currentWeights.keys).union(effectiveTarget.keys)

        for key in allKeys {
            let current = currentWeights[key, default: 0]
            let target = effectiveTarget[key, default: 0]

            // Lerp towards target
            let smoothed = current + (target - current) * alpha

            if smoothed > weightThreshold {
                currentWeights[key] = smoothed
            } else {
                currentWeights.removeValue(forKey: key)
            }
        }

        // Handle blend out when inactive
        if !isActive && !currentWeights.isEmpty {
            let decay = deltaTime / blendOutDuration
            for (key, value) in currentWeights {
                let newValue = value - decay
                if newValue > weightThreshold {
                    currentWeights[key] = newValue
                } else {
                    currentWeights.removeValue(forKey: key)
                }
            }
        }
    }
}
