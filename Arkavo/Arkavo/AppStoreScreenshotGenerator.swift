import AVFoundation
import SwiftUI
import UIKit

@MainActor
class AppStoreScreenshotGenerator: NSObject {
    private enum Dimensions {
        case size1290x2796
        case size1320x2868

        var size: CGSize {
            switch self {
            case .size1290x2796:
                CGSize(width: 1290, height: 2796)
            case .size1320x2868:
                CGSize(width: 1320, height: 2868)
            }
        }
    }

    private let window: UIWindow
    private var captureTimer: Timer?
    private var autoStopTimer: Timer?
    private var screenshotCount = 0
    private let maxScreenshots = 10
    private var screenshotDirectory: URL?
    private let targetDimensions: Dimensions = .size1290x2796

    init(window: UIWindow) {
        self.window = window
        super.init()
    }

    private func captureVideoFrame(_ playerLayer: AVPlayerLayer) async -> (UIImage, CGRect)? {
        guard let player = playerLayer.player else { return nil }

        guard let asset = player.currentItem?.asset,
              let track = asset.tracks(withMediaType: .video).first
        else {
            return nil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = player.currentTime()

        do {
            let cgImage = try await generator.image(at: time).image
            return (UIImage(cgImage: cgImage), playerLayer.frame)
        } catch {
            print("Error capturing video frame: \(error)")
            return nil
        }
    }

    @MainActor
    private func captureScreenshot() async {
        guard let directory = screenshotDirectory else { return }

        // First capture video frames
        let videoLayers = findVideoLayers(in: window)
        pausePlayingVideos()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Capture video frames before creating the screenshot
        var videoFrames: [(UIImage, CGRect)] = []
        for layer in videoLayers {
            if let frameData = await captureVideoFrame(layer) {
                videoFrames.append(frameData)
            }
        }

        // Create the screenshot with composited video frames
        let screenshot = await withCheckedContinuation { continuation in
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                // Draw the base window content
                window.layoutIfNeeded()
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)

                // Draw each video frame
                for (videoFrame, frame) in videoFrames {
                    videoFrame.draw(in: frame)
                }
            }
            continuation.resume(returning: image)
        }

        resumePlayingVideos()

        // Scale down to target size
        let resizedImage = await scaleImage(screenshot, to: targetDimensions.size)

        // Save to disk
        await Task.detached {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                .replacingOccurrences(of: ":", with: "-")
            let filename = await "screenshot_\(self.screenshotCount + 1)_\(timestamp).png"
            let fileURL = directory.appendingPathComponent(filename)

            if let data = resizedImage.pngData() {
                do {
                    try data.write(to: fileURL)
                    await print("Saved screenshot \(self.screenshotCount + 1): \(filename)")
                } catch {
                    print("Error saving screenshot: \(error)")
                }
            }
        }.value
    }

    @MainActor
    private func scaleImage(_ image: UIImage, to targetSize: CGSize) async -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func pausePlayingVideos() {
        findVideoLayers(in: window).forEach { $0.player?.pause() }
    }

    private func resumePlayingVideos() {
        findVideoLayers(in: window).forEach { $0.player?.play() }
    }

    private func findVideoLayers(in view: UIView) -> [AVPlayerLayer] {
        var layers: [AVPlayerLayer] = []

        if let playerLayer = view.layer as? AVPlayerLayer {
            layers.append(playerLayer)
        }

        if let sublayers = view.layer.sublayers {
            layers.append(contentsOf: sublayers.compactMap { $0 as? AVPlayerLayer })
        }

        for subview in view.subviews {
            layers.append(contentsOf: findVideoLayers(in: subview))
        }

        return layers
    }

    private func createScreenshotDirectory() -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let size = targetDimensions.size
        let dirName = "AppStore_Screenshots_\(Int(size.width))x\(Int(size.height))_\(timestamp)"
        let dirURL = documentsURL.appendingPathComponent(dirName)

        try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }

    func startCapturing() {
        screenshotDirectory = createScreenshotDirectory()

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopCapturing()
            }
        }

        captureTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                if self.screenshotCount >= self.maxScreenshots {
                    self.stopCapturing()
                    return
                }

                await self.captureScreenshot()
                self.screenshotCount += 1
            }
        }

        print("Screenshot capture started. Will automatically stop in 2 minutes.")
        print("Target dimensions: \(targetDimensions.size.width) × \(targetDimensions.size.height)")
    }

    func stopCapturing() {
        captureTimer?.invalidate()
        captureTimer = nil
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        print("Screenshot capture completed. Total screenshots: \(screenshotCount)")

        if let directory = screenshotDirectory {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                shareDirectory(directory)
            }
        }
    }

    @MainActor
    private func shareDirectory(_ directory: URL) {
        guard let windowScene = window.windowScene,
              let rootViewController = windowScene.windows.first?.rootViewController
        else {
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [directory],
            applicationActivities: nil
        )

        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = rootViewController.view
            popoverController.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                                  y: rootViewController.view.bounds.midY,
                                                  width: 0, height: 0)
        }

        rootViewController.present(activityVC, animated: true)
    }
}

struct ScreenshotExportButton: View {
    let screenshotGenerator: AppStoreScreenshotGenerator?

    var body: some View {
        Button("Export Screenshots") {
            screenshotGenerator?.stopCapturing()
        }
    }
}

@MainActor
class WindowAccessor: ObservableObject {
    @Published var window: UIWindow?
    static let shared = WindowAccessor()

    private init() {}

    func setupWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.window = UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }

    func updateWindow() {
        window = UIApplication.shared.windows.first { $0.isKeyWindow }
    }
}
