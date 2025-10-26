import Metal
import MetalKit
import CoreVideo
import CoreImage
@preconcurrency import AVFoundation

/// Manages Metal-based composition of screen and camera frames for picture-in-picture
public final class CompositorManager: Sendable {
    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext

    // PiP configuration
    nonisolated(unsafe) public var pipPosition: PiPPosition = .bottomRight
    nonisolated(unsafe) public var pipScale: Float = 0.2 // 20% of screen size

    // MARK: - Initialization

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RecorderError.encodingFailed
        }

        guard let commandQueue = device.makeCommandQueue() else {
            throw RecorderError.encodingFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device)
    }

    // MARK: - Public Methods

    /// Composites screen and camera frames into a single frame with PiP layout
    public func composite(
        screen screenBuffer: CMSampleBuffer,
        camera cameraBuffer: CMSampleBuffer?
    ) -> CVPixelBuffer? {
        // Get screen image buffer
        guard let screenPixelBuffer = CMSampleBufferGetImageBuffer(screenBuffer) else {
            return nil
        }

        // If no camera, return screen only
        guard let cameraBuffer = cameraBuffer,
              let cameraPixelBuffer = CMSampleBufferGetImageBuffer(cameraBuffer) else {
            return screenPixelBuffer
        }

        // Create CIImages
        let screenImage = CIImage(cvPixelBuffer: screenPixelBuffer)
        let cameraImage = CIImage(cvPixelBuffer: cameraPixelBuffer)

        // Calculate PiP dimensions and position
        let screenSize = screenImage.extent.size
        let pipSize = CGSize(
            width: screenSize.width * CGFloat(pipScale),
            height: screenSize.height * CGFloat(pipScale)
        )

        // Scale camera to PiP size maintaining aspect ratio
        let cameraAspect = cameraImage.extent.width / cameraImage.extent.height
        let pipAspect = pipSize.width / pipSize.height

        var scaledCameraSize = pipSize
        if cameraAspect > pipAspect {
            // Camera is wider, fit width
            scaledCameraSize.height = pipSize.width / cameraAspect
        } else {
            // Camera is taller, fit height
            scaledCameraSize.width = pipSize.height * cameraAspect
        }

        let scaleX = scaledCameraSize.width / cameraImage.extent.width
        let scaleY = scaledCameraSize.height / cameraImage.extent.height
        let scaledCamera = cameraImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Calculate position based on PiP setting
        let position = calculatePiPPosition(
            screenSize: screenSize,
            pipSize: scaledCameraSize,
            position: pipPosition
        )

        // Position the camera overlay
        let positionedCamera = scaledCamera.transformed(by: CGAffineTransform(translationX: position.x, y: position.y))

        // Add rounded corners and border to PiP
        let pipWithEffects = addPiPEffects(to: positionedCamera, size: scaledCameraSize)

        // Composite the images
        let composited = pipWithEffects.composited(over: screenImage)

        // Render to pixel buffer
        return renderToPixelBuffer(image: composited, size: screenSize)
    }

    // MARK: - Private Methods

    private func calculatePiPPosition(
        screenSize: CGSize,
        pipSize: CGSize,
        position: PiPPosition
    ) -> CGPoint {
        let margin: CGFloat = 20

        switch position {
        case .topLeft:
            return CGPoint(x: margin, y: screenSize.height - pipSize.height - margin)
        case .topRight:
            return CGPoint(x: screenSize.width - pipSize.width - margin, y: screenSize.height - pipSize.height - margin)
        case .bottomLeft:
            return CGPoint(x: margin, y: margin)
        case .bottomRight:
            return CGPoint(x: screenSize.width - pipSize.width - margin, y: margin)
        }
    }

    private func addPiPEffects(to image: CIImage, size: CGSize) -> CIImage {
        // Add rounded corners
        let cornerRadius: CGFloat = 12

        // Create rounded rectangle mask
        let maskRect = CGRect(origin: .zero, size: size)
        let mask = CIImage(color: CIColor.white)
            .cropped(to: maskRect)
            .applyingFilter("CIBoxBlur", parameters: ["inputRadius": cornerRadius])

        // Apply mask
        let maskedImage = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: CIColor.clear).cropped(to: image.extent),
            kCIInputMaskImageKey: mask
        ])

        // Add subtle border/shadow
        // This is a simplified version - could be enhanced with CIFilter effects
        return maskedImage
    }

    private func renderToPixelBuffer(image: CIImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = pixelBuffer else {
            return nil
        }

        ciContext.render(image, to: outputBuffer)
        return outputBuffer
    }
}

// MARK: - Supporting Types

public enum PiPPosition: String, Sendable, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    public var id: String { rawValue }
}
