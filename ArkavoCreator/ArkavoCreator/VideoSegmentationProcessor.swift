import AVFoundation
import CoreImage
import CoreML
import UniformTypeIdentifiers
import Vision

public class VideoSegmentationProcessor {
    private let model: DETRResnet50SemanticSegmentationF16
    private let context = CIContext()

    public struct FrameSegmentation: Sendable {
        public let timestamp: TimeInterval
        public let segmentation: MLShapedArray<Int32>
        public let frameImage: CGImage

        fileprivate init(timestamp: TimeInterval, segmentation: MLShapedArray<Int32>, frameImage: CGImage) {
            self.timestamp = timestamp
            self.segmentation = segmentation
            self.frameImage = frameImage
        }
    }

    public enum ProcessingError: Error {
        case modelInitializationFailed
        case videoAccessFailed
        case frameExtractionFailed
        case segmentationFailed
        case invalidVideoURL
    }

    public init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        do {
            model = try DETRResnet50SemanticSegmentationF16(configuration: configuration)
        } catch {
            throw ProcessingError.modelInitializationFailed
        }
    }

    public func processVideo(url: URL,
                             frameInterval: TimeInterval = 1.0,
                             progressHandler _: @escaping @Sendable (Double) -> Void) async throws -> [FrameSegmentation]
    {
        // Verify file exists and is readable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path)
        else {
            throw ProcessingError.invalidVideoURL
        }

        // Create AVAsset using modern initialization
        let asset = AVURLAsset(url: url)

        // Get video duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Create image generator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        // Calculate frame times
        var times: [CMTime] = []
        var currentTime: Double = 0
        while currentTime < durationSeconds {
            times.append(CMTime(seconds: currentTime, preferredTimescale: 600))
            currentTime += frameInterval
        }

        // Process frames
        var results: [FrameSegmentation] = []

        for (index, time) in times.enumerated() {
            do {
                // Extract frame
                let cgImage = try await generator.image(at: time).image

                // Create input for the model
                let input = try DETRResnet50SemanticSegmentationF16Input(imageWith: cgImage)

                // Perform prediction
                let output = try await model.prediction(input: input)

                // Store result
                results.append(FrameSegmentation(
                    timestamp: CMTimeGetSeconds(time),
                    segmentation: output.semanticPredictionsShapedArray,
                    frameImage: cgImage
                ))

                // Report progress
                let progress = Double(index + 1) / Double(times.count)
                await MainActor.run {
//                    progressHandler?(progress)
                    print("progress \(progress)")
                }

            } catch {
                print("Error processing frame at \(CMTimeGetSeconds(time))s: \(error)")
                // Continue processing other frames
                continue
            }
        }

        return results
    }

    public func analyzeSegmentations(_ segmentations: [FrameSegmentation],
                                     threshold: Float = 0.8) -> [(TimeInterval, Float)]
    {
        var significantChanges: [(TimeInterval, Float)] = []

        // Skip if we have less than 2 frames
        guard segmentations.count >= 2 else { return [] }

        // Compare consecutive frames
        for i in 0 ..< (segmentations.count - 1) {
            let current = segmentations[i].segmentation
            let next = segmentations[i + 1].segmentation

            // Calculate similarity between consecutive frames
            var similarity: Float = 0
            var totalPixels = 0

            // Compare segmentation maps
            for y in 0 ..< 448 {
                for x in 0 ..< 448 {
                    if current[y, x] == next[y, x] {
                        similarity += 1
                    }
                    totalPixels += 1
                }
            }

            let similarityScore = similarity / Float(totalPixels)

            // If similarity is below threshold, record the timestamp
            if similarityScore < threshold {
                significantChanges.append((segmentations[i].timestamp, similarityScore))
            }
        }

        return significantChanges
    }

    // Helper method to save processed frames
    public func saveFrameWithSegmentation(_ frame: FrameSegmentation,
                                          toDirectory directory: URL,
                                          withPrefix prefix: String = "frame") throws
    {
        // Create visualization of segmentation
        let width = 448
        let height = 448
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        // Define colors for different classes
        let colors: [[UInt8]] = [
            [255, 0, 0, 255], // Red
            [0, 255, 0, 255], // Green
            [0, 0, 255, 255], // Blue
            [255, 255, 0, 255], // Yellow
            [255, 0, 255, 255], // Magenta
            [0, 255, 255, 255], // Cyan
        ]
        let scalarArray = frame.segmentation.scalars
        // Create segmentation visualization
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = y * width + x
                let classIndex = Int(scalarArray[index])
                let color = colors[classIndex % colors.count]
                let pixelIndex = index * bytesPerPixel

                pixelData[pixelIndex] = color[0] // R
                pixelData[pixelIndex + 1] = color[1] // G
                pixelData[pixelIndex + 2] = color[2] // B
                pixelData[pixelIndex + 3] = color[3] // A
            }
        }

        let data = CFDataCreate(nil, &pixelData, pixelData.count)!
        let provider = CGDataProvider(data: data)!

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let segmentationImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw ProcessingError.segmentationFailed
        }

        // Create blended image using correct filter chain
        let ciOriginal = CIImage(cgImage: frame.frameImage)
        let ciSegmentation = CIImage(cgImage: segmentationImage)

        // Scale segmentation to match original if needed
        let scaledSegmentation = ciSegmentation.transformed(by: CGAffineTransform(
            scaleX: CGFloat(frame.frameImage.width) / CGFloat(segmentationImage.width),
            y: CGFloat(frame.frameImage.height) / CGFloat(segmentationImage.height)
        ))

        // Create multiply blend filter for opacity
        guard let multiplyFilter = CIFilter(name: "CIColorMatrix") else {
            throw ProcessingError.segmentationFailed
        }

        multiplyFilter.setValue(scaledSegmentation, forKey: kCIInputImageKey)
        // Set alpha channel to 0.5 using color matrix
        multiplyFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        multiplyFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        multiplyFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        multiplyFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.5), forKey: "inputAVector")

        guard let adjustedSegmentation = multiplyFilter.outputImage else {
            throw ProcessingError.segmentationFailed
        }

        // Blend the images
        guard let blendFilter = CIFilter(name: "CISourceOverCompositing") else {
            throw ProcessingError.segmentationFailed
        }

        blendFilter.setValue(adjustedSegmentation, forKey: kCIInputImageKey)
        blendFilter.setValue(ciOriginal, forKey: kCIInputBackgroundImageKey)

        guard let outputImage = blendFilter.outputImage,
              let blendedImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            throw ProcessingError.segmentationFailed
        }

        // Save the blended image using modern UTType
        let timestamp = String(format: "%.2f", frame.timestamp)
        let fileURL = directory.appendingPathComponent("\(prefix)_\(timestamp).jpg")

        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ProcessingError.segmentationFailed
        }

        CGImageDestinationAddImage(destination, blendedImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw ProcessingError.segmentationFailed
        }
    }
}

