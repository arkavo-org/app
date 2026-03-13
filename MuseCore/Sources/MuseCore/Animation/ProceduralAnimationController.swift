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

// MARK: - Avatar Conversation State

/// Represents the current state of the avatar's conversation for animation purposes
public enum AvatarConversationState: Sendable {
    case idle
    case listening
    case thinking
    case speaking
}

// MARK: - Procedural Animation Controller

/// Main facade for the procedural animation system.
/// Delegates to VRMMetalKit's AnimationLayerCompositor for proper bone rotation handling.
@MainActor
public class ProceduralAnimationController {

    // MARK: - Properties

    private let compositor = AnimationLayerCompositor()
    private weak var model: VRMModel?
    private weak var expressionController: VRMExpressionController?

    // VRMA idle cycle layer (replaces procedural idle layers)
    public let idleCycleLayer = VRMAIdleCycleLayer()

    // Expression and mood layers
    public let expressionLayer = ExpressionLayer()
    public let moodLingeringLayer = MoodLingeringLayer()

    // Speech-driven layers
    public let speakingDynamicsLayer = SpeakingDynamicsLayer()
    public let lipSyncLayer = LipSyncLayer()

    // Emote layers
    public let emoteLayer = EmoteAnimationLayer()
    public let vrmaLayer = VRMAAnimationLayer()

    // Physics interaction layer (recoil/lean from touch and device tilt)
    public let physicsInteractionLayer = PhysicsInteractionLayer()

    // Muse-specific animation layers
    public let eyeTrackingLayer = EyeTrackingLayer()

    // Managed expression controller for decay and timing
    private let managedExpressionController = ManagedExpressionController()

    // Welcome animation controller
    public let welcomeController = WelcomeAnimationController()

    // Animation context (updated each frame)
    private var context = AnimationContext()

