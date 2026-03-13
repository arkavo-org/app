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
import VRMMetalKit

/// Mood lingering layer - maintains emotional expression after emotes end.
/// When an emote like "laugh" ends, the associated mood (happy) lingers
/// before naturally decaying, providing emotional continuity.
///
/// Layer priority 4 - between ExpressionLayer (3) and SpeakingDynamicsLayer (5).
public class MoodLingeringLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.mood.lingering"
    public let priority = 4  // After expression layer, before speaking dynamics
    public var isEnabled = true

    public var affectedBones: Set<VRMHumanoidBone> {
        []  // Morphs only - no bone transforms
    }

    // MARK: - State Machine

    public enum State: Equatable, CustomStringConvertible {
        case idle
        case lingeringHold(preset: VRMExpressionPreset, intensity: Float)
        case lingeringDecay(preset: VRMExpressionPreset, startIntensity: Float)

        public var description: String {
            switch self {
            case .idle:
                return "idle"
            case .lingeringHold(let preset, let intensity):
                return "lingeringHold(\(preset.rawValue), \(String(format: "%.2f", intensity)))"
            case .lingeringDecay(let preset, let start):
                return "lingeringDecay(\(preset.rawValue), from \(String(format: "%.2f", start)))"
            }
        }
    }

    // MARK: - Properties

    private(set) public var state: State = .idle
    private var stateTimer: Float = 0

    /// Current output intensity for blending
    private(set) public var currentIntensity: Float = 0

    /// Current output preset
    private(set) public var currentPreset: VRMExpressionPreset = .neutral

    // MARK: - Configuration

    /// Duration to hold lingering mood at peak intensity (seconds)
    public var lingerHoldDuration: Float {
        Float(AnimationTimingConfig.moodLingerHoldMs) / 1000.0
    }

    /// Duration for lingering mood to decay (seconds)
    public var lingerDecayDuration: Float {
        Float(AnimationTimingConfig.moodLingerDecayMs) / 1000.0
    }

    // MARK: - Cached Output

    private var cachedOutput = LayerOutput(blendMode: .additive)

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Inject a lingering mood when an emote ends.
    /// Called by EmoteAnimationLayer via callback when emote completes.
    /// - Parameters:
    ///   - preset: The expression preset to linger (e.g., .happy after laugh)
    ///   - intensity: The intensity to hold (0.0 - 1.0)
    public func injectLingeringMood(preset: VRMExpressionPreset, intensity: Float) {
        guard intensity > 0.01 else { return }

        state = .lingeringHold(preset: preset, intensity: intensity)
        stateTimer = 0
        currentPreset = preset
        currentIntensity = intensity
    }

    /// Clear any lingering mood immediately.
    /// Called when a new emote starts or new expression is set.
    public func clearLingeringMood() {
        state = .idle
        stateTimer = 0
        currentPreset = .neutral
        currentIntensity = 0
    }

    /// Check if mood is currently lingering
    public var isLingering: Bool {
        switch state {
        case .idle:
            return false
        case .lingeringHold, .lingeringDecay:
            return currentIntensity > 0.01
        }
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        stateTimer += deltaTime

        switch state {
        case .idle:
            currentPreset = .neutral
            currentIntensity = 0

        case .lingeringHold(let preset, let intensity):
            currentPreset = preset
            currentIntensity = intensity

            // Hold timer expired? Start decay
            if stateTimer >= lingerHoldDuration {
                state = .lingeringDecay(preset: preset, startIntensity: intensity)
                stateTimer = 0
            }

        case .lingeringDecay(let preset, let startIntensity):
            currentPreset = preset

            // Decay using ease-out curve
            let decayProgress = min(1.0, stateTimer / lingerDecayDuration)
            let remainingIntensity = AnimationTimingConfig.decayCurve(decayProgress)
            currentIntensity = startIntensity * remainingIntensity

            // Decay complete?
            if decayProgress >= 1.0 {
                state = .idle
                stateTimer = 0
                currentPreset = .neutral
                currentIntensity = 0
            }
        }
    }

    public func evaluate() -> LayerOutput {
        cachedOutput.bones.removeAll(keepingCapacity: true)
        cachedOutput.morphWeights.removeAll(keepingCapacity: true)

        guard currentIntensity > 0.01 else {
            return cachedOutput
        }

        // Output the lingering expression as morph weight
        cachedOutput.morphWeights[currentPreset.rawValue] = currentIntensity

        return cachedOutput
    }
}