public class VideoSceneDetector {
    private let segmentationProcessor: VideoSegmentationProcessor
    private let similarityThreshold: Float

    public init(configuration: MLModelConfiguration = MLModelConfiguration(),
                similarityThreshold: Float = 0.8) throws
    {
        segmentationProcessor = try VideoSegmentationProcessor(configuration: configuration)
        self.similarityThreshold = similarityThreshold
    }

    // Process video and generate metadata
    public func generateMetadata(for videoURL: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let segmentations = try await segmentationProcessor.processVideo(url: videoURL) { progress in
            print("Processing progress: \(Int(progress * 100))%")
        }

        var significantScenes: [SceneSegmentationData] = []

        for segmentation in segmentations {
            let sceneData = try await processSegmentation(segmentation)

            // Check if this is a significant scene
            if shouldIncludeScene(sceneData, previousScene: significantScenes.last) {
                significantScenes.append(sceneData)
            }
        }

        return VideoMetadata(
            videoId: videoURL.lastPathComponent,
            duration: durationSeconds,
            significantScenes: significantScenes
        )
    }

    // Process a single frame's segmentation
    public func processSegmentation(_ segmentation: VideoSegmentationProcessor.FrameSegmentation) async throws -> SceneSegmentationData {
        var classCount: [Int: Int] = [:]
        let scalarArray = segmentation.segmentation.scalars

        // Count occurrences of each class
        for value in scalarArray {
            let classId = Int(value)
            classCount[classId, default: 0] += 1
        }

        // Get dominant classes
        let dominantClasses = classCount.sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        return SceneSegmentationData(
            timestamp: segmentation.timestamp,
            classDistribution: classCount,
            dominantClasses: dominantClasses,
            totalPixels: scalarArray.count
        )
    }

