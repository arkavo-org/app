//
//  VRMAvatarRenderer.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Foundation
import Metal
import MetalKit
import simd
import VRMMetalKit

/// Wraps VRMMetalKit renderer for avatar display and rendering
@MainActor
class VRMAvatarRenderer: NSObject {
    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderer: VRMRenderer?
    private var _model: VRMModel?

    /// The loaded VRM model (for VRMA export rest pose)
    var model: VRMModel? { _model }

    private var expressionController: VRMExpressionController? {
        renderer?.expressionController
    }

    // ARKit face tracking driver
    private let faceDriver: ARKitFaceDriver

    // ARKit body tracking driver
    private let bodyDriver: ARKitBodyDriver

    private(set) var isLoaded = false
    private(set) var error: Error?
    private var updateCount = 0  // For logging control

    // Lifecycle state
    private(set) var isPaused = false
    weak var mtkView: MTKView?

    // Current camera mode for resize handling
    private var currentCameraMode: CameraMode = .face
    enum CameraMode { case face, body }

    // Idle animation state
    private var idleAnimationTimer: Timer?
    private var breathingPhase: Float = 0
    private var nextBlinkTime: TimeInterval = 0
    private var isBlinking = false
    private var faceTrackingActive = false
    private var lastFaceTrackingTime: TimeInterval = 0

    // MARK: - Initialization

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Initialize ARKit face driver with default mapper and smoothing
        self.faceDriver = ARKitFaceDriver(
            mapper: .default,
            smoothing: .default
        )

        // Initialize ARKit body driver with default mapper and smoothing
        self.bodyDriver = ARKitBodyDriver(
            mapper: .default,
            smoothing: .default
        )

        super.init()

        // Initialize renderer (uses standard 3D MToon rendering by default)
        let vrmRenderer = VRMRenderer(device: device)
        renderer = vrmRenderer

