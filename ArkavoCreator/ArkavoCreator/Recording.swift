import Foundation
import AVFoundation
import AppKit
import ArkavoC2PA

// MARK: - Notification Names

extension Notification.Name {
    static let recordingCompleted = Notification.Name("recordingCompleted")
    static let cameraMetadataUpdated = Notification.Name("cameraMetadataUpdated")
}

/// Represents a recorded video file
struct Recording: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let date: Date
    let duration: TimeInterval
    let fileSize: Int64
    let thumbnailPath: URL?
    var c2paStatus: C2PAStatus?

    enum C2PAStatus: Sendable {
        case signed(validatedAt: Date, isValid: Bool)
        case unsigned
        case unknown

        var isSigned: Bool {
            if case .signed = self {
                return true
            }
            return false
        }

        var isValid: Bool {
            if case .signed(_, let valid) = self {
                return valid
            }
            return false
        }
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Manages recordings on disk
@MainActor
final class RecordingsManager: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    private let recordingsDirectory: URL

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingsDirectory = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        // Listen for recording completed notifications
        NotificationCenter.default.addObserver(
            forName: .recordingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadRecordings()
            }
        }

        Task {
            await loadRecordings()
        }
    }

    func loadRecordings() async {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            let movFiles = fileURLs.filter { $0.pathExtension == "mov" }

            var loadedRecordings: [Recording] = []
            for url in movFiles {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let fileSize = attributes[.size] as? Int64,
                      let creationDate = attributes[.creationDate] as? Date else {
                    continue
                }

                // Get video duration using modern API
                let asset = AVURLAsset(url: url)
                let duration: TimeInterval
                do {
                    let durationValue = try await asset.load(.duration)
                    duration = durationValue.seconds
                } catch {
                    duration = 0
                }

                // Extract title from metadata or use filename
                let title = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "arkavo_recording_", with: "")
                    .replacingOccurrences(of: "_", with: " ")

                let recording = Recording(
                    id: UUID(),
                    url: url,
                    title: title,
                    date: creationDate,
                    duration: duration.isNaN ? 0 : duration,
                    fileSize: fileSize,
                    thumbnailPath: nil, // Will be generated on demand
                    c2paStatus: .unknown // Will be checked on demand
                )
                loadedRecordings.append(recording)
            }

            recordings = loadedRecordings.sorted { $0.date > $1.date } // Most recent first

        } catch {
            print("Error loading recordings: \(error)")
            recordings = []
        }
    }

    func deleteRecording(_ recording: Recording) {
        do {
            try FileManager.default.removeItem(at: recording.url)

            // Delete thumbnail if exists
            if let thumbnailPath = recording.thumbnailPath {
                try? FileManager.default.removeItem(at: thumbnailPath)
            }

            Task {
                await loadRecordings()
            }
        } catch {
            print("Error deleting recording: \(error)")
        }
    }

    func generateThumbnail(for recording: Recording) async -> NSImage? {
        let asset = AVURLAsset(url: recording.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let (cgImage, _) = try await imageGenerator.image(at: .zero)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }

    func verifyC2PA(for recording: Recording) async -> Recording.C2PAStatus {
        do {
            let signer = try C2PASigner()
            let result = try await signer.verify(file: recording.url)

            if result.hasManifest {
                return .signed(validatedAt: Date(), isValid: result.isValid)
            } else {
                return .unsigned
            }
        } catch {
            print("Error verifying C2PA: \(error)")
            return .unknown
        }
    }
}
