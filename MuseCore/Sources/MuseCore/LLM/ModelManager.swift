import Foundation
import Observation

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
    public private(set) var state: ModelState = .idle
    public private(set) var selectedModel: ModelInfo = ModelRegistry.defaultModel
    public private(set) var availableModels: [ModelInfo] = []

    private let backend: MLXBackend

    /// The backend used by this manager — pass to AssistantViewModel
    public var streamingProvider: MLXBackend { backend }

    public init() {
        backend = MLXBackend()
        refreshAvailableModels()
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
        guard state != .loading else { return }

        state = .loading

        do {
            try await backend.loadModel(selectedModel.huggingFaceID)
            state = .ready
        } catch {
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