    // Determine if a scene is significantly different from the previous one
    private func shouldIncludeScene(_ current: SceneSegmentationData, previousScene: SceneSegmentationData?) -> Bool {
        guard let previous = previousScene else {
            return true // Always include first scene
        }

        // Compare class distributions
        let similarity = VideoSceneDetector.calculateDistributionSimilarity(
            current.classDistribution,
            previous.classDistribution,
            totalPixels: current.totalPixels
        )

        return similarity < similarityThreshold
    }

    // Calculate similarity between two class distributions
    private static func calculateDistributionSimilarity(_ dist1: [Int: Int], _ dist2: [Int: Int], totalPixels: Int) -> Float {
        var commonPixels = 0

        for (classId, count1) in dist1 {
            let count2 = dist2[classId] ?? 0
            commonPixels += min(count1, count2)
        }

        return Float(commonPixels) / Float(totalPixels)
    }

    // Real-time comparison against reference metadata
    public actor SceneMatchDetector {
        private var referenceMetadata: [VideoMetadata]
        private let similarityThreshold: Float

        public init(referenceMetadata: [VideoMetadata], similarityThreshold: Float = 0.8) {
            self.referenceMetadata = referenceMetadata
            self.similarityThreshold = similarityThreshold
        }

        public func addReferenceVideo(_ metadata: VideoMetadata) {
            referenceMetadata.append(metadata)
        }

        public func findMatches(for scene: SceneSegmentationData) -> [SceneMatch] {
            var matches: [SceneMatch] = []

            for reference in referenceMetadata {
                for refScene in reference.significantScenes {
                    let similarity = calculateSceneSimilarity(scene, refScene)

                    if similarity >= similarityThreshold {
                        matches.append(SceneMatch(
                            sourceTimestamp: scene.timestamp,
                            matchedVideoId: reference.videoId,
                            matchedTimestamp: refScene.timestamp,
                            similarity: similarity
                        ))
                    }
                }
            }

            return matches
        }

        private func calculateSceneSimilarity(_ scene1: SceneSegmentationData, _ scene2: SceneSegmentationData) -> Float {
            calculateDistributionSimilarity(
                scene1.classDistribution,
                scene2.classDistribution,
                totalPixels: scene1.totalPixels
            )
        }
    }
}

// Serializable metadata structures
public struct SceneSegmentationData: Codable, Sendable {
    public let timestamp: TimeInterval
    public let classDistribution: [Int: Int] // Class ID to pixel count
    public let dominantClasses: [Int] // Top 3 most common classes
    public let totalPixels: Int

    public var description: String {
        "Scene at \(String(format: "%.2f", timestamp))s - Top classes: \(dominantClasses)"
    }
}

public struct VideoMetadata: Codable, Sendable {
    public let videoId: String
    public let duration: TimeInterval
    public let significantScenes: [SceneSegmentationData]
    public let processingDate: Date

    public init(videoId: String, duration: TimeInterval, significantScenes: [SceneSegmentationData], processingDate: Date = Date()) {
        self.videoId = videoId
        self.duration = duration
        self.significantScenes = significantScenes
        self.processingDate = processingDate
    }
}

public struct SceneMatch: Sendable {
    public let sourceTimestamp: TimeInterval
    public let matchedVideoId: String
    public let matchedTimestamp: TimeInterval
    public let similarity: Float
}
