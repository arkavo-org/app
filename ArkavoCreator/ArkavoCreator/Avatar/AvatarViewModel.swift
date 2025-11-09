//
//  AvatarViewModel.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Foundation
import ArkavoRecorder
import ArkavoRecorderShared
import SwiftUI
import VRMMetalKit

/// ViewModel for avatar recording and management
@MainActor
class AvatarViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var recordingMode: RecordingMode = .avatar
    @Published var downloadedModels: [URL] = []
    @Published var selectedModelURL: URL?
    @Published var backgroundColor: Color = .green
    @Published var avatarScale: Double = 1.0
    @Published var error: String?
    @Published var isLoading = false
    @Published var faceTrackingStatus: String = "Awaiting face metadata"

    // MARK: - Dependencies

    let downloader = VRMDownloader()

    weak var renderer: VRMAvatarRenderer?
    private var metadataObserver: MetadataObserverToken?

    // Multi-source face tracking management
    private var faceSources: [String: ARFaceSource] = [:]

    private final class MetadataObserverToken: @unchecked Sendable {
        let value: NSObjectProtocol
        init(_ value: NSObjectProtocol) {
            self.value = value
        }
    }

    // MARK: - Initialization

    init() {
        refreshModels()
        print("[AvatarViewModel] Initializing - subscribing to face metadata notifications")
        let observer = NotificationCenter.default.addObserver(
            forName: .cameraMetadataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CameraMetadataEvent else {
                print("[AvatarViewModel] Received notification but couldn't cast to CameraMetadataEvent")
                return
            }
            Task { @MainActor [weak self] in
                // Use multi-source path for better support
                self?.handleMetadataEvent(event)
            }
        }
        metadataObserver = MetadataObserverToken(observer)
        print("[AvatarViewModel] Face tracking is ENABLED and ready to receive metadata")
    }

    deinit {
        if let observer = metadataObserver?.value {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Model Management

    func refreshModels() {
        let models = downloader.listDownloadedModels()
        print("[AvatarViewModel] Found \(models.count) VRM models:")
        for model in models {
            print("  - \(model.lastPathComponent) at \(model.path)")
        }
        downloadedModels = models.sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Auto-select first model if none selected
        if selectedModelURL == nil, let first = downloadedModels.first {
            selectedModelURL = first
        }
    }

    func downloadModel(from urlString: String) async {
        isLoading = true
        error = nil

        do {
            let localURL = try await downloader.downloadModel(from: urlString)
            refreshModels()
            selectedModelURL = localURL
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func deleteModel(_ url: URL) {
        do {
            try downloader.deleteModel(at: url)
            refreshModels()

            // Clear selection if deleted model was selected
            if selectedModelURL == url {
                selectedModelURL = downloadedModels.first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func attachRenderer(_ renderer: VRMAvatarRenderer?) {
        self.renderer = renderer
    }

    // MARK: - Multi-Source Management

    /// Handle camera metadata event with multi-source support
    ///
    /// This method manages multiple camera sources (e.g., iPhone + iPad)
    /// and uses the ARFaceSource infrastructure for proper multi-source handling.
    private func handleMetadataEvent(_ event: CameraMetadataEvent) {
        guard case let .arFace(faceMetadata) = event.metadata else {
            print("[AvatarViewModel] Received non-face metadata, ignoring")
            return
        }

        print("[AvatarViewModel] Received face metadata from source: \(event.sourceID.prefix(8))")

        // Get or create source for this camera
        let source = getOrCreateSource(for: event.sourceID)

        // Convert and update source with new data
        let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(event)
        if let blendShapes {
            source.update(blendShapes: blendShapes)
            print("[AvatarViewModel] Updated source with \(blendShapes.shapes.count) blend shapes")
        }

        // Update renderer with all active sources
        let allSources = Array(faceSources.values)
        let activeSources = allSources.filter { $0.isActive }
        print("[AvatarViewModel] Applying face tracking with \(activeSources.count) active sources")
        renderer?.applyFaceTracking(sources: allSources, priority: .latestActive)

        // Update status based on active sources
        updateTrackingStatus(faceMetadata.trackingState, sourceID: event.sourceID)
    }

    private func getOrCreateSource(for sourceID: String) -> ARFaceSource {
        if let existing = faceSources[sourceID] {
            return existing
        }

        // Create new source
        let source = ARFaceSource(
            name: "Camera \(sourceID.prefix(8))",
            metadata: ["sourceID": sourceID]
        )
        faceSources[sourceID] = source
        return source
    }

    private func updateTrackingStatus(_ state: ARFaceTrackingState, sourceID: String) {
        let activeSources = faceSources.values.filter { $0.isActive }
        let sourceCount = activeSources.count

        if sourceCount == 0 {
            faceTrackingStatus = "No active face tracking"
        } else if sourceCount == 1 {
            switch state {
            case .normal:
                faceTrackingStatus = "Face tracking active"
            case .limited:
                faceTrackingStatus = "Tracking limited"
            case .notTracking:
                faceTrackingStatus = "Face not detected"
            case .unknown:
                faceTrackingStatus = "Awaiting face metadata"
            }
        } else {
            faceTrackingStatus = "Multi-camera tracking (\(sourceCount) sources)"
        }
    }

    /// Remove inactive sources (called periodically or on source disconnect)
    func cleanupInactiveSources() {
        faceSources = faceSources.filter { $0.value.isActive }
    }
}
