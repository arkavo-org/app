//
//  MuseAvatarRenderer.swift
//  ArkavoCreator
//
//  AI-driven VRM avatar renderer using MuseCore's procedural animation system.
//  Produces CVPixelBuffer frames for streaming/recording via VRMFrameCaptureManager.
//

import Foundation
import Metal
import MetalKit
import MuseCore
import simd
import VRMMetalKit

/// Wraps VRMMetalKit renderer with MuseCore's procedural animation system
/// for AI-driven avatar rendering in the streaming pipeline.
@MainActor
class MuseAvatarRenderer: NSObject {
    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderer: VRMRenderer?
    private var _model: VRMModel?

    var model: VRMModel? { _model }

    private var expressionController: VRMExpressionController? {
        renderer?.expressionController
    }

    // MuseCore animation system
    let animationController = ProceduralAnimationController()
    private let lipSyncCoordinator = LipSyncCoordinator()
    private let audioAnalyzer = AudioAnalyzer()
    private let clipLibrary = VRMAClipLibrary()

    // Frame timing
    private var lastFrameTime: CFTimeInterval = 0

    // State
    private(set) var isLoaded = false
    private(set) var error: Error?
    private(set) var isPaused = false
    weak var mtkView: MTKView?

    // MARK: - Initialization

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        super.init()

        let vrmRenderer = VRMRenderer(device: device)
        renderer = vrmRenderer

        // Wire up MuseCore dependencies
        animationController.configure(
            lipSync: lipSyncCoordinator,
            audio: audioAnalyzer,
            clips: clipLibrary
        )

        setupCamera()
    }

    // MARK: - Model Loading

    func loadModel(from url: URL) async throws {
        isLoaded = false
        error = nil

        do {
            let vrmModel = try await VRMModel.load(from: url, device: device)
            _model = vrmModel

            renderer?.loadModel(vrmModel)

            // Setup MuseCore animation system with the model
            animationController.setup(
                model: vrmModel,
                expressionController: expressionController
            )

            // Load VRMA clips for idle animations and emotes
            await animationController.loadClips()

            isLoaded = true
            lastFrameTime = CACurrentMediaTime()
        } catch {
            self.error = error
            isLoaded = false
            throw error
        }
    }

    // MARK: - Lifecycle

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        mtkView?.isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        mtkView?.isPaused = false
        lastFrameTime = CACurrentMediaTime()
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        setCameraForBody()
    }

    /// Full body camera framing for streaming
    func setCameraForBody() {
        guard let renderer else { return }

        let fov: Float = 45.0 * .pi / 180.0
        let drawableSize = mtkView?.drawableSize ?? CGSize(width: 1920, height: 1080)
        let aspect: Float = drawableSize.width > 0 && drawableSize.height > 0
            ? Float(drawableSize.width / drawableSize.height)
            : 16.0 / 9.0

        renderer.projectionMatrix = perspectiveMatrix(
            fov: fov, aspect: aspect, near: 0.1, far: 100.0
        )

        let eye = SIMD3<Float>(0, 0.9, -2.2)
        let center = SIMD3<Float>(0, 0.9, 0)
        let up = SIMD3<Float>(0, 1, 0)
        renderer.viewMatrix = lookAtMatrix(eye: eye, center: center, up: up)
    }

    /// Face close-up camera framing
    func setCameraForFace() {
        guard let renderer else { return }

        let fov: Float = 35.0 * .pi / 180.0
        let drawableSize = mtkView?.drawableSize ?? CGSize(width: 1920, height: 1080)
        let aspect: Float = drawableSize.width > 0 && drawableSize.height > 0
            ? Float(drawableSize.width / drawableSize.height)
            : 16.0 / 9.0

        renderer.projectionMatrix = perspectiveMatrix(
            fov: fov, aspect: aspect, near: 0.1, far: 100.0
        )

        let eye = SIMD3<Float>(0, 1.45, -1.0)
        let center = SIMD3<Float>(0, 1.45, 0)
        let up = SIMD3<Float>(0, 1, 0)
        renderer.viewMatrix = lookAtMatrix(eye: eye, center: center, up: up)
    }

    // MARK: - Animation Control

    /// Set conversation state for animation system
    func setConversationState(_ state: AvatarConversationState) {
        animationController.setConversationState(state)
    }

    /// Prepare lip sync for upcoming speech
    @discardableResult
    func prepareLipSync(text: String) -> Double {
        lipSyncCoordinator.prepare(text: text)
    }

    /// Start lip sync playback
    func startLipSync() {
        lipSyncCoordinator.startSync()
    }

    /// Stop lip sync playback
    func stopLipSync() {
        lipSyncCoordinator.stop()
    }

    /// Set sentiment expression
    func setSentiment(_ preset: VRMExpressionPreset, intensity: Float) {
        animationController.setSentiment(preset, intensity: intensity)
    }

    /// Trigger an emote animation
    func triggerEmote(_ emote: EmoteAnimationLayer.Emote) {
        animationController.triggerEmote(emote)
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
            SIMD4<Float>(0, 0, wzScale, 0)
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
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
}

// MARK: - MTKViewDelegate

extension MuseAvatarRenderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
        setCameraForBody()
    }

    func draw(in view: MTKView) {
        guard let renderer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable
        else { return }

        guard isLoaded else {
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            encoder?.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        // Calculate delta time
        let now = CACurrentMediaTime()
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now

        // Update procedural animation system
        animationController.update(deltaTime: min(deltaTime, 0.1))

        // Render
        renderer.draw(
            in: view,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Render to offscreen texture for video capture
    func renderToTexture(
        colorTexture: MTLTexture,
        depthTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let renderer, isLoaded else { return }

        // Update animation before rendering
        let now = CACurrentMediaTime()
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        animationController.update(deltaTime: min(deltaTime, 0.1))

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 0
        )

        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

        renderer.drawOffscreenHeadless(
            to: colorTexture,
            depth: depthTexture,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor
        )
    }
}
