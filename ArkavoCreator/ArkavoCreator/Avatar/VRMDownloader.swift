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
        case vrmHubAuthRequired
        case noDownloadLinkFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Invalid URL. Please provide a valid VRM file URL or VRM Hub model URL."
            case let .downloadFailed(error):
                "Download failed: \(error.localizedDescription)"
            case .invalidFileType:
                "Invalid file type. Only .vrm files are supported."
            case .saveFailed:
                "Failed to save VRM file."
            case .vrmHubAuthRequired:
                "VRM Hub downloads require authentication. Please download manually and use a direct .vrm file URL."
            case .noDownloadLinkFound:
                "Could not find download link on VRM Hub page. Model may require authentication."
            }
        }
    }

    /// Downloads a VRM model from the given URL
    /// - Parameters:
    ///   - urlString: URL string pointing to a .vrm file or VRM Hub model page
    /// - Returns: Local file URL of the downloaded model
    func downloadModel(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        isDownloading = true
        downloadProgress = 0.0
        error = nil

        defer {
            isDownloading = false
            downloadProgress = 0.0
        }

        // Check if this is a VRM Hub URL
        if url.host?.contains("hub.vroid.com") == true {
            return try await downloadFromVRMHub(url)
        }

        // Direct .vrm file download
        guard url.pathExtension.lowercased() == "vrm" else {
            throw DownloadError.invalidFileType
        }

        return try await downloadDirectVRM(from: url)
    }

    /// Downloads a VRM file directly from a URL
    private func downloadDirectVRM(from url: URL) async throws -> URL {
        do {
            // Download the file
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw DownloadError.downloadFailed(
                    NSError(domain: "VRMDownloader", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Server returned error",
                    ])
                )
            }

            return try saveVRMFile(data: data, filename: url.lastPathComponent)

        } catch {
            self.error = DownloadError.downloadFailed(error)
            throw DownloadError.downloadFailed(error)
        }
    }

    /// Attempts to download from VRM Hub
    private func downloadFromVRMHub(_ url: URL) async throws -> URL {
        // Extract model ID from URL
        // URL format: https://hub.vroid.com/en/characters/{characterId}/models/{modelId}
        let pathComponents = url.pathComponents
        guard let modelIdIndex = pathComponents.lastIndex(of: "models"),
              modelIdIndex + 1 < pathComponents.count
        else {
            throw DownloadError.invalidURL
        }

        let modelId = pathComponents[modelIdIndex + 1]

        // Try to construct download URL
        // VRM Hub typically uses: https://api.vroid.com/models/{modelId}/download
        let downloadURLString = "https://api.vroid.com/models/\(modelId)/download"

        guard let downloadURL = URL(string: downloadURLString) else {
            throw DownloadError.invalidURL
        }

        do {
            var request = URLRequest(url: downloadURL)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DownloadError.downloadFailed(
                    NSError(domain: "VRMDownloader", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid response",
                    ])
                )
            }

            // Check if authentication is required (401/403)
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw DownloadError.vrmHubAuthRequired
            }

            guard httpResponse.statusCode == 200 else {
                throw DownloadError.downloadFailed(
                    NSError(domain: "VRMDownloader", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)",
                    ])
                )
            }

            // Generate filename from model ID
            let filename = "model_\(modelId).vrm"
            return try saveVRMFile(data: data, filename: filename)

        } catch let error as DownloadError {
            self.error = error
            throw error
        } catch {
            self.error = DownloadError.downloadFailed(error)
            throw DownloadError.downloadFailed(error)
        }
    }

    /// Saves VRM data to local file
    private func saveVRMFile(data: Data, filename: String) throws -> URL {
        // Create destination URL in app documents directory
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let modelsDirectory = documentsPath.appendingPathComponent("VRMModels", isDirectory: true)

        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        let destinationURL = modelsDirectory.appendingPathComponent(filename)

        // Write file
        try data.write(to: destinationURL)

        downloadProgress = 1.0

        return destinationURL
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
