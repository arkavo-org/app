//
//  VRMDownloader.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Foundation

/// Downloads VRM models from URLs (VRM Hub or direct .vrm files)
@MainActor
class VRMDownloader: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var error: Error?

    enum DownloadError: LocalizedError {
        case invalidURL
        case downloadFailed(Error)
        case invalidFileType
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Invalid URL. Please provide a valid VRM file URL."
            case let .downloadFailed(error):
                "Download failed: \(error.localizedDescription)"
            case .invalidFileType:
                "Invalid file type. Only .vrm files are supported."
            case .saveFailed:
                "Failed to save VRM file."
            }
        }
    }

    /// Downloads a VRM model from the given URL
    /// - Parameters:
    ///   - urlString: URL string pointing to a .vrm file
    /// - Returns: Local file URL of the downloaded model
    func downloadModel(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        // Validate it's a .vrm file URL
        guard url.pathExtension.lowercased() == "vrm" else {
            throw DownloadError.invalidFileType
        }

        isDownloading = true
        downloadProgress = 0.0
        error = nil

        defer {
            isDownloading = false
            downloadProgress = 0.0
        }

        do {
            // Download the file
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw DownloadError.downloadFailed(
                    NSError(domain: "VRMDownloader", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Server returned error",
                    ]),
                )
            }

            // Create destination URL in app documents directory
            let documentsPath = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask,
            )[0]

            let modelsDirectory = documentsPath.appendingPathComponent("VRMModels", isDirectory: true)

            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true,
            )

            // Generate filename from URL
            let filename = url.lastPathComponent
            let destinationURL = modelsDirectory.appendingPathComponent(filename)

            // Write file
            try data.write(to: destinationURL)

            downloadProgress = 1.0

            return destinationURL

        } catch {
            self.error = DownloadError.downloadFailed(error)
            throw DownloadError.downloadFailed(error)
        }
    }

    /// Lists all downloaded VRM models
    /// - Returns: Array of local VRM file URLs
    func listDownloadedModels() -> [URL] {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask,
        )[0]

        let modelsDirectory = documentsPath.appendingPathComponent("VRMModels", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil,
        ) else {
            return []
        }

        return files.filter { $0.pathExtension.lowercased() == "vrm" }
    }

    /// Deletes a downloaded VRM model
    /// - Parameter url: Local file URL of the model to delete
    func deleteModel(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
