//
//  VRMFrameCaptureManager.swift
//  ArkavoCreator
//
//  Created for Issue #192 - Flexible Recording Input Combinations
//

import CoreVideo
import Foundation
@preconcurrency import Metal

/// Captures VRM avatar render output as CVPixelBuffer for recording
/// Uses offscreen Metal rendering at 30fps for video encoding
@MainActor
final class VRMFrameCaptureManager {
    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // Offscreen render targets
    private var colorTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private let renderSize: CGSize

    // Pixel buffer pool for efficient allocation
    private var pixelBufferPool: CVPixelBufferPool?

    // Timing
    private var frameTimer: Timer?
    private let targetFrameRate: Int

    // State
    private(set) var isCapturing = false

    // Thread-safe latest frame storage for cross-actor access
    // Using nonisolated(unsafe) because we protect access with NSLock
    private let latestFrameLock = NSLock()
    nonisolated(unsafe) private var _latestFrame: CVPixelBuffer?

    /// Thread-safe access to the latest captured frame
    /// Can be called from any thread/actor
    nonisolated var latestFrame: CVPixelBuffer? {
        latestFrameLock.lock()
        defer { latestFrameLock.unlock() }
        return _latestFrame
    }

    nonisolated private func storeLatestFrame(_ buffer: CVPixelBuffer?) {
        latestFrameLock.lock()
        _latestFrame = buffer
        latestFrameLock.unlock()
    }

    // Callbacks
    var onFrame: ((CVPixelBuffer) -> Void)?

    // Reference to renderer
    weak var renderer: VRMAvatarRenderer?

    // MARK: - Initialization

    /// Initialize the capture manager
    /// - Parameters:
    ///   - device: Metal device to use for rendering
    ///   - size: Output resolution (default 1080p)
    ///   - frameRate: Target frame rate (default 30fps)
    init(device: MTLDevice, size: CGSize = CGSize(width: 1920, height: 1080), frameRate: Int = 30) throws {
        self.device = device
        self.renderSize = size
        self.targetFrameRate = frameRate

        guard let queue = device.makeCommandQueue() else {
            throw VRMCaptureError.metalInitializationFailed
        }
        self.commandQueue = queue

        try createRenderTargets(size: size)
        try createPixelBufferPool(size: size)

        print("[VRMFrameCaptureManager] Initialized: \(Int(size.width))x\(Int(size.height))@\(frameRate)fps")
    }

    // Note: Timer cleanup happens automatically when the object is deallocated
    // since Timer holds a weak reference via the closure's [weak self].
    // The isCapturing flag prevents further frame processing.

    // MARK: - Public Methods

    /// Start capturing frames from the VRM renderer
    func startCapture() {
        guard !isCapturing else { return }
        guard renderer != nil else {
            print("[VRMFrameCaptureManager] Cannot start capture - no renderer set")
            return
        }

        isCapturing = true

        // Create timer for frame capture at target frame rate
        let interval = 1.0 / Double(targetFrameRate)
        frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureFrame()
            }
        }

        print("[VRMFrameCaptureManager] Started capture at \(targetFrameRate)fps")
    }

    /// Stop capturing frames
    func stopCapture() {
        guard isCapturing else { return }

        frameTimer?.invalidate()
        frameTimer = nil
        isCapturing = false

        print("[VRMFrameCaptureManager] Stopped capture")
    }

    /// Capture a single frame synchronously (for immediate use)
    /// - Returns: CVPixelBuffer containing the current avatar render, or nil if unavailable
    func captureTexture() -> CVPixelBuffer? {
        guard let renderer,
              let colorTexture,
              let depthTexture,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return nil
        }

        // Render VRM to offscreen texture
        renderer.renderToTexture(
            colorTexture: colorTexture,
            depthTexture: depthTexture,
            commandBuffer: commandBuffer
        )

        // Synchronize texture for CPU access (only needed for managed storage mode)
        // Shared storage mode doesn't need synchronization on Apple Silicon
        if colorTexture.storageMode == .managed,
           let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.synchronize(resource: colorTexture)
            blitEncoder.endEncoding()
        }

        // Commit and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Copy texture to pixel buffer
        return copyTextureToPixelBuffer(colorTexture)
    }

    // MARK: - Private Methods

    private func createRenderTargets(size: CGSize) throws {
        // Color texture (BGRA for compatibility with CVPixelBuffer)
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .shared // Required for CPU access

        guard let color = device.makeTexture(descriptor: colorDescriptor) else {
            throw VRMCaptureError.textureCreationFailed
        }
        colorTexture = color

        // Depth texture
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private

        guard let depth = device.makeTexture(descriptor: depthDescriptor) else {
            throw VRMCaptureError.textureCreationFailed
        }
        depthTexture = depth

        print("[VRMFrameCaptureManager] Created render targets: \(Int(size.width))x\(Int(size.height))")
    }

    private func createPixelBufferPool(size: CGSize) throws {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pixelBufferPool
        )

        guard status == kCVReturnSuccess else {
            throw VRMCaptureError.pixelBufferPoolCreationFailed
        }

        print("[VRMFrameCaptureManager] Created pixel buffer pool")
    }

    private func captureFrame() {
        guard isCapturing,
              let renderer,
              let colorTexture,
              let depthTexture,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        // Render VRM to offscreen texture
        renderer.renderToTexture(
            colorTexture: colorTexture,
            depthTexture: depthTexture,
            commandBuffer: commandBuffer
        )

        // Synchronize texture for CPU access (only needed for managed storage mode)
        // Shared storage mode doesn't need synchronization on Apple Silicon
        if colorTexture.storageMode == .managed,
           let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.synchronize(resource: colorTexture)
            blitEncoder.endEncoding()
        }

        // Capture texture reference for completion handler
        let texture = colorTexture

        commandBuffer.addCompletedHandler { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCapturing else { return }

                if let pixelBuffer = self.copyTextureToPixelBuffer(texture) {
                    // Store in thread-safe buffer for cross-actor access
                    self.storeLatestFrame(pixelBuffer)
                    self.onFrame?(pixelBuffer)
                }
            }
        }

        commandBuffer.commit()
    }

    private func copyTextureToPixelBuffer(_ texture: MTLTexture) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            print("[VRMFrameCaptureManager] Failed to create pixel buffer from pool")
            return nil
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pb) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )

        texture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )

        return pixelBuffer
    }
}

// MARK: - Errors

enum VRMCaptureError: Error, LocalizedError {
    case metalInitializationFailed
    case textureCreationFailed
    case pixelBufferPoolCreationFailed

    var errorDescription: String? {
        switch self {
        case .metalInitializationFailed:
            return "Failed to initialize Metal command queue"
        case .textureCreationFailed:
            return "Failed to create Metal render textures"
        case .pixelBufferPoolCreationFailed:
            return "Failed to create pixel buffer pool"
        }
    }
}
