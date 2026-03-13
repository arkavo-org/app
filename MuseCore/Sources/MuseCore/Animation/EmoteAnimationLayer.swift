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

/// Emote metadata and timing layer for Muse app.
/// All visual animation is handled by VRMAAnimationLayer via mocap clips.
/// This layer provides enum definitions, durations, emotion mappings, and timing callbacks.
public class EmoteAnimationLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.emotes"
    public let priority = 3
    public var isEnabled = true

    public var affectedBones: Set<VRMHumanoidBone> { [] }

    // MARK: - Emote Types

    public enum Emote: String, CaseIterable, Sendable {
        case none
        case wave
        case nod
        case jump
        case hop
        case thinking
        case bow
        case surprised
        case laugh
        case shrug
        case clap
        case sad
        case angry
        case pout
        case excited
        case scared
        case flex
        case heart
        case point
        case bashful
        case victory
        case exhausted
        case dance
        case yawn
        case curious
        case nervous
        case proud
        case relieved
        case disgust
        case goodbye
        case love
        case confused
        case grateful
        case danceGangnam
        case danceDab
        case idle
        case walk
        case arGreeting
    }

    // MARK: - State

    private var currentEmote: Emote = .none
    private var emoteProgress: Float = 0
    private var emoteDuration: Float = 1.0

    // MARK: - Durations

    private static let durations: [Emote: Float] = [
        .wave: 2.0,
        .nod: 1.5,
        .jump: 1.2,
        .hop: 1.2,
        .thinking: 1.5,
        .bow: 1.2,
        .surprised: 1.5,
        .laugh: 1.5,
        .shrug: 1.5,
        .clap: 1.5,
        .sad: 1.5,
        .angry: 1.5,
        .pout: 1.5,
        .excited: 2.0,
        .scared: 1.5,
        .flex: 1.5,
        .heart: 2.0,
        .point: 1.5,
        .bashful: 2.0,
        .victory: 2.0,
        .exhausted: 2.0,
        .dance: 4.0,
        .yawn: 2.0,
        .curious: 1.5,
        .nervous: 2.0,
        .proud: 1.5,
        .relieved: 1.5,
        .disgust: 1.5,
        .goodbye: 2.0,
        .love: 2.5,
        .confused: 1.5,
        .grateful: 2.5,
        .danceGangnam: 4.0,
        .danceDab: 2.0,
        .idle: 0.0,
        .none: 0.0,
        .walk: 1.0,
        .arGreeting: 5.0,
    ]

    // MARK: - Emote-to-Emotion Mapping

    public static let emoteEmotions: [Emote: (preset: VRMExpressionPreset, intensity: Float)?] = [
        .wave: (.happy, 0.6),
        .nod: (.happy, 0.3),
        .jump: (.happy, 0.95),
        .hop: (.happy, 0.5),
        .thinking: (.relaxed, 0.4),
        .bow: (.relaxed, 0.6),
        .surprised: (.surprised, 0.7),
        .laugh: (.happy, 0.9),
        .shrug: (.relaxed, 0.3),
        .clap: (.happy, 0.7),
        .sad: (.sad, 0.7),
        .angry: (.angry, 0.8),
        .pout: (.sad, 0.6),
        .excited: (.happy, 1.0),
        .scared: (.surprised, 0.8),
        .flex: (.happy, 0.5),
        .heart: (.happy, 0.8),
        .point: (.relaxed, 0.3),
        .bashful: (.relaxed, 0.5),
        .victory: (.happy, 0.9),
        .exhausted: (.relaxed, 0.4),
        .dance: (.happy, 0.8),
        .yawn: (.relaxed, 0.3),
        .curious: (.relaxed, 0.4),
        .nervous: (.surprised, 0.3),
        .proud: (.happy, 0.6),
        .relieved: (.relaxed, 0.5),
        .disgust: (.angry, 0.5),
        .goodbye: (.happy, 0.5),
        .love: (.happy, 0.8),
        .confused: (.surprised, 0.4),
        .grateful: (.happy, 0.7),
        .danceGangnam: (.happy, 0.9),
        .danceDab: (.happy, 0.7),
        .idle: nil,
        .none: nil,
        .walk: nil,
        .arGreeting: (.happy, 0.6),
    ]

    // MARK: - Callbacks

    public var onEmoteEnded: ((Emote, VRMExpressionPreset?, Float) -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    public func trigger(_ emote: Emote) {
        currentEmote = emote
        emoteProgress = 0
        emoteDuration = Self.durations[emote] ?? 1.0
    }

    public var activeEmote: Emote { currentEmote }
    public var isPlaying: Bool { currentEmote != .none && currentEmote != .idle }

    public func stopWalk() {
        if currentEmote == .walk {
            currentEmote = .none
            emoteProgress = 0
        }
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        guard currentEmote != .none && currentEmote != .idle else { return }

        emoteProgress += deltaTime / emoteDuration

        if emoteProgress >= 1.0 {
            if currentEmote == .walk {
                emoteProgress = emoteProgress.truncatingRemainder(dividingBy: 1.0)
            } else {
                let endedEmote = currentEmote
                currentEmote = .none
                emoteProgress = 0

                if let emotionData = Self.emoteEmotions[endedEmote], let emotion = emotionData {
                    onEmoteEnded?(endedEmote, emotion.preset, emotion.intensity)
                } else {
                    onEmoteEnded?(endedEmote, nil, 0)
                }
            }
        }
    }

    public func evaluate() -> LayerOutput {
        // All visual animation handled by VRMAAnimationLayer — this layer is metadata only
        LayerOutput(blendMode: .additive)
    }
}
