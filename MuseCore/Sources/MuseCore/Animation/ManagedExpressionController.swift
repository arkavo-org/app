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

/// Manages expression lifecycle with smooth transitions and natural decay.
/// Implements state machine: neutral -> building -> peak -> holding -> decaying -> neutral
@MainActor
public class ManagedExpressionController {

    // MARK: - Expression State

    public enum State: Equatable, CustomStringConvertible {
        case neutral
        case building(targetPreset: VRMExpressionPreset, targetIntensity: Float)
        case peak(preset: VRMExpressionPreset, intensity: Float)
        case holding(preset: VRMExpressionPreset, intensity: Float)
        case decaying(preset: VRMExpressionPreset, startIntensity: Float)

        public var description: String {
            switch self {
            case .neutral: return "neutral"
            case .building(let preset, let intensity): return "building(\(preset.rawValue), \(String(format: "%.2f", intensity)))"
            case .peak(let preset, let intensity): return "peak(\(preset.rawValue), \(String(format: "%.2f", intensity)))"
            case .holding(let preset, let intensity): return "holding(\(preset.rawValue), \(String(format: "%.2f", intensity)))"
            case .decaying(let preset, let start): return "decaying(\(preset.rawValue), from \(String(format: "%.2f", start)))"
            }
        }
    }

    // MARK: - Properties

    private(set) public var state: State = .neutral

    /// Current expression preset being displayed
    private(set) public var currentPreset: VRMExpressionPreset = .neutral

    /// Current expression intensity (0.0 - 1.0)
    private(set) public var currentIntensity: Float = 0.0

    /// Timer for state transitions
    private var stateTimer: Float = 0

    /// Speed for building up to target intensity (per second)
    private let buildSpeed: Float = 5.0

    /// Callback when expression changes
    public var onExpressionChanged: ((VRMExpressionPreset, Float) -> Void)?

    // MARK: - Micro-Expression State (Interruption Jolt)

    /// Whether a micro-expression is currently active
    private var microExpressionActive: Bool = false

    /// Saved expression state to restore after micro-expression
    private var savedPreset: VRMExpressionPreset?
    private var savedIntensity: Float = 0
    private var savedState: State?

    /// Micro-expression parameters
    private var microPreset: VRMExpressionPreset = .neutral
    private var microTargetIntensity: Float = 0
    private var microAttackDuration: Float = 0
    private var microSustainDuration: Float = 0
    private var microDecayDuration: Float = 0
    private var microTimer: Float = 0

    /// Micro-expression phase
    private enum MicroPhase {
        case attack
        case sustain
        case decay
    }
    private var microPhase: MicroPhase = .attack

    // MARK: - Public API

    /// Request a new expression with target intensity.
    /// Expression will build up, hold at peak, then naturally decay.
    public func setExpression(_ preset: VRMExpressionPreset, intensity: Float) {
        // Ignore neutral requests during active expression (let it decay naturally)
        if preset == .neutral && intensity <= 0 {
            return
        }

        // If same preset with similar intensity, extend the hold
        if case .holding(let currentPresetInHold, let currentHoldIntensity) = state,
           currentPresetInHold == preset,
           abs(currentHoldIntensity - intensity) < 0.1 {
            // Reset hold timer to extend
            stateTimer = 0
            return
        }

        // Interrupt current state and start building to new expression
        state = .building(targetPreset: preset, targetIntensity: intensity)
        stateTimer = 0
    }

    /// Force immediate return to neutral (e.g., for barge-in)
    public func clearExpression() {
        state = .neutral
        currentPreset = .neutral
        currentIntensity = 0
        stateTimer = 0
        microExpressionActive = false
        onExpressionChanged?(.neutral, 0)
    }

    /// Trigger a micro-expression overlay for interruption feedback.
    /// The micro-expression plays on top of the current expression and restores it after.
    /// Uses fast ADSR envelope: Attack -> Sustain -> Decay
    ///
    /// - Parameters:
    ///   - preset: The expression preset for the micro-expression
    ///   - intensity: Target intensity (default 0.35)
    ///   - attackDuration: Time to ramp up (default 50ms)
    ///   - sustainDuration: Time to hold at peak (default 100ms)
    ///   - decayDuration: Time to return to previous state (default 200ms)
    public func triggerMicroExpression(
        preset: VRMExpressionPreset,
        intensity: Float = 0.35,
        attackDuration: Float = AnimationTimingConfig.microExpressionAttackSeconds,
        sustainDuration: Float = AnimationTimingConfig.microExpressionSustainSeconds,
        decayDuration: Float = AnimationTimingConfig.microExpressionDecaySeconds
    ) {
        // Save current state if not already in micro-expression
        if !microExpressionActive {
            savedPreset = currentPreset
            savedIntensity = currentIntensity
            savedState = state
        }

        // Set up micro-expression parameters
        microExpressionActive = true
        microPreset = preset
        microTargetIntensity = intensity
        microAttackDuration = attackDuration
        microSustainDuration = sustainDuration
        microDecayDuration = decayDuration
        microTimer = 0
        microPhase = .attack
    }

