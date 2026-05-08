import Foundation

/// Catalog of supported MLX models with metadata
public struct ModelInfo: Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let huggingFaceID: String
    public let estimatedMemoryMB: Int
    public let parameterCount: String
    public let quantization: String

    public init(
        id: String,
        displayName: String,
        huggingFaceID: String,
        estimatedMemoryMB: Int,
        parameterCount: String,
        quantization: String
    ) {
        self.id = id
        self.displayName = displayName
        self.huggingFaceID = huggingFaceID
        self.estimatedMemoryMB = estimatedMemoryMB
        self.parameterCount = parameterCount
        self.quantization = quantization
    }
}

/// Registry of available MLX models
public enum ModelRegistry {
    /// All supported models, ordered by size
    public static let models: [ModelInfo] = [
        ModelInfo(
            id: "gemma-4-e4b",
            displayName: "Gemma 4 E4B",
            huggingFaceID: "mlx-community/gemma-4-e4b-it-8bit",
            estimatedMemoryMB: 9000,
            parameterCount: "8B (4B active MoE)",
            quantization: "8-bit"
        ),
        ModelInfo(
            id: "qwen3.5-0.8b",
            displayName: "Qwen 3.5 0.8B",
            huggingFaceID: "mlx-community/Qwen3.5-0.8B",
            estimatedMemoryMB: 1600,
            parameterCount: "0.8B",
            quantization: "bf16"
        ),
        ModelInfo(
            id: "qwen3.5-9b",
            displayName: "Qwen 3.5 9B",
            huggingFaceID: "mlx-community/Qwen3.5-9B",
            estimatedMemoryMB: 18000,
            parameterCount: "9B",
            quantization: "bf16"
        ),
    ]

    /// The default model
    public static let defaultModel = models[0]

    /// Find a model by its ID
    public static func model(forID id: String) -> ModelInfo? {
        models.first { $0.id == id }
    }

    /// Models that fit within the given memory budget (in MB)
    public static func availableModels(memoryBudgetMB: Int) -> [ModelInfo] {
        models.filter { $0.estimatedMemoryMB <= memoryBudgetMB }
    }

    /// Check if a model's files exist in the local cache.
    ///
    /// HuggingFace's `HubCache` lays models out as
    /// `<cacheDir>/huggingface/hub/models--<org>--<repo>` (slashes in the repo
    /// id replaced with `--`). Two locations may apply:
    ///   1. The user's home cache: `~/.cache/huggingface/hub/...`
    ///   2. The app sandbox cache: `Library/Caches/huggingface/hub/...`
    /// Either presence counts as cached so we don't redundantly re-download.
    public static func isModelCached(_ model: ModelInfo) -> Bool {
        let folder = "models--" + model.huggingFaceID.replacingOccurrences(of: "/", with: "--")
        let candidates = cacheCandidateURLs().map {
            $0.appendingPathComponent("huggingface")
              .appendingPathComponent("hub")
              .appendingPathComponent(folder)
        }
        return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func cacheCandidateURLs() -> [URL] {
        var urls: [URL] = []
        if let sandbox = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            urls.append(sandbox)
        }
        // ~/.cache — used by the system Python HF client; we share this cache
        // when the user runs models outside the app, per project memory.
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".cache"))
        return urls
    }
}
