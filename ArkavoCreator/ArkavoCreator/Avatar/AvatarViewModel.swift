//
//  AvatarViewModel.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Foundation
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

    // MARK: - Dependencies

    let downloader = VRMDownloader()

    // MARK: - Initialization

    init() {
        refreshModels()
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
}