    /// Update the expression state machine. Call every frame.
    /// - Parameter deltaTime: Time since last update in seconds
    public func update(deltaTime: Float) {
        // Handle micro-expression if active
        if microExpressionActive {
            updateMicroExpression(deltaTime: deltaTime)
            return
        }

        stateTimer += deltaTime

        switch state {
        case .neutral:
            // Stay in neutral, nothing to update
            currentPreset = .neutral
            currentIntensity = 0

        case .building(let targetPreset, let targetIntensity):
            // Build up to target intensity
            currentPreset = targetPreset
            currentIntensity = min(currentIntensity + buildSpeed * deltaTime, targetIntensity)

            // Reached target? Move to peak
            if currentIntensity >= targetIntensity {
                currentIntensity = targetIntensity
                state = .peak(preset: targetPreset, intensity: targetIntensity)
                stateTimer = 0
            }

            onExpressionChanged?(currentPreset, currentIntensity)

        case .peak(let preset, let intensity):
            // Brief peak state before holding
            currentPreset = preset
            currentIntensity = intensity

            // Immediately move to holding (peak is just a marker state)
            state = .holding(preset: preset, intensity: intensity)
            stateTimer = 0

            onExpressionChanged?(currentPreset, currentIntensity)

        case .holding(let preset, let intensity):
            // Hold at peak intensity
            currentPreset = preset
            currentIntensity = intensity

            // Hold timer expired? Start decay
            if stateTimer >= AnimationTimingConfig.expressionPeakHoldSeconds {
                state = .decaying(preset: preset, startIntensity: intensity)
                stateTimer = 0
            }

            // No callback needed - intensity unchanged

        case .decaying(let preset, let startIntensity):
            // Decay from peak to neutral using ease-out curve
            currentPreset = preset

            let decayProgress = stateTimer / AnimationTimingConfig.expressionDecaySeconds
            let remainingIntensity = AnimationTimingConfig.decayCurve(decayProgress)
            currentIntensity = startIntensity * remainingIntensity

            // Decay complete?
            if decayProgress >= 1.0 {
                currentIntensity = 0
                currentPreset = .neutral
                state = .neutral
                stateTimer = 0
            }

            onExpressionChanged?(currentPreset, currentIntensity)
        }
    }

    /// Update micro-expression overlay (ADSR envelope)
    private func updateMicroExpression(deltaTime: Float) {
        microTimer += deltaTime

        switch microPhase {
        case .attack:
            // Ramp up to target intensity
            let attackProgress = min(microTimer / microAttackDuration, 1.0)
            currentPreset = microPreset
            currentIntensity = microTargetIntensity * attackProgress
            onExpressionChanged?(currentPreset, currentIntensity)

            if attackProgress >= 1.0 {
                microPhase = .sustain
                microTimer = 0
            }

        case .sustain:
            // Hold at peak
            currentPreset = microPreset
            currentIntensity = microTargetIntensity
            // No callback needed - intensity unchanged

            if microTimer >= microSustainDuration {
                microPhase = .decay
                microTimer = 0
            }

        case .decay:
            // Decay back to saved state
            let decayProgress = min(microTimer / microDecayDuration, 1.0)
            let eased = AnimationTimingConfig.easeOutQuadratic(decayProgress)

            // Blend from micro-expression back to saved state
            let targetPreset = savedPreset ?? .neutral
            let targetIntensity = savedIntensity

            // Interpolate intensity
            currentIntensity = microTargetIntensity * (1.0 - eased) + targetIntensity * eased

            // Switch preset midway through decay
            if decayProgress > 0.5 {
                currentPreset = targetPreset
            }

            onExpressionChanged?(currentPreset, currentIntensity)

            if decayProgress >= 1.0 {
                // Restore saved state
                microExpressionActive = false
                currentPreset = targetPreset
                currentIntensity = targetIntensity
                if let saved = savedState {
                    state = saved
                }
                savedPreset = nil
                savedIntensity = 0
                savedState = nil
            }
        }
    }

    /// Check if an expression is currently active (not neutral or fully decayed)
    public var isActive: Bool {
        switch state {
        case .neutral:
            return false
        case .building, .peak, .holding:
            return true
        case .decaying:
            return currentIntensity > 0.01
        }
    }

    /// Get the current output for blending
    /// - Returns: Tuple of (preset, intensity) for the current frame
    public func getCurrentOutput() -> (preset: VRMExpressionPreset, intensity: Float) {
        return (currentPreset, currentIntensity)
    }

    // MARK: - Turn-Yielding

    /// Trigger expectant eyebrow for turn-yielding.
    /// Uses `.surprised` preset at low intensity to raise eyebrows naturally.
    /// - Parameter isQuestion: True if sentence ended with ?, false for statements
    public func triggerExpectantEyebrow(isQuestion: Bool) {
        let intensity = isQuestion
            ? AnimationTimingConfig.expectantBrowQuestionIntensity
            : AnimationTimingConfig.expectantBrowStatementIntensity

        triggerMicroExpression(
            preset: .surprised,
            intensity: intensity,
            attackDuration: 0.1,
            sustainDuration: AnimationTimingConfig.expectantHoldDurationSeconds,
            decayDuration: AnimationTimingConfig.expectantFadeDurationSeconds
        )
    }
}
