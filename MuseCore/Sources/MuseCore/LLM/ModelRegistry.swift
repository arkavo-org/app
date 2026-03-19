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
            id: "gemma-3-270m",
            displayName: "Gemma 3 270M",
            huggingFaceID: "mlx-community/gemma-3-270m-it-bf16",
            estimatedMemoryMB: 906,
            parameterCount: "270M",
            quantization: "bf16"
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

    /// The default model (smallest, already cached)
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
    /// MLX uses `Caches/models/<org>/<repo>` via the system caches directory,
    /// which resolves correctly inside the App Sandbox container.
    public static func isModelCached(_ model: ModelInfo) -> Bool {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let modelDir = cachesURL
            .appendingPathComponent("models")
            .appendingPathComponent(model.huggingFaceID)
        return FileManager.default.fileExists(atPath: modelDir.path)
    }
}
