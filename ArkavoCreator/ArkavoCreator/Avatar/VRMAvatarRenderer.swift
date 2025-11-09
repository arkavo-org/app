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
    private var model: VRMModel?
    private var expressionController: VRMExpressionController? {
        renderer?.expressionController
    }

    // ARKit face tracking driver
    private let faceDriver: ARKitFaceDriver

    private(set) var isLoaded = false
    private(set) var error: Error?

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

        super.init()

        // Initialize renderer with standard 3D mode (not Toon2D)
        let vrmRenderer = VRMRenderer(device: device)
        vrmRenderer.renderingMode = .standard  // Use standard 3D MToon rendering
        renderer = vrmRenderer

        print("[VRMAvatarRenderer] Initialized with standard 3D rendering mode and ARKit driver")
        setupCamera()
    }

    // MARK: - Model Loading

    func loadModel(from url: URL) async throws {
        isLoaded = false
        error = nil

        do {
            print("[VRMAvatarRenderer] Loading model from: \(url.path)")

            // Load VRM model
            let vrmModel = try await VRMModel.load(from: url, device: device)
            model = vrmModel

            print("[VRMAvatarRenderer] Model loaded successfully, nodes: \(vrmModel.nodes.count)")

            // Load into renderer
            renderer?.loadModel(vrmModel)

            print("[VRMAvatarRenderer] Model loaded into renderer")

            isLoaded = true
        } catch {
            print("[VRMAvatarRenderer] Failed to load model: \(error)")
            self.error = error
            isLoaded = false
            throw error
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        guard let renderer else { return }

        // Set up perspective projection - tighter FOV for face focus
        let fov: Float = 35.0 * .pi / 180.0  // Narrower FOV for portrait-style framing
        let aspect: Float = 16.0 / 9.0
        let near: Float = 0.1
        let far: Float = 100.0

        renderer.projectionMatrix = perspectiveMatrix(
            fov: fov,
            aspect: aspect,
            near: near,
            far: far,
        )

        // Set up view matrix - positioned for face tracking
        // Camera positioned in front of avatar face, zoomed in for AR face tracking proportions
        // VRM models typically face -Z, so camera is at negative Z to see the front
        let eye = SIMD3<Float>(0, 1.45, -1.0)    // Eye level height (lowered camera to see higher), 1.0 unit away on -Z
        let center = SIMD3<Float>(0, 1.45, 0)    // Look at eye level (center of screen)
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
}

// MARK: - MTKViewDelegate

extension VRMAvatarRenderer: MTKViewDelegate {
    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
        // Handle resize if needed
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
            print("[VRMAvatarRenderer] No expression controller available for face tracking")
            return
        }

        print("[VRMAvatarRenderer] Applying face tracking - \(blendShapes.shapes.count) blend shapes")

        // Use ARKitFaceDriver to map, smooth, and apply blend shapes
        faceDriver.update(
            blendShapes: blendShapes,
            controller: expressionController
        )
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
        guard let expressionController else { return }

        // Use ARKitFaceDriver with multi-source support
        faceDriver.update(
            sources: sources,
            controller: expressionController,
            priority: priority
        )
    }

    /// Reset face tracking filters (call when switching avatars or restarting)
    func resetFaceTracking() {
        faceDriver.resetFilters()
    }
}