        print("[VRMAvatarRenderer] Initialized with standard 3D rendering mode and ARKit driver")
        setupCamera()
    }

    // MARK: - Model Loading

    func loadModel(from url: URL) async throws {
        isLoaded = false
        error = nil

        do {
            #if DEBUG
            print("[VRMAvatarRenderer] Loading model from: \(url.path)")
            #endif

            // Load VRM model
            let vrmModel = try await VRMModel.load(from: url, device: device)
            _model = vrmModel

            #if DEBUG
            print("[VRMAvatarRenderer] Model loaded successfully, nodes: \(vrmModel.nodes.count)")
            #endif

            // Load into renderer
            renderer?.loadModel(vrmModel)

            #if DEBUG
            print("[VRMAvatarRenderer] Model loaded into renderer")
            #endif

            isLoaded = true

            // Start idle animation (visual self-check disabled for recording)
            Task { @MainActor in
                // await performVisualSelfCheck(model: vrmModel)
                startIdleAnimation()
            }
        } catch {
            print("[VRMAvatarRenderer] Failed to load model: \(error)")
            self.error = error
            isLoaded = false
            throw error
        }
    }

    // MARK: - Self-Check Validation

    /// Performs a visual self-check by animating through expressions
    private func performVisualSelfCheck(model: VRMModel) async {
        #if DEBUG
        print("\n🎬 [Visual Self-Check] Starting expression animation test...")

        guard let expressionController else {
            print("❌ [Visual Self-Check] No expression controller available")
            return
        }

        guard let expressions = model.expressions else {
            print("❌ [Visual Self-Check] Model has no expressions defined")
            return
        }

        // Report available expressions
        print("📋 [Visual Self-Check] Model has \(expressions.preset.count) preset expressions")

        // Test key expressions with visible animation
        let testExpressions: [(VRMExpressionPreset, String, TimeInterval)] = [
            (.neutral, "Neutral", 0.5),
            (.happy, "Happy/Smile", 1.0),
            (.neutral, "Neutral", 0.3),
            (.blink, "Blink", 0.3),
            (.neutral, "Neutral", 0.3),
            (.aa, "Mouth Open", 0.8),
            (.neutral, "Neutral", 0.3),
            (.angry, "Angry", 0.8),
            (.neutral, "Neutral", 0.3),
            (.sad, "Sad", 0.8),
            (.neutral, "Neutral", 0.5)
        ]

        print("\n🔬 [Visual Self-Check] Animating expressions (watch the avatar!)...")

        for (preset, name, duration) in testExpressions {
            if expressions.preset[preset] != nil {
                // Animate to the expression
                expressionController.setExpressionWeight(preset, weight: 1.0)
                print("   → \(name)")

                // Hold the expression
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

                // Reset to neutral
                expressionController.setExpressionWeight(preset, weight: 0.0)
            }
        }

        // Report ARKit compatibility
        let arkitMappedExpressions: [VRMExpressionPreset] = [
            .happy, .angry, .sad, .surprised, .blink,
            .aa, .ih, .ou, .ee, .oh
        ]

        let available = arkitMappedExpressions.filter { expressions.preset[$0] != nil }
        let coverage = Float(available.count) / Float(arkitMappedExpressions.count) * 100

        print("\n🎭 [Visual Self-Check] ARKit face tracking compatibility:")
        print("   📊 Expression coverage: \(available.count)/\(arkitMappedExpressions.count) (\(String(format: "%.0f", coverage))%)")

        if coverage >= 80 {
            print("   ✨ Excellent - full face tracking support")
        } else if coverage >= 50 {
            print("   ⚡ Good - most expressions will work")
        } else {
            print("   ⚠️  Limited - some expressions missing")
        }

        // Test body tracking if available
        if model.humanoid != nil {
            print("\n🦴 [Visual Self-Check] Testing body tracking capabilities...")

            // Zoom out for full body view
            setCameraForBody()
            print("   📷 Camera zoomed out for full body view")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second to transition

            // Define poses with their application functions
            let bodyPoses: [(String, (VRMModel) -> Void, TimeInterval)] = [
                ("T-Pose", applyTPose, 2.5),
                ("Arms Up", applyArmsUpPose, 2.0),
                ("Neutral", applyNeutralPose, 0.5),
                ("Squat", applySquatPose, 2.5),
                ("Neutral", applyNeutralPose, 0.5)
            ]

            print("\n🔬 [Visual Self-Check] Applying body poses...")
            for (poseName, poseFunc, duration) in bodyPoses {
                print("   → \(poseName)")
                poseFunc(model)  // Apply the pose
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }

            // Zoom back in for face
            setCameraForFace()
            print("   📷 Camera zoomed back to face view")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s transition
        } else {
            print("\n⚠️  [Visual Self-Check] No humanoid skeleton found - skipping body pose tests")
        }

        print("\n✅ [Visual Self-Check] Complete - starting idle animation\n")
        #endif
    }

    // MARK: - Idle Animation

    private func startIdleAnimation() {
        stopIdleAnimation()

        #if DEBUG
        print("💤 [Idle Animation] Starting breathing and blink animation")
        #endif

        nextBlinkTime = CACurrentMediaTime() + Double.random(in: 2.0...5.0)

        idleAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateIdleAnimation()
            }
        }
    }

    private func stopIdleAnimation() {
        idleAnimationTimer?.invalidate()
        idleAnimationTimer = nil
    }

    private func updateIdleAnimation() {
        guard let expressionController else { return }

        // Don't animate if face tracking is active
        let now = CACurrentMediaTime()
        if faceTrackingActive && (now - lastFaceTrackingTime) < 0.5 {
            return
        }

        // Breathing animation (subtle mouth movement)
        breathingPhase += 0.05
        let breathWeight = (sin(breathingPhase) + 1.0) * 0.02  // Very subtle 0-4% mouth open
        expressionController.setExpressionWeight(.aa, weight: breathWeight)

        // Blink animation
        if now >= nextBlinkTime {
            if !isBlinking {
                // Start blink
                isBlinking = true
                expressionController.setExpressionWeight(.blink, weight: 1.0)

                // Schedule blink end
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.expressionController?.setExpressionWeight(.blink, weight: 0.0)
                    self.isBlinking = false
                }

                // Schedule next blink
                nextBlinkTime = now + Double.random(in: 2.0...6.0)
            }
        }
    }

    // MARK: - Lifecycle Management

    /// Pause rendering and animations (call when view is hidden)
    func pause() {
        guard !isPaused else { return }
        isPaused = true

        stopIdleAnimation()
        mtkView?.isPaused = true

        #if DEBUG
        print("⏸️ [VRMAvatarRenderer] Paused")
        #endif
    }

    /// Resume rendering and animations (call when view is visible)
    func resume() {
        guard isPaused else { return }
        isPaused = false

        mtkView?.isPaused = false
        if isLoaded {
            startIdleAnimation()
        }

        #if DEBUG
        print("▶️ [VRMAvatarRenderer] Resumed")
        #endif
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        setCameraForFace()
    }

    /// Position camera for face tracking (close-up view)
    func setCameraForFace() {
        currentCameraMode = .face
        guard let renderer else { return }

        // Set up perspective projection - tighter FOV for face focus
        let fov: Float = 35.0 * .pi / 180.0  // Narrower FOV for portrait-style framing
        // Use actual drawable aspect ratio to prevent squashing
        let drawableSize = mtkView?.drawableSize ?? CGSize(width: 1920, height: 1080)
        let aspect: Float = drawableSize.width > 0 && drawableSize.height > 0
            ? Float(drawableSize.width / drawableSize.height)
            : 16.0 / 9.0  // Fallback
        let near: Float = 0.1
        let far: Float = 100.0

        renderer.projectionMatrix = perspectiveMatrix(
            fov: fov,
            aspect: aspect,
            near: near,
            far: far
        )

        // Camera positioned in front of avatar face, zoomed in for AR face tracking proportions
        // VRM models typically face -Z, so camera is at negative Z to see the front
        let eye = SIMD3<Float>(0, 1.45, -1.0)    // Eye level height, 1.0 unit away on -Z
        let center = SIMD3<Float>(0, 1.45, 0)    // Look at eye level
        let up = SIMD3<Float>(0, 1, 0)           // Up vector

        renderer.viewMatrix = lookAtMatrix(eye: eye, center: center, up: up)
    }

    /// Position camera for body tracking (full body view)
    func setCameraForBody() {
        currentCameraMode = .body
        guard let renderer else { return }

        // FOV tuned for full body to fill screen
        let fov: Float = 45.0 * .pi / 180.0  // Moderate FOV for full body framing
        // Use actual drawable aspect ratio to prevent squashing
        let drawableSize = mtkView?.drawableSize ?? CGSize(width: 1920, height: 1080)
        let aspect: Float = drawableSize.width > 0 && drawableSize.height > 0
            ? Float(drawableSize.width / drawableSize.height)
            : 16.0 / 9.0  // Fallback
        let near: Float = 0.1
        let far: Float = 100.0

        renderer.projectionMatrix = perspectiveMatrix(
            fov: fov,
            aspect: aspect,
            near: near,
            far: far
        )

        // Camera positioned to frame full body from head to feet, centered
        // VRM models are ~1.7m tall with hips around 0.9m height
        let eye = SIMD3<Float>(0, 0.9, -2.2)     // Centered on hips, close enough to fill frame
        let center = SIMD3<Float>(0, 0.9, 0)     // Look at hip center
        let up = SIMD3<Float>(0, 1, 0)           // Up vector

        renderer.viewMatrix = lookAtMatrix(eye: eye, center: center, up: up)
    }

    // MARK: - Matrix Helpers

    private func perspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fov * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2 * far * near / zRange

        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0),
        )
    }

    private func lookAtMatrix(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        return simd_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1),
        )
    }

    // MARK: - Manual Pose Application

    /// Set a specific bone's rotation
    /// 
    /// Uses VRMMetalKit's setLocalRotation API for thread-safe bone manipulation.
    private func setBonePose(_ model: VRMModel, bone: VRMHumanoidBone, rotation: simd_quatf) {
        model.setLocalRotation(rotation, for: bone)
    }

    /// Update world transforms after applying poses
    private func updatePoseTransforms(_ model: VRMModel) {
        let rootNodes = model.nodes.filter { $0.parent == nil }
        for root in rootNodes {
            root.updateWorldTransform()
        }
    }

    /// Apply T-Pose (arms extended horizontally)
    private func applyTPose(_ model: VRMModel) {
        // Arms extended horizontally to sides (90 degrees from body)
        let leftArmRotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))   // 90° roll
        let rightArmRotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 0, 1)) // -90° roll
        let straight = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) // Identity

        setBonePose(model, bone: .leftUpperArm, rotation: leftArmRotation)
        setBonePose(model, bone: .rightUpperArm, rotation: rightArmRotation)
        setBonePose(model, bone: .leftLowerArm, rotation: straight)
        setBonePose(model, bone: .rightLowerArm, rotation: straight)

        updatePoseTransforms(model)
    }

    /// Apply Arms Up Pose (arms raised above head)
    private func applyArmsUpPose(_ model: VRMModel) {
        // Arms raised straight up (180 degrees from default)
        let leftArmRotation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1))   // 180° roll
        let rightArmRotation = simd_quatf(angle: -.pi, axis: SIMD3<Float>(0, 0, 1)) // -180° roll
        let straight = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        setBonePose(model, bone: .leftUpperArm, rotation: leftArmRotation)
        setBonePose(model, bone: .rightUpperArm, rotation: rightArmRotation)
        setBonePose(model, bone: .leftLowerArm, rotation: straight)
        setBonePose(model, bone: .rightLowerArm, rotation: straight)

        updatePoseTransforms(model)
    }

    /// Apply Squat Pose (bend legs)
    private func applySquatPose(_ model: VRMModel) {
        // Bend hips and knees for squat position
        let hipsBend = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0))  // -45° pitch (lean forward)
        let kneeBend = simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0))   // 60° pitch (bend knees)

        setBonePose(model, bone: .hips, rotation: hipsBend)
        setBonePose(model, bone: .leftUpperLeg, rotation: kneeBend)
        setBonePose(model, bone: .rightUpperLeg, rotation: kneeBend)
        setBonePose(model, bone: .leftLowerLeg, rotation: kneeBend)
        setBonePose(model, bone: .rightLowerLeg, rotation: kneeBend)

        updatePoseTransforms(model)
    }

    /// Apply Neutral Pose (reset all bones)
    private func applyNeutralPose(_ model: VRMModel) {
        // Reset all bones to identity rotation
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        guard let humanoid = model.humanoid else { return }

        for bone in humanoid.humanBones.keys {
            setBonePose(model, bone: bone, rotation: identity)
        }

        updatePoseTransforms(model)
    }
}

