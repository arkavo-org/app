//
//  AvatarViewModel.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Foundation
import ArkavoRecorder
import SwiftUI

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

    private final class MetadataObserverToken: @unchecked Sendable {
        let value: NSObjectProtocol
        init(_ value: NSObjectProtocol) {
            self.value = value
        }
    }

    // MARK: - Initialization

    init() {
        refreshModels()
        let observer = NotificationCenter.default.addObserver(
            forName: .cameraMetadataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.object as? CameraMetadataEvent,
                case let .arFace(faceMetadata) = event.metadata
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleFaceMetadata(faceMetadata)
            }
        }
        metadataObserver = MetadataObserverToken(observer)
    }

    deinit {
        if let observer = metadataObserver?.value {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Model Management

    func refreshModels() {
        downloadedModels = downloader.listDownloadedModels()
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

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

    private func handleFaceMetadata(_ metadata: ARFaceMetadata) {
        renderer?.applyFaceTracking(blendShapes: metadata.blendShapes)
        switch metadata.trackingState {
        case .normal:
            faceTrackingStatus = "Face tracking active"
        case .limited:
            faceTrackingStatus = "Tracking limited"
        case .notTracking:
            faceTrackingStatus = "Face not detected"
        case .unknown:
            faceTrackingStatus = "Awaiting face metadata"
        }
    }
}
