//
//  AvatarViewModel.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import ArkavoKit
import Foundation
import Metal
import SwiftUI
import VRMMetalKit

/// ViewModel for avatar recording and management
@MainActor
class AvatarViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var recordingMode: RecordingMode = .avatar
    @Published var downloadedModels: [URL] = []
    @Published var selectedModelURL: URL? {
        didSet {
            // Persist selection
            if let url = selectedModelURL {
                UserDefaults.standard.set(url.path, forKey: "lastSelectedAvatarModelPath")
            }
        }
    }
    @Published var backgroundColor: Color = .black
    @Published var avatarScale: Double = 1.0
    @Published var error: String?
    @Published var isLoading = false
    @Published var faceTrackingStatus: String = "Awaiting face metadata"
    @Published private(set) var isModelLoaded = false

    // Debug: Latest body skeleton for visualization
    @Published var latestBodySkeleton: ARKitBodySkeleton?

    // Debug: Latest face blend shapes for visualization
    @Published var latestFaceBlendShapes: ARKitFaceBlendShapes?

    // MARK: - Dependencies

    let downloader = VRMDownloader()

    weak var renderer: VRMAvatarRenderer?
    private var metadataObserver: MetadataObserverToken?
    private var hasAttemptedAutoLoad = false

    // VRM frame capture for recording
    private var captureManager: VRMFrameCaptureManager?

    // Multi-source face tracking management
    private var faceSources: [String: ARFaceSource] = [:]

    // Multi-source body tracking management
    private var bodySources: [String: ARBodySource] = [:]

    // Lifecycle state
    private var isActive = false

    private final class MetadataObserverToken: @unchecked Sendable {
        let value: NSObjectProtocol
        init(_ value: NSObjectProtocol) {
            self.value = value
        }
    }

    // MARK: - Initialization

    init() {
        refreshModels()
        print("[AvatarViewModel] Initializing - subscribing to face & body metadata notifications")
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
        print("[AvatarViewModel] Face & body tracking is ENABLED and ready to receive metadata")
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

        // Restore last selected model from persistence
        if selectedModelURL == nil,
           let savedPath = UserDefaults.standard.string(forKey: "lastSelectedAvatarModelPath") {
            let savedURL = URL(fileURLWithPath: savedPath)
            // Only restore if the file still exists
            if downloadedModels.contains(savedURL) {
                selectedModelURL = savedURL
                print("[AvatarViewModel] Restored last selected model: \(savedURL.lastPathComponent)")
            }
        }

        // Fallback: Auto-select first model if none selected
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

    /// Load the currently selected VRM model into the renderer
    func loadSelectedModel() async {
        guard let url = selectedModelURL, let renderer else {
            error = "No model selected or renderer not available"
            return
        }

        isLoading = true
        error = nil

        do {
            try await renderer.loadModel(from: url)
            isModelLoaded = true
            print("[AvatarViewModel] Model loaded successfully: \(url.lastPathComponent)")
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
            isModelLoaded = false
        }

        isLoading = false
    }

    /// Auto-load the last selected model if available (called when avatar mode activates)
    func autoLoadIfNeeded() async {
        // Only attempt auto-load once per session and if we have a selection
        guard !hasAttemptedAutoLoad,
              !isModelLoaded,
              selectedModelURL != nil,
              renderer != nil else {
            return
        }

        hasAttemptedAutoLoad = true
        print("[AvatarViewModel] Auto-loading last selected model...")
        await loadSelectedModel()
    }

    // MARK: - Lifecycle Management

    func activate() {
        isActive = true
        #if DEBUG
        print("▶️ [AvatarViewModel] Activated - will process metadata")
        #endif
    }

    func deactivate() {
        isActive = false
        #if DEBUG
        print("⏸️ [AvatarViewModel] Deactivated - will ignore metadata")
        #endif
    }

    // MARK: - Multi-Source Management

    private var logFrameCount = 0  // For throttling logs

    /// Handle camera metadata event with multi-source support
    ///
    /// This method manages multiple camera sources (e.g., iPhone + iPad)
    /// and uses the ARFaceSource infrastructure for proper multi-source handling.
    private func handleMetadataEvent(_ event: CameraMetadataEvent) {
        // Early exit if not active (avatar mode not visible)
        guard isActive else { return }

        let shouldLog = logFrameCount % 30 == 0  // Log every 30th frame (~1 per second at 30fps)
        logFrameCount += 1

        if shouldLog {
            print("🎭 [AvatarViewModel] handleMetadataEvent called for source: \(event.sourceID)")
        }

        // Handle face tracking metadata
        if case let .arFace(faceMetadata) = event.metadata {
            if shouldLog {
                print("   ✅ [AvatarViewModel] Face metadata received: \(faceMetadata.blendShapes.count) blend shapes")
            }

            // Get or create source for this camera
            let source = getOrCreateSource(for: event.sourceID)
            if shouldLog {
                print("   📍 [AvatarViewModel] Using face source: \(source.sourceID)")
            }

            // Convert and update source with new data
            let blendShapes = ARKitDataConverter.toARKitFaceBlendShapes(event)
            if let blendShapes {
                source.update(blendShapes: blendShapes)

                // Store for debug visualization
                latestFaceBlendShapes = blendShapes

                if shouldLog {
                    print("   📊 [AvatarViewModel] Updated source with \(blendShapes.shapes.count) blend shapes")

                    // Log key expression blend shapes for debugging
                    let eyeBlinkLeft = blendShapes.weight(for: "eyeBlinkLeft")
                    let eyeBlinkRight = blendShapes.weight(for: "eyeBlinkRight")
                    let mouthSmileLeft = blendShapes.weight(for: "mouthSmileLeft")
                    let mouthSmileRight = blendShapes.weight(for: "mouthSmileRight")
                    let browInnerUp = blendShapes.weight(for: "browInnerUp")
                    let browOuterUpLeft = blendShapes.weight(for: "browOuterUpLeft")
                    let browOuterUpRight = blendShapes.weight(for: "browOuterUpRight")
                    let jawOpen = blendShapes.weight(for: "jawOpen")

                    print("      └─ eyeBlinkL: \(String(format: "%.3f", eyeBlinkLeft)), eyeBlinkR: \(String(format: "%.3f", eyeBlinkRight))")
                    print("      └─ smileL: \(String(format: "%.3f", mouthSmileLeft)), smileR: \(String(format: "%.3f", mouthSmileRight))")
                    print("      └─ browInner: \(String(format: "%.3f", browInnerUp)), browOuter: \(String(format: "%.3f", (browOuterUpLeft + browOuterUpRight) / 2))")
                    print("      └─ jawOpen: \(String(format: "%.3f", jawOpen))")
                }
            } else {
                if shouldLog {
                    print("   ❌ [AvatarViewModel] Failed to convert to ARKitFaceBlendShapes")
                }
            }

            // Update renderer with all active sources
            let allSources = Array(faceSources.values)
            let activeSources = allSources.filter { $0.isActive }
            if shouldLog {
                print("   🎯 [AvatarViewModel] Applying face tracking: \(activeSources.count) active / \(allSources.count) total sources")
                print("      └─ Renderer exists: \(renderer != nil)")
            }
            renderer?.applyFaceTracking(sources: allSources, priority: .latestActive)
            if shouldLog {
                print("   ✅ [AvatarViewModel] Face tracking applied to renderer")
            }

            // Update status based on active sources
            updateTrackingStatus(faceMetadata.trackingState, sourceID: event.sourceID)
        }
        // Handle body tracking metadata
        else if case let .arBody(bodyMetadata) = event.metadata {
            if shouldLog {
                print("   🦴 [AvatarViewModel] Body metadata received: \(bodyMetadata.joints.count) joints")
            }

            // Get or create body source for this camera
            let source = getOrCreateBodySource(for: event.sourceID)
            if shouldLog {
                print("   📍 [AvatarViewModel] Using body source: \(source.sourceID)")
            }

            // Convert and update source with new data
            if let skeleton = ARKitDataConverter.toARKitBodySkeleton(event) {
                source.update(skeleton: skeleton)

                // Store latest skeleton for debug visualization
                latestBodySkeleton = skeleton

                if shouldLog {
                    print("   📊 [AvatarViewModel] Updated source with \(skeleton.joints.count) joint transforms")
                }
            } else {
                if shouldLog {
                    print("   ❌ [AvatarViewModel] Failed to convert to ARKitBodySkeleton")
                }
            }

            // Update renderer with all active body sources
            let allBodySources = Array(bodySources.values)
            let activeBodySources = allBodySources.filter { $0.isActive }
            if shouldLog {
                print("   🎯 [AvatarViewModel] Applying body tracking: \(activeBodySources.count) active / \(allBodySources.count) total sources")
                print("      └─ Renderer exists: \(renderer != nil)")
            }
            renderer?.applyBodyTracking(sources: allBodySources, priority: .latestActive)
            if shouldLog {
                print("   ✅ [AvatarViewModel] Body tracking applied to renderer")
            }
        }
        else {
            if shouldLog {
                print("   ⚠️  [AvatarViewModel] Received unknown metadata type, ignoring")
            }
        }
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

    private func getOrCreateBodySource(for sourceID: String) -> ARBodySource {
        if let existing = bodySources[sourceID] {
            return existing
        }

        // Create new source
        let source = ARBodySource(
            name: "Camera \(sourceID.prefix(8))",
            metadata: ["sourceID": sourceID]
        )
        bodySources[sourceID] = source
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
        bodySources = bodySources.filter { $0.value.isActive }
    }

    // MARK: - Recording Integration

    /// Connect avatar texture capture to a recording session
    /// - Parameter session: The recording session to connect to
    func connectToRecordingSession(_ session: RecordingSession) {
        guard let renderer else {
            print("[AvatarViewModel] Cannot connect to recording session - no renderer")
            return
        }

        // Initialize capture manager if needed
        if captureManager == nil {
            do {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    print("[AvatarViewModel] Failed to create Metal device for capture")
                    return
                }
                captureManager = try VRMFrameCaptureManager(device: device)
                captureManager?.renderer = renderer
                print("[AvatarViewModel] Created VRM capture manager")
            } catch {
                print("[AvatarViewModel] Failed to create capture manager: \(error)")
                return
            }
        }

        captureManager?.renderer = renderer

        // Start continuous capture so latestFrame is always available
        captureManager?.startCapture()

        // Set up the avatar texture provider for the recording session
        // Uses thread-safe latestFrame property that can be accessed from any actor
        let manager = captureManager
        session.avatarTextureProvider = {
            return manager?.latestFrame
        }

        print("[AvatarViewModel] Connected avatar capture to recording session")
    }

    /// Disconnect from recording session
    func disconnectFromRecordingSession(_ session: RecordingSession) {
        session.avatarTextureProvider = nil
        captureManager?.stopCapture()
        print("[AvatarViewModel] Disconnected avatar capture from recording session")
    }

    /// Start capturing avatar frames for streaming/preview
    func startCapture() {
        captureManager?.startCapture()
    }

    /// Stop capturing avatar frames
    func stopCapture() {
        captureManager?.stopCapture()
    }

    /// Returns a texture provider closure for use with RecordingSession
    /// Ensures capture is started and returns the latest frame
    func getTextureProvider() -> (@Sendable () -> CVPixelBuffer?)? {
        // Create capture manager if needed
        if captureManager == nil {
            guard let renderer else {
                print("[AvatarViewModel] getTextureProvider: No renderer available")
                return nil
            }

            do {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    print("[AvatarViewModel] getTextureProvider: Failed to create Metal device")
                    return nil
                }
                captureManager = try VRMFrameCaptureManager(device: device)
                captureManager?.renderer = renderer
                print("[AvatarViewModel] getTextureProvider: Created capture manager")
            } catch {
                print("[AvatarViewModel] getTextureProvider: Failed to create capture manager: \(error)")
                return nil
            }
        }

        guard let manager = captureManager else {
            print("[AvatarViewModel] getTextureProvider: No capture manager")
            return nil
        }

        // Start capture if not already running
        manager.startCapture()

        print("[AvatarViewModel] getTextureProvider: Returning provider")
        return { [weak manager] in
            manager?.latestFrame
        }
    }
}