// MARK: - MTKViewDelegate

extension VRMAvatarRenderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
        // Reapply current camera mode with new aspect ratio
        switch currentCameraMode {
        case .face:
            setCameraForFace()
        case .body:
            setCameraForBody()
        }
    }

    func draw(in view: MTKView) {
        guard let renderer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable
        else {
            return
        }

        // Only render if model is loaded
        guard isLoaded else {
            // Clear to background color
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            encoder?.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        // Update any animations here if needed
        // For MVP, we're just doing static pose + lip sync

        // Render
        renderer.draw(
            in: view,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Apply ARKit face tracking blend shapes to the VRM avatar
    ///
    /// Uses the ARKitFaceDriver for proper mapping, smoothing, and QoS management.
    ///
    /// - Parameter blendShapes: ARKit face blend shapes from VRMMetalKit
    func applyFaceTracking(blendShapes: ARKitFaceBlendShapes) {
        guard let expressionController else {
            #if DEBUG
            print("[VRMAvatarRenderer] No expression controller available for face tracking")
            #endif
            return
        }

        #if DEBUG
        print("[VRMAvatarRenderer] Applying face tracking - \(blendShapes.shapes.count) blend shapes, headTransform: \(blendShapes.headTransform != nil ? "yes" : "no")")
        #endif

        // Use ARKitFaceDriver to map, smooth, and apply blend shapes
        faceDriver.update(
            blendShapes: blendShapes,
            controller: expressionController
        )

        // Apply head transform if available
        if let headTransform = blendShapes.headTransform, let model = model {
            applyHeadTransform(headTransform, to: model)
        }
    }

    /// Apply head transform from ARKit face tracking to the VRM head bone
    ///
    /// Extracts rotation from the head transform matrix and applies it to the head bone.
    /// The ARKit transform is in world space; we only apply the rotation component.
    ///
    /// - Parameters:
    ///   - transform: 4x4 transform matrix from ARKit face anchor
    ///   - model: VRM model to apply the transform to
    private func applyHeadTransform(_ transform: simd_float4x4, to model: VRMModel) {
        guard let humanoid = model.humanoid,
              let headBone = humanoid.humanBones[.head],
              headBone.node >= 0 && headBone.node < model.nodes.count else {
            return
        }

        let headNode = model.nodes[headBone.node]

        // Extract rotation from transform matrix
        // The rotation is in the upper-left 3x3 portion
        let col0 = simd_make_float3(transform.columns.0)
        let col1 = simd_make_float3(transform.columns.1)
        let col2 = simd_make_float3(transform.columns.2)

        // Normalize the columns to remove any scale
        let rotationMatrix = simd_float3x3(
            normalize(col0),
            normalize(col1),
            normalize(col2)
        )

        // Convert to quaternion
        var rotation = simd_quatf(rotationMatrix)

        // ARKit face tracking coordinate conversion:
        // ARKit provides the face pose in camera space where:
        // - Looking up gives positive X rotation
        // - Looking right gives positive Y rotation
        // VRM expects:
        // - Looking up should tilt head back (negative X in VRM convention)
        // - Looking right should turn head right
        // We need to negate X (pitch) and Z (roll) to match VRM
        rotation = simd_quatf(
            ix: -rotation.imag.x,  // Negate pitch
            iy: rotation.imag.y,   // Keep yaw
            iz: -rotation.imag.z,  // Negate roll
            r: rotation.real
        )

        headNode.rotation = rotation
        headNode.updateLocalMatrix()

        // Update world transforms
        headNode.updateWorldTransform()
    }

    /// Apply face tracking from multiple sources (for multi-camera setup)
    ///
    /// - Parameters:
    ///   - sources: Array of face tracking sources (e.g., iPhone + iPad)
    ///   - priority: Strategy for selecting/merging sources (default: latest active)
    func applyFaceTracking(
        sources: [ARFaceSource],
        priority: SourcePriorityStrategy = .latestActive
    ) {
        guard let expressionController else {
            if updateCount == 0 {
                print("   ❌ [VRMAvatarRenderer] No expression controller, cannot apply face tracking")
            }
            return
        }

        // Log available expressions in the model (only once, not every frame)
        if let model = model, let expressions = model.expressions, updateCount == 0 {
            print("🎨 [VRMAvatarRenderer] First face tracking update - model has \(expressions.preset.count) expression presets")
            print("   💤 [VRMAvatarRenderer] Pausing idle animation for live face tracking")
            updateCount += 1
        }

        // Mark face tracking as active (pauses idle animation)
        faceTrackingActive = true
        lastFaceTrackingTime = CACurrentMediaTime()

        // Use ARKitFaceDriver with multi-source support
        faceDriver.update(
            sources: sources,
            controller: expressionController,
            priority: priority
        )

        // Apply head transform from the most active source
        if let model = model {
            // Find the most recent active source with a head transform
            let activeSources = sources.filter { $0.isActive }
            for source in activeSources.sorted(by: { $0.lastUpdate > $1.lastUpdate }) {
                if let blendShapes = source.blendShapes,
                   let headTransform = blendShapes.headTransform {
                    applyHeadTransform(headTransform, to: model)
                    break // Only apply from one source
                }
            }
        }
    }

    /// Reset face tracking filters (call when switching avatars or restarting)
    func resetFaceTracking() {
        faceDriver.resetFilters()
    }

    // Debug frame counter for logging
    private static var bodyTrackingLogCounter = 0

    /// Apply ARKit body tracking skeleton to the VRM avatar
    ///
    /// Uses the ARKitBodyDriver for proper mapping, smoothing, and skeleton retargeting.
    ///
    /// - Parameter skeleton: ARKit body skeleton from VRMMetalKit
    func applyBodyTracking(skeleton: ARKitBodySkeleton) {
        guard let model else {
            #if DEBUG
            print("[VRMAvatarRenderer] No model available for body tracking")
            #endif
            return
        }

        // Log hips input rotation every 60 frames
        Self.bodyTrackingLogCounter += 1
        let shouldLog = Self.bodyTrackingLogCounter % 60 == 0

        if shouldLog {
            if let hipsTransform = skeleton.joints[.hips] {
                // Extract rotation from matrix
                let col0 = simd_float3(hipsTransform.columns.0.x, hipsTransform.columns.0.y, hipsTransform.columns.0.z)
                let col1 = simd_float3(hipsTransform.columns.1.x, hipsTransform.columns.1.y, hipsTransform.columns.1.z)
                let col2 = simd_float3(hipsTransform.columns.2.x, hipsTransform.columns.2.y, hipsTransform.columns.2.z)
                let rotMatrix = simd_float3x3(simd_normalize(col0), simd_normalize(col1), simd_normalize(col2))
                let inputRot = simd_quatf(rotMatrix)
                print("[BodyTrack] Hips INPUT: w=\(String(format: "%.3f", inputRot.real)), x=\(String(format: "%.3f", inputRot.imag.x)), y=\(String(format: "%.3f", inputRot.imag.y)), z=\(String(format: "%.3f", inputRot.imag.z))")
            }
        }

        // Use ARKitBodyDriver to map, smooth, and apply skeleton
        bodyDriver.update(
            skeleton: skeleton,
            nodes: model.nodes,
            humanoid: model.humanoid
        )

        if shouldLog {
            // Log output rotation from VRM hips node
            if let humanoid = model.humanoid,
               let hipsBone = humanoid.humanBones[.hips],
               hipsBone.node >= 0 && hipsBone.node < model.nodes.count {
                let hipsNode = model.nodes[hipsBone.node]
                let outRot = hipsNode.rotation
                print("[BodyTrack] Hips OUTPUT: w=\(String(format: "%.3f", outRot.real)), x=\(String(format: "%.3f", outRot.imag.x)), y=\(String(format: "%.3f", outRot.imag.y)), z=\(String(format: "%.3f", outRot.imag.z))")
            }
        }
    }

    /// Apply body tracking from multiple sources (for multi-camera setup)
    ///
    /// - Parameters:
    ///   - sources: Array of body tracking sources (e.g., iPhone + iPad)
    ///   - priority: Strategy for selecting/merging sources (default: latest active)
    func applyBodyTracking(
        sources: [ARBodySource],
        priority: SourcePriorityStrategy = .latestActive
    ) {
        guard let model else {
            if updateCount == 0 {
                print("   ❌ [VRMAvatarRenderer] No model, cannot apply body tracking")
            }
            return
        }

        // Log available humanoid bones in the model (only once, not every frame)
        if model.humanoid != nil, updateCount == 0 {
            print("🦴 [VRMAvatarRenderer] First body tracking update - model has humanoid bones")
            updateCount += 1
        }

        // Convert sources to skeleton dictionary for updateMulti
        var skeletons: [String: ARKitBodySkeleton] = [:]
        for source in sources {
            if let skeleton = source.skeleton {
                skeletons[source.sourceID.uuidString] = skeleton
            }
        }

        // Use ARKitBodyDriver with multi-source support
        bodyDriver.updateMulti(
            skeletons: skeletons,
            nodes: model.nodes,
            humanoid: model.humanoid
        )

        // IMPORTANT: Center the avatar after body tracking
        // ARKit provides world-space positions which can move the model off-camera
        // We only want the relative bone rotations, not the absolute position
        centerAvatarHips(model)
    }

    /// Center the avatar by zeroing out hips translation
    ///
    /// ARKit body tracking provides world-space positions which can move the avatar
    /// out of the camera view. This method keeps the avatar centered by zeroing the
    /// X and Z translation while preserving Y (height) for jump/squat detection.
    ///
    /// Uses VRMMetalKit's setHipsTranslation API for thread-safe manipulation.
    private func centerAvatarHips(_ model: VRMModel) {
        // Get current hips translation
        guard let currentTranslation = model.getHipsTranslation() else {
            return
        }
        
        // Keep Y component for height variation (squat/jump)
        // Zero X and Z to keep avatar centered horizontally
        let centeredTranslation = SIMD3<Float>(0, currentTranslation.y, 0)
        model.setHipsTranslation(centeredTranslation)
    }

    /// Reset body tracking filters (call when switching avatars or restarting)
    func resetBodyTracking() {
        bodyDriver.resetFilters()
    }

    // MARK: - Offscreen Rendering for Recording

    /// Render the avatar to an offscreen texture for video capture
    /// - Parameters:
    ///   - colorTexture: Output color texture (BGRA format, .shared storage)
    ///   - depthTexture: Output depth texture (depth32Float)
    ///   - commandBuffer: Metal command buffer for rendering
    func renderToTexture(
        colorTexture: MTLTexture,
        depthTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let renderer, isLoaded else { return }

        // Create render pass descriptor for offscreen rendering
        let renderPassDescriptor = MTLRenderPassDescriptor()

        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 0 // Transparent background for compositing
        )

        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

        // Use VRMRenderer's offscreen rendering capability
        renderer.drawOffscreenHeadless(
            to: colorTexture,
            depth: depthTexture,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor
        )
    }
}
