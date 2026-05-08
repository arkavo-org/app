import Foundation
import Observation
import OSLog

/// State of model lifecycle
public enum ModelState: Equatable, Sendable {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)
    case unloaded(reason: String)
}

/// Manages MLX model lifecycle: download, load, unload, and memory budget.
@Observable
@MainActor
public final class ModelManager {
    private let logger = Logger(subsystem: "com.arkavo.musecore", category: "ModelManager")

    public private(set) var state: ModelState = .idle
    public private(set) var selectedModel: ModelInfo = ModelRegistry.defaultModel
    public private(set) var availableModels: [ModelInfo] = []

    private let backend: MLXBackend

    /// Monotonic counter — progress callbacks with a stale generation are ignored
    private var loadGeneration: Int = 0

    /// The MLX backend for streaming generation
    public var streamingProvider: MLXBackend { backend }

    /// Custom model cache directory (persisted via UserDefaults)
    public var customCacheDirectory: URL? {
        didSet {
            backend.customCacheDirectory = customCacheDirectory
            if let dir = customCacheDirectory {
                UserDefaults.standard.set(dir.path, forKey: "MLXModelCacheDirectory")
                logger.info("Custom cache directory set: \(dir.path)")
            } else {
                UserDefaults.standard.removeObject(forKey: "MLXModelCacheDirectory")
                logger.info("Custom cache directory cleared, using default")
            }
        }
    }

    public init() {
        backend = MLXBackend()

        // Restore persisted cache directory
        if let savedPath = UserDefaults.standard.string(forKey: "MLXModelCacheDirectory") {
            let url = URL(fileURLWithPath: savedPath)
            customCacheDirectory = url
            backend.customCacheDirectory = url
            logger.info("Restored custom cache directory: \(savedPath)")
        }

        refreshAvailableModels()
        logger.info("ModelManager init: \(self.availableModels.count) models available, default=\(self.selectedModel.displayName)")
        logger.info("Selected model cached: \(ModelRegistry.isModelCached(self.selectedModel))")

        // Auto-load the default model if it's already cached on disk
        if ModelRegistry.isModelCached(self.selectedModel) {
            logger.info("Auto-loading cached model: \(self.selectedModel.huggingFaceID)")
            Task { await self.loadSelectedModel() }
        } else {
            logger.info("Default model not cached, skipping auto-load")
        }
    }

    /// Refresh which models are available based on system memory
    public func refreshAvailableModels() {
        let systemMemoryMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        // Use 50% of system memory as budget for model loading
        let budgetMB = systemMemoryMB / 2
        availableModels = ModelRegistry.availableModels(memoryBudgetMB: budgetMB)
    }

    /// Select and load a model
    public func selectModel(_ model: ModelInfo) async {
        guard model != selectedModel || state != .ready else { return }

        selectedModel = model

        // Unload current model first
        if state == .ready {
            await unloadModel()
        }

        await loadSelectedModel()
    }

    /// Load the currently selected model
    public func loadSelectedModel() async {
        switch state {
        case .loading, .downloading, .ready:
            logger.info("loadSelectedModel: skipping, already in state \(String(describing: self.state))")
            return
        case .idle, .error, .unloaded:
            break
        }

        loadGeneration += 1
        let currentGeneration = loadGeneration
        let isCached = ModelRegistry.isModelCached(selectedModel)
        logger.info("loadSelectedModel: \(self.selectedModel.huggingFaceID), cached=\(isCached), generation=\(currentGeneration)")
        state = isCached ? .loading : .downloading(progress: 0)

        do {
            try await backend.loadModel(selectedModel.huggingFaceID) { [weak self] progress in
                guard !isCached else { return }
                Task { @MainActor in
                    guard let self, self.loadGeneration == currentGeneration else { return }
                    self.state = .downloading(progress: progress)
                }
            }
            guard loadGeneration == currentGeneration else {
                logger.warning("loadSelectedModel: generation mismatch, discarding")
                return
            }
            state = .loading
            await Task.yield()
            state = .ready
            logger.info("loadSelectedModel: model ready")
        } catch {
            guard loadGeneration == currentGeneration else { return }
            logger.error("loadSelectedModel: failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// Unload the model to free GPU memory
    public func unloadModel() async {
        backend.unloadModel()
        state = .idle
    }

    /// Unload with a reason (e.g., entering Studio)
    public func unloadModel(reason: String) async {
        backend.unloadModel()
        state = .unloaded(reason: reason)
    }

    /// Whether the model is ready for generation
    public var isReady: Bool {
        state == .ready
    }

    /// System memory in GB
    public var systemMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }

    /// Whether the selected model is cached locally
    public var isSelectedModelCached: Bool {
        ModelRegistry.isModelCached(selectedModel)
    }
}
