import Foundation
import AVFoundation
import AppKit
import ArkavoSocial
import ArkavoMediaKit
// C2PA support temporarily disabled
// import ArkavoC2PA

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
    var tdfStatus: TDFProtectionStatus?
    var irohStatus: IrohPublishStatus = .unpublished

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

    /// TDF3 protection status for FairPlay streaming
    enum TDFProtectionStatus: Sendable {
        case protected(tdfURL: URL, protectedAt: Date)
        case unprotected
        case unknown

        var isProtected: Bool {
            if case .protected = self {
                return true
            }
            return false
        }

        var tdfURL: URL? {
            if case .protected(let url, _) = self {
                return url
            }
            return nil
        }
    }

    /// Iroh P2P publish status for TDF content
    enum IrohPublishStatus: Sendable {
        case unpublished
        case publishing
        case published(ticket: ContentTicket)
        case failed(String)

        var isPublished: Bool {
            if case .published = self {
                return true
            }
            return false
        }

        var contentTicket: ContentTicket? {
            if case .published(let ticket) = self {
                return ticket
            }
            return nil
        }
    }

    /// URL of the TDF3 archive (ZIP containing manifest.json + 0.payload)
    var tdfURL: URL {
        url.deletingPathExtension().appendingPathExtension("tdf")
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
    @Published private(set) var needsFolderSelection = false

    private var recordingsDirectory: URL

    init() {
        // Check if we have a bookmarked folder, otherwise we'll need user to select one
        if let folder = RecordingsFolderAccess.getBookmarkedFolder() {
            recordingsDirectory = folder
            debugLog("📂 [RecordingsManager] recordingsDirectory: \(recordingsDirectory.path)")
        } else {
            // Use sandboxed container as temporary fallback until user selects folder
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            recordingsDirectory = documentsURL.appendingPathComponent("Recordings", isDirectory: true)
            needsFolderSelection = true
            debugLog("📂 [RecordingsManager] no folder selected, using fallback: \(recordingsDirectory.path)")
        }

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

    func selectRecordingsFolder() async {
        if let folder = await RecordingsFolderAccess.chooseRecordingsFolder() {
            recordingsDirectory = folder
            needsFolderSelection = false
            debugLog("📂 [RecordingsManager] user selected: \(folder.path)")
            await loadRecordings()
        }
    }

    func loadRecordings() async {
        // Start security-scoped access for the recordings directory
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            debugLog("Error loading recordings: Cannot access recordings directory")
            recordings = []
            return
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            let mediaFiles = fileURLs.filter { $0.pathExtension == "mov" || $0.pathExtension == "m4a" }

            var loadedRecordings: [Recording] = []
            for url in mediaFiles {
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
            debugLog("Error loading recordings: \(error)")
            recordings = []
        }
    }

    func deleteRecording(_ recording: Recording) {
        // Start security-scoped access on the directory (the bookmark is on the directory, not individual files)
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            debugLog("Error deleting recording: Cannot access recordings directory")
            return
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

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
            debugLog("Error deleting recording: \(error)")
        }
    }

    func generateThumbnail(for recording: Recording) async -> NSImage? {
        // Start security-scoped access on the directory (the bookmark is on the directory, not individual files)
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            debugLog("Error generating thumbnail: Cannot access recordings directory")
            return nil
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        let asset = AVURLAsset(url: recording.url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let (cgImage, _) = try await imageGenerator.image(at: .zero)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            debugLog("Error generating thumbnail: \(error)")
            return nil
        }
    }

    func verifyC2PA(for recording: Recording) async -> Recording.C2PAStatus {
        // C2PA verification temporarily disabled - c2patool not available
        // TODO: Re-enable when c2patool is bundled with the app
        return .unsigned
    }

    /// Check TDF protection status for a recording
    func checkTDFStatus(for recording: Recording) async -> Recording.TDFProtectionStatus {
        let tdfURL = recording.tdfURL

        // Check if TDF archive exists
        if FileManager.default.fileExists(atPath: tdfURL.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: tdfURL.path),
               let modDate = attrs[.modificationDate] as? Date
            {
                return .protected(tdfURL: tdfURL, protectedAt: modDate)
            }
            return .protected(tdfURL: tdfURL, protectedAt: Date())
        }
        return .unprotected
    }

    /// Protect a recording with TDF3 for FairPlay streaming
    func protectRecording(_ recording: Recording, kasURL: URL) async throws {
        // Capture URLs before detaching (for Sendable safety)
        let videoURL = recording.url
        let tdfURL = recording.tdfURL
        let assetID = recording.id.uuidString
        let title = recording.title

        // Start security-scoped access on the directory (the bookmark is on the directory, not individual files)
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access recordings folder - please re-select the recordings folder"]
            )
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        // Load video data (potentially large file)
        debugLog("📂 Loading video data from: \(videoURL.path)")
        let videoData = try Data(contentsOf: videoURL)
        debugLog("📂 Loaded \(videoData.count) bytes")

        // Create protection service and encrypt
        let protectionService = RecordingProtectionService(kasURL: kasURL)
        debugLog("🔐 Starting TDF3 protection...")
        let tdfArchive = try await protectionService.protectVideo(
            videoData: videoData,
            assetID: assetID
        )
        debugLog("✅ TDF archive created: \(tdfArchive.count) bytes")

        // Write TDF archive
        try tdfArchive.write(to: tdfURL)
        debugLog("💾 Protected recording: \(title)")
        debugLog("💾 TDF archive: \(tdfURL.path)")
    }

    /// Protect a recording with HLS segmentation for streaming playback
    func protectRecordingHLS(_ recording: Recording, kasURL: URL) async throws {
        // Capture URLs before detaching (for Sendable safety)
        let videoURL = recording.url
        let tdfURL = recording.tdfURL
        let assetID = recording.id.uuidString
        let title = recording.title

        // Start security-scoped access on the directory (the bookmark is on the directory, not individual files)
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access recordings folder - please re-select the recordings folder"]
            )
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        // Create HLS protection service
        let protectionService = HLSRecordingProtectionService(kasURL: kasURL)
        debugLog("🎬 Starting HLS TDF protection for: \(title)")

        // Convert to HLS and package into TDF
        let tdfArchive = try await protectionService.protectVideoHLS(
            videoURL: videoURL,
            assetID: assetID
        )
        debugLog("✅ HLS TDF archive created: \(tdfArchive.count) bytes")

        // Write TDF archive
        try tdfArchive.write(to: tdfURL)
        debugLog("💾 Protected HLS recording: \(title)")
        debugLog("💾 TDF archive: \(tdfURL.path)")
    }

    /// Protect a recording with fMP4/CBCS for true FairPlay hardware DRM
    func protectRecordingFMP4(_ recording: Recording, kasURL: URL) async throws {
        // Capture URLs before detaching (for Sendable safety)
        let videoURL = recording.url
        let tdfURL = recording.tdfURL
        let assetID = recording.id.uuidString
        let title = recording.title

        // Start security-scoped access on the directory
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access recordings folder - please re-select the recordings folder"]
            )
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        // Create fMP4 protection service
        let protectionService = FMP4RecordingProtectionService(kasURL: kasURL)
        debugLog("🎬 Starting fMP4 FairPlay protection for: \(title)")

        // Convert to fMP4/CBCS and package into TDF
        let tdfArchive = try await protectionService.protectVideo(
            videoURL: videoURL,
            assetID: assetID
        )
        debugLog("✅ fMP4 TDF archive created: \(tdfArchive.count) bytes")

        // Write TDF archive
        try tdfArchive.write(to: tdfURL)
        debugLog("💾 Protected fMP4 recording: \(title)")
        debugLog("💾 TDF archive: \(tdfURL.path)")
    }
}