    // AR context
    private var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 1.6, 2.5)
    private var avatarPosition: SIMD3<Float> = .zero

    // Conversation state
    private var conversationState: AvatarConversationState = .idle

    // Flirty context (triggers wink)
    private var isFlirtyContext: Bool = false

    // MARK: - Injected Dependencies

    /// LipSyncCoordinator instance (injected)
    public var lipSyncCoordinator: LipSyncCoordinator?

    /// AudioAnalyzer instance (injected)
    public var audioAnalyzer: AudioAnalyzer?

    /// VRMAClipLibrary instance (injected)
    public var clipLibrary: VRMAClipLibrary?

    // MARK: - Initialization

    public init() {
        // Add layers to compositor in priority order
        compositor.addLayer(idleCycleLayer)           // Priority 0 - VRMA idle cycling
        compositor.addLayer(expressionLayer)           // Priority 3 - blink, facial expressions
        compositor.addLayer(moodLingeringLayer)        // Priority 4 - post-emote mood persistence
        compositor.addLayer(speakingDynamicsLayer)     // Priority 5 - audio-driven gesticulation
        compositor.addLayer(lipSyncLayer)              // Priority 5 - lip sync visemes
        compositor.addLayer(emoteLayer)                // Priority 6 - emote metadata/timing
        compositor.addLayer(vrmaLayer)                 // Priority 6 - VRMA emote clips
        compositor.addLayer(physicsInteractionLayer)   // Priority 7 - physics recoil/lean
        compositor.addLayer(eyeTrackingLayer)          // Priority 8 - dedicated eye tracking

        // Enable/disable layers
        idleCycleLayer.isEnabled = true
        expressionLayer.isEnabled = true
        moodLingeringLayer.isEnabled = true
        speakingDynamicsLayer.isEnabled = true
        lipSyncLayer.isEnabled = true
        emoteLayer.isEnabled = true
        vrmaLayer.isEnabled = true
        physicsInteractionLayer.isEnabled = true
        eyeTrackingLayer.isEnabled = true

        // Wire up managed expression controller to expression layer
        managedExpressionController.onExpressionChanged = { [weak self] preset, intensity in
            self?.expressionLayer.setExpression(preset, intensity: intensity)
        }

        // Wire up welcome controller callbacks
        welcomeController.onTriggerEmote = { [weak self] emote in
            self?.triggerEmote(emote)
        }
        welcomeController.onSetExpression = { [weak self] preset, intensity in
            self?.setSentiment(preset, intensity: intensity)
        }
        welcomeController.onPlayLatestVRMA = { [weak self] in
            self?.playLatestVRMAIfExists()
        }

        // Wire up blink-gaze coordination
        eyeTrackingLayer.onBlinkRequest = { [weak self] in
            self?.expressionLayer.triggerBlink()
        }

        // Wire up emote completion for mood lingering
        emoteLayer.onEmoteEnded = { [weak self] _, preset, intensity in
            guard let preset = preset else { return }
            self?.moodLingeringLayer.injectLingeringMood(preset: preset, intensity: intensity)
        }
    }

    // MARK: - Configuration

    /// Configure injected dependencies and wire internal layers
    /// - Parameters:
    ///   - lipSync: LipSyncCoordinator instance
    ///   - audio: AudioAnalyzer instance
    ///   - clips: VRMAClipLibrary instance
    public func configure(lipSync: LipSyncCoordinator, audio: AudioAnalyzer, clips: VRMAClipLibrary) {
        self.lipSyncCoordinator = lipSync
        self.audioAnalyzer = audio
        self.clipLibrary = clips
    }

    // MARK: - Setup

    /// Configure the controller with a VRM model and expression controller
    public func setup(model: VRMModel, expressionController: VRMExpressionController?) {
        self.model = model
        self.expressionController = expressionController
        compositor.setup(model: model)

        // Capture bind pose for VRMA layers — they need to convert absolute VRMA values
        // to deltas because the compositor applies basePose * delta.
        // This is NOT retargeting (VRMAnimationLoader already did that).
        // It's converting the reference frame to match the compositor's expected input.
        idleCycleLayer.captureBindPose(model: model)
        vrmaLayer.captureBindPose(model: model)

        // Setup VRMA clip library for loading with retargeting
        clipLibrary?.setup(model: model)

        // Log available expressions for debugging
        if let expressions = model.expressions {
            let presetNames = expressions.preset.keys.map { $0.rawValue }.sorted()
            print("[ProceduralAnimation] Available expressions: \(presetNames)")
        }
    }

    /// Load all VRMA clips and setup idle cycle layer. Must be awaited before starting entrance.
    public func loadClips() async {
        guard let clipLibrary = clipLibrary else { return }
        await clipLibrary.loadAllClips()
        idleCycleLayer.setup(clips: clipLibrary.loadedIdleClips)
    }

    // MARK: - Camera/Avatar Position

    /// Update camera position
    public func updateCameraPosition(_ position: SIMD3<Float>) {
        cameraPosition = position
    }

    /// Update the avatar's world position from its anchor transform
    public func updateAvatarPosition(_ transform: matrix_float4x4) {
        avatarPosition = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }

    // MARK: - Speech Integration

    /// Set the current conversation state
    public func setConversationState(_ state: AvatarConversationState) {
        conversationState = state
        let isSpeaking = (state == .speaking)

        // Map to VRMMetalKit conversation state for context
        switch state {
        case .idle:
            context.conversationState = .idle
        case .listening:
            context.conversationState = .listening
        case .thinking:
            context.conversationState = .thinking
        case .speaking:
            context.conversationState = .speaking
        }

        // Update speaking dynamics layer
        speakingDynamicsLayer.setSpeakingState(isSpeaking)
    }

    /// Set the sentiment-driven expression (routed through managed expression controller)
    public func setSentiment(_ preset: VRMExpressionPreset, intensity: Float) {
        // Clear any lingering mood - new sentiment takes precedence
        moodLingeringLayer.clearLingeringMood()
        managedExpressionController.setExpression(preset, intensity: intensity)
    }

    /// Clear current expression (return to neutral)
    public func clearExpression() {
        managedExpressionController.clearExpression()
    }

    /// Check if an expression is currently active
    public var isExpressionActive: Bool {
        managedExpressionController.isActive
    }

    /// Set flirty context (triggers wink animation)
    public func setFlirtyContext(_ isFlirty: Bool) {
        isFlirtyContext = isFlirty
    }

    // MARK: - Interruption Protocol Support

    /// Trigger a micro-expression overlay for interruption feedback.
    public func triggerMicroExpression(preset: VRMExpressionPreset, intensity: Float) {
        managedExpressionController.triggerMicroExpression(preset: preset, intensity: intensity)
    }

    /// Force immediate saccade to user for interruption acknowledgment.
    public func forceSaccadeToUser() {
        eyeTrackingLayer.forceSaccadeToUser()
    }

    /// Force immediate mouth closure for interruption protocol.
    public func forceMouthClosed() {
        lipSyncLayer.forceClose()
        lipSyncCoordinator?.hardReset()
    }

    // MARK: - Turn-Yielding

    /// Trigger turn-yielding cues when avatar finishes speaking.
    public func triggerTurnYield(isQuestion: Bool) {
        managedExpressionController.triggerExpectantEyebrow(isQuestion: isQuestion)

        if isQuestion {
            triggerEmote(.thinking)
        }
    }

    /// Trigger silence breaker when user doesn't respond.
    public func triggerSilenceBreaker() {
        if Bool.random() {
            triggerEmote(.thinking)
        } else {
            managedExpressionController.setExpression(.happy, intensity: 0.4)
            triggerEmote(.nod)
        }
    }

    // MARK: - Entrance Walk

    /// Start walk animation for entrance sequence
    public func startEntranceWalk() {
        if let clip = clipLibrary?.clip(for: .walk) {
            vrmaLayer.play(clip: clip, blendIn: 0.2, loop: true)
        }
    }

    /// Stop walk animation after entrance sequence
    /// Smooth blend-out is safe with .blend(weight) mode — no T-pose flash
    public func stopEntranceWalk() {
        vrmaLayer.stop(blendOut: 0.3)
    }

    // MARK: - Emote Triggers

    /// Trigger an emote animation — plays VRMA clip (no procedural fallback)
    public func triggerEmote(_ emote: EmoteAnimationLayer.Emote) {
        moodLingeringLayer.clearLingeringMood()

        guard let clip = clipLibrary?.clip(for: emote) else {
            print("[ProceduralAnimation] No VRMA clip for emote: \(emote.rawValue)")
            return
        }

        vrmaLayer.play(clip: clip, blendIn: 0.2, loop: false)

        vrmaLayer.onClipEnded = { [weak self] _ in
            if let emotionData = EmoteAnimationLayer.emoteEmotions[emote], let emotion = emotionData {
                self?.moodLingeringLayer.injectLingeringMood(preset: emotion.preset, intensity: emotion.intensity)
            }
        }
    }

    // MARK: - VRMA Clip Playback

    /// Play the "latest.vrma" clip if it exists (for development testing)
    public func playLatestVRMAIfExists() {
        guard let clip = clipLibrary?.clip(named: "latest") else {
            return
        }

        vrmaLayer.play(clip: clip, blendIn: 0.3, loop: false)
    }

    /// Play a VRMA clip by name
    public func playVRMAClip(named name: String, loop: Bool = false) {
        guard let clip = clipLibrary?.clip(named: name) else {
            return
        }

        vrmaLayer.play(clip: clip, blendIn: 0.2, loop: loop)
    }

    // MARK: - Physics Interaction

    /// Trigger physics recoil from touch impact
    public func triggerRecoil(
        impactPoint: SIMD3<Float>,
        surfaceNormal: SIMD3<Float>,
        intensity: Float = 1.0
    ) {
        physicsInteractionLayer.triggerRecoil(
            impactPoint: impactPoint,
            surfaceNormal: surfaceNormal,
            intensity: intensity
        )
    }

    /// Update physics lean from device gravity
    public func updatePhysicsLean(deviceGravity: SIMD3<Float>) {
        physicsInteractionLayer.updateLean(deviceGravity: deviceGravity)
    }

    // MARK: - Wind

    /// Set wind vector for SpringBone hair/cloth physics
    public func setWind(_ wind: SIMD3<Float>) {
        let strength = simd_length(wind)
        if strength > 0.001 {
            let direction = wind / strength
            model?.springBoneGlobalParams?.windDirection = direction
            model?.springBoneGlobalParams?.windAmplitude = strength
            model?.springBoneGlobalParams?.windFrequency = 1.0 + strength * 0.2
        } else {
            model?.springBoneGlobalParams?.windAmplitude = 0
        }
    }

    // MARK: - Main Update

    /// Main update loop - called from Renderer.draw()
    public func update(deltaTime: Float) {
        guard model != nil else { return }

        // Update context for this frame
        context.deltaTime = deltaTime
        context.time += deltaTime
        context.cameraPosition = cameraPosition
        context.avatarPosition = avatarPosition
        context.isFlirty = isFlirtyContext

        // Reset flirty flag after one frame (one-shot trigger)
        isFlirtyContext = false

        // Update managed expression controller (handles decay timing)
        managedExpressionController.update(deltaTime: deltaTime)

        // Update speaking dynamics layer with audio RMS
        speakingDynamicsLayer.currentRMS = audioAnalyzer?.currentRMS ?? 0

        // Update lip sync timing and push state to LipSyncLayer
        if let lipSync = lipSyncCoordinator {
            lipSync.update(deltaTime: deltaTime)
            lipSyncLayer.coordinatorIsPlaying = lipSync.isPlaying
            lipSyncLayer.coordinatorMorphWeights = lipSync.getMorphWeights()
        }

        // Update compositor (handles all layers)
        compositor.update(deltaTime: deltaTime, context: context)

        // Extract total composited head rotation for VOR
        if let headQuat = compositor.getCompositedBoneRotation(.head) {
            let matrix = simd_float3x3(headQuat)
            let yaw = atan2(matrix.columns.0.z, matrix.columns.2.z)
            let pitch = asin(simd_clamp(-matrix.columns.1.z, -1.0, 1.0))
            eyeTrackingLayer.updateHeadRotation(yaw: yaw, pitch: pitch)
        }

        // Apply all morph weights to expression controller
        compositor.applyMorphsToController(expressionController)
    }
}
