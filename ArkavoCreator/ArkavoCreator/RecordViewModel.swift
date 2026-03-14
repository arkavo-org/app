// C2PA signing pending c2pa-opentdf-rs integration
// import ArkavoC2PA
import ArkavoKit
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI
import VideoToolbox

@MainActor
@Observable
final class RecordViewModel {
    // MARK: - Recording State

    private(set) var recordingSession: RecordingSession?
    var isRecording: Bool = false
    var isPaused: Bool = false
    var duration: TimeInterval = 0.0
    var audioLevel: Float = 0.0

    // Configuration
    var title: String = ""
    var pipPosition: PiPPosition = .bottomRight
    var enableCamera: Bool = true
    var enableMicrophone: Bool = true
    var enableDesktop: Bool = true
    var enableAvatar: Bool = false
    var avatarTextureProvider: (@Sendable () -> CVPixelBuffer?)?
    var museTextureProvider: (@Sendable () -> CVPixelBuffer?)?
    var availableCameras: [CameraInfo] = []
    var selectedCameraIDs: [String] = []
    var cameraLayout: MultiCameraLayout = .pictureInPicture
    var floatingHeadEnabled: Bool = false {
        didSet {
            // Update session in real-time when toggle changes
            recordingSession?.floatingHeadEnabled = floatingHeadEnabled
        }
    }
    var remoteBridgeEnabled: Bool = FeatureFlags.remoteCameraBridge
    var remoteBridgePort: String = "0"  // 0 = auto-assign available port
    var remoteCameraSources: [String] = []
    private(set) var actualPort: UInt16 = 0  // The actual port being used
    private var previewStore: CameraPreviewStore?
    private var hasInitializedSession = false
    private var remoteCameraServer: RemoteCameraServer?

    // Desktop/Screen selection
    var desktopPreviewImage: NSImage?
    var availableScreens: [ScreenInfo] = []
    var selectedScreenID: CGDirectDisplayID?

    // Watermark configuration (always enabled, no UI toggle)
    var watermarkEnabled: Bool = true
    var watermarkPosition: WatermarkPosition = .bottomCenter
    var watermarkOpacity: Float = 0.6

    // Status
    var error: String?
    var isProcessing: Bool = false

    /// Validation: at least one input must be enabled to start recording
    var canStartRecording: Bool {
        enableDesktop || enableCamera || enableAvatar || enableMicrophone
    }

    // Timer for updating duration
    private var timer: Timer?

    // Security-scoped resource for recordings folder (held during recording)
    private var scopedFolderURL: URL?

    // Desktop audio
    var enableDesktopAudio: Bool = false
    var desktopAudioLevel: Float = 0.0
    var micVolume: Float = 1.0 {
        didSet { recordingSession?.setAudioGain(micVolume, for: "microphone") }
    }
    var desktopAudioVolume: Float = 1.0 {
        didSet { recordingSession?.setAudioGain(desktopAudioVolume, for: "screen") }
    }

    // Standalone audio level monitor (always-on, independent of recording)
    nonisolated(unsafe) private var audioMonitorSession: AVCaptureSession?
    private var audioMonitorOutput: AVCaptureAudioDataOutput?
    private let audioMonitorQueue = DispatchQueue(label: "com.arkavo.audioMonitor")
    private var audioMonitorDelegate: AudioLevelDelegate?

    // Desktop audio monitor
    private var desktopAudioSource: ScreenAudioSource?
    private var lastMicLevelUpdate: CFAbsoluteTime = 0
    private var lastDesktopLevelUpdate: CFAbsoluteTime = 0
    private static let levelUpdateInterval: CFAbsoluteTime = 1.0 / 15.0 // ~15 FPS

    // MARK: - Initialization

    init() {
        generateDefaultTitle()
        refreshCameraDevices()
        refreshScreenDevices()
        startAudioMonitor()
    }

    deinit {
        let session = audioMonitorSession
        session?.stopRunning()
    }

    // MARK: - Screen Selection

    func refreshScreenDevices() {
        availableScreens = ScreenCaptureManager.availableScreens()
        // Auto-select primary screen if nothing selected
        if selectedScreenID == nil {
            selectedScreenID = availableScreens.first(where: { $0.isPrimary })?.displayID
                ?? availableScreens.first?.displayID
        }
    }

    func selectScreen(_ screen: ScreenInfo) {
        selectedScreenID = screen.displayID
        // Restart preview with new screen if desktop is enabled
        if enableDesktop, let session = recordingSession {
            // Stop current capture and restart with new display
            session.stopScreenPreview()
            session.selectedDisplayID = selectedScreenID
            session.screenPreviewHandler = { [weak self] cgImage in
                Task { @MainActor in
                    self?.desktopPreviewImage = NSImage(cgImage: cgImage, size: .zero)
                }
            }
            try? session.startScreenPreview()
        }
    }

    // MARK: - Recording Control

    func startRecording() async {
        // Validate title before starting
        if let validationError = validateTitle(title) {
            error = validationError
            return
        }

        do {
            let session = try acquireRecordingSession()
            session.pipPosition = pipPosition
            session.enableCamera = enableCamera
            session.enableMicrophone = enableMicrophone
            session.enableDesktop = enableDesktop
            session.enableAvatar = enableAvatar
            if enableAvatar, let provider = avatarTextureProvider {
                session.avatarTextureProvider = provider
            }
            if let museProvider = museTextureProvider {
                session.museTextureProvider = museProvider
            }
            debugLog("🎬 [RecordViewModel] Starting recording - enableAvatar: \(enableAvatar), avatarTextureProvider: \(session.avatarTextureProvider != nil ? "SET" : "NIL"), museTextureProvider: \(session.museTextureProvider != nil ? "SET" : "NIL")")
            session.selectedDisplayID = selectedScreenID
            session.watermarkEnabled = watermarkEnabled
            session.watermarkPosition = watermarkPosition
            session.watermarkOpacity = watermarkOpacity
            session.floatingHeadEnabled = floatingHeadEnabled
            session.cameraLayoutStrategy = resolvedCameraLayout()
            session.enableScreenAudio = enableDesktopAudio
            session.setAudioGain(micVolume, for: "microphone")
            session.setAudioGain(desktopAudioVolume, for: "screen")

            if enableCamera {
                ensureDefaultCameraSelection()
                session.setCameraSources(selectedCameraIDs)
            } else {
                session.setCameraSources([])
            }

            // Register with shared state for streaming access
            RecordingState.shared.setRecordingSession(session)

            // Generate output URL (may prompt for folder selection)
            let outputURL = try await generateOutputURL()

            // Start recording
            try await session.startRecording(outputURL: outputURL, title: title)

            isRecording = true
            error = nil

            // Start duration timer
            startTimer()

            // Start stream monitor tracking
            StreamMonitorViewModel.shared.startMonitoring()
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
            RecordingState.shared.setRecordingSession(nil)
            // Release scoped access if we acquired it before failing
            scopedFolderURL?.stopAccessingSecurityScopedResource()
            scopedFolderURL = nil
        }
    }

    func stopRecording() async {
        guard let session = recordingSession else { return }

        stopTimer()
        isProcessing = true

        do {
            debugLog("⏹️ Stopping recording session...")
            let outputURL = try await session.stopRecording()
            debugLog("✅ Recording session stopped, output at: \(outputURL.path)")

            // C2PA signing pending c2pa-opentdf-rs integration
            // let signedURL = try await signRecording(outputURL: outputURL, recordingTitle: title, recordingDuration: duration)

            isRecording = false
            isPaused = false
            duration = 0.0
            // Unregister from shared state
            RecordingState.shared.setRecordingSession(nil)

            // Recording complete - saved successfully
            debugLog("✅ Recording saved: \(outputURL.path)")

            // Post notification to refresh library
            NotificationCenter.default.post(name: .recordingCompleted, object: nil)
            try? activatePreviewPipeline()

            // Stop stream monitor tracking
            StreamMonitorViewModel.shared.stopMonitoring()
        } catch let error as RecorderError {
            debugLog("❌ RecorderError during stop: \(error)")
            self.error = "Failed to stop recording: \(error.localizedDescription). The operation could not be completed."
        } catch {
            debugLog("❌ Error during stop: \(error)")
            self.error = "Failed to stop recording: \(error.localizedDescription). The operation could not be completed."
        }

        // Release security-scoped access to the recordings folder
        scopedFolderURL?.stopAccessingSecurityScopedResource()
        scopedFolderURL = nil

        isProcessing = false
    }

    // MARK: - C2PA Signing (pending c2pa-opentdf-rs integration)
    /*
    private func signRecording(outputURL: URL, recordingTitle: String, recordingDuration: TimeInterval) async throws -> URL {
        // Build C2PA manifest
        var builder = C2PAManifestBuilder(title: recordingTitle)
        _ = builder.addCreatedAction()
        _ = builder.addRecordedAction(when: Date(), duration: recordingDuration)

        // Add device metadata
        #if os(macOS)
            let deviceModel = getMacModel()
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            _ = builder.addDeviceMetadata(model: deviceModel, os: osVersion)
        #endif

        // Add author (if we have identity info - for now use app name)
        _ = builder.addAuthor(name: "Arkavo Creator")

        let manifest = builder.build()

        // Sign the recording
        let signer = try C2PASigner(signingMode: .selfSigned)
        let signedURL = outputURL.deletingPathExtension().appendingPathExtension("signed.mov")

        do {
            try await signer.sign(
                inputFile: outputURL,
                outputFile: signedURL,
                manifest: manifest
            )

            // Replace original with signed version
            try FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: signedURL, to: outputURL)

            return outputURL
        } catch {
            // If signing fails, keep the unsigned recording
            debugLog("C2PA signing failed: \(error.localizedDescription), keeping unsigned recording")
            return outputURL
        }
    }
    */

    private func getMacModel() -> String {
        #if os(macOS)
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            let bytes = model.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        #else
            return "Unknown"
        #endif
    }

    func pauseRecording() {
        guard let session = recordingSession else { return }
        session.pauseRecording()
        isPaused = true
        stopTimer()
    }

    func resumeRecording() {
        guard let session = recordingSession else { return }
        session.resumeRecording()
        isPaused = false
        startTimer()
    }

    /// Creates a recording session for streaming without file recording.
    /// This allows streaming to work independently of the record button.
    func startPreviewSession() async {
        do {
            let session = try acquireRecordingSession()
            session.pipPosition = pipPosition
            session.enableCamera = enableCamera
            session.enableMicrophone = enableMicrophone
            session.enableDesktop = enableDesktop
            session.enableAvatar = enableAvatar
            session.floatingHeadEnabled = floatingHeadEnabled
            session.cameraLayoutStrategy = resolvedCameraLayout()
            session.enableScreenAudio = enableDesktopAudio
            session.setAudioGain(micVolume, for: "microphone")
            session.setAudioGain(desktopAudioVolume, for: "screen")

            if enableCamera {
                ensureDefaultCameraSelection()
                session.setCameraSources(selectedCameraIDs)
            } else {
                session.setCameraSources([])
            }

            // Register with shared state for streaming access
            RecordingState.shared.setRecordingSession(session)

            // Start camera/desktop preview (but not recording to file)
            if enableCamera {
                try session.startCameraPreview(for: selectedCameraIDs)
            }
            if enableDesktop {
                try session.startScreenPreview()
            }
        } catch {
            self.error = "Failed to start preview session: \(error.localizedDescription)"
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let session = recordingSession else { return }
                duration = session.duration
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Always-On Audio Level Monitor

    private func startAudioMonitor() {
        let session = AVCaptureSession()
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let delegate = AudioLevelDelegate { [weak self] level in
            let now = CFAbsoluteTimeGetCurrent()
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, now - lastMicLevelUpdate >= Self.levelUpdateInterval else { return }
                lastMicLevelUpdate = now
                audioLevel = level
            }
        }
        output.setSampleBufferDelegate(delegate, queue: audioMonitorQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        audioMonitorDelegate = delegate
        audioMonitorOutput = output
        audioMonitorSession = session

        DispatchQueue.global(qos: .utility).async {
            session.startRunning()
        }
    }

    func stopAudioMonitor() {
        audioMonitorSession?.stopRunning()
        audioMonitorSession = nil
        audioMonitorOutput = nil
        audioMonitorDelegate = nil
    }

    func toggleDesktopAudio() {
        if enableDesktopAudio {
            enableDesktopAudio = false
            stopDesktopAudioMonitor()
        } else {
            enableDesktopAudio = true
            startDesktopAudioMonitor()
        }
        // Sync to recording session for live updates
        recordingSession?.enableScreenAudio = enableDesktopAudio
    }

    private func startDesktopAudioMonitor() {
        let source = ScreenAudioSource(sourceID: "monitor-desktop-audio")
        source.onSample = { [weak self] sampleBuffer in
            guard let self else { return }
            let level = Self.computeRMS(from: sampleBuffer)
            let now = CFAbsoluteTimeGetCurrent()
            Task { @MainActor [weak self] in
                guard let self, now - lastDesktopLevelUpdate >= Self.levelUpdateInterval else { return }
                lastDesktopLevelUpdate = now
                desktopAudioLevel = level
            }
        }
        desktopAudioSource = source
        Task {
            do {
                try await source.start()
            } catch {
                await MainActor.run {
                    self.error = "Desktop audio requires Screen Recording permission. Open System Settings > Privacy & Security > Screen Recording."
                    self.enableDesktopAudio = false
                }
            }
        }
    }

    private func stopDesktopAudioMonitor() {
        guard let source = desktopAudioSource else { return }
        Task {
            try? await source.stop()
        }
        desktopAudioSource = nil
        desktopAudioLevel = 0.0
    }

    nonisolated static func computeRMS(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee,
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard let dataPointer else { return 0 }

        var sum: Float = 0.0
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let samples = length / MemoryLayout<Float32>.size
            guard samples > 0 else { return 0 }
            dataPointer.withMemoryRebound(to: Float32.self, capacity: samples) { ptr in
                for i in 0..<samples {
                    let s = ptr[i]
                    sum += s * s
                }
            }
            return min(1.0, sqrt(sum / Float(samples)) * 3)
        } else {
            let samples = length / MemoryLayout<Int16>.size
            guard samples > 0 else { return 0 }
            dataPointer.withMemoryRebound(to: Int16.self, capacity: samples) { ptr in
                for i in 0..<samples {
                    let s = Float(ptr[i]) / Float(Int16.max)
                    sum += s * s
                }
            }
            return min(1.0, sqrt(sum / Float(samples)) * 10)
        }
    }

    /// Cleanly shuts down all capture resources (mic, camera, screen).
    /// Called on app termination to release hardware.
    func cleanup() async {
        stopAudioMonitor()
        stopDesktopAudioMonitor()
        stopTimer()

        if isRecording {
            await stopRecording()
        }

        if let session = recordingSession {
            session.stopCameraPreview()
            session.stopScreenPreview()
            try? await session.stopStreaming()
        }

        recordingSession = nil
        RecordingState.shared.setRecordingSession(nil)
    }

    // MARK: - Utilities

    private func generateDefaultTitle() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        title = "Recording \(formatter.string(from: Date()))"
    }

    private func generateOutputURL() async throws -> URL {
        // Get bookmarked folder or prompt user to select one
        var recordingsFolder = RecordingsFolderAccess.getBookmarkedFolder()
        if recordingsFolder == nil {
            recordingsFolder = await RecordingsFolderAccess.chooseRecordingsFolder()
        }

        guard let folder = recordingsFolder else {
            throw CocoaError(.userCancelled)
        }

        // Start security-scoped access and keep it alive for the duration of recording.
        // The previous withScopedAccess pattern stopped access before AVAssetWriter could write.
        guard folder.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        scopedFolderURL = folder

        // Create recordings directory if needed
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Generate filename with appropriate extension based on recording mode
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        // Use .m4a for audio-only (no camera, no desktop, no avatar), .mov for video
        let isAudioOnly = !enableCamera && !enableDesktop && !enableAvatar
        let ext = isAudioOnly ? "m4a" : "mov"
        let filename = "arkavo_recording_\(formatter.string(from: Date())).\(ext)"

        return folder.appendingPathComponent(filename)
    }

    func getAvailableDevices() -> (screens: [ScreenInfo], cameras: [CameraInfo], microphones: [AudioDeviceInfo]) {
        (
            RecordingSession.availableScreens(),
            availableCameras,
            RecordingSession.availableMicrophones(),
        )
    }

    func getCameraPreview() -> AVCaptureSession? {
        recordingSession?.getCameraPreview()
    }

    // MARK: - Format Helpers

    func formattedDuration() -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func audioLevelPercentage() -> Double {
        Double(min(1.0, max(0.0, audioLevel)))
    }

    func desktopAudioLevelPercentage() -> Double {
        Double(min(1.0, max(0.0, desktopAudioLevel)))
    }

    // MARK: - Input Validation

    /// Validates recording title length and characters
    /// - Parameter title: The recording title to validate
    /// - Returns: Error message if validation fails, nil if valid
    private func validateTitle(_ title: String) -> String? {
        // Check if empty (title is optional but should have fallback)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            // This is OK - will use default title
            return nil
        }

        // Check minimum length (if provided)
        if trimmedTitle.count < 3 {
            return "Recording title is too short (minimum 3 characters)"
        }

        // Check maximum length
        if trimmedTitle.count > 200 {
            return "Recording title is too long (maximum 200 characters)"
        }

        // Check for control characters
        if title.rangeOfCharacter(from: .controlCharacters) != nil {
            return "Recording title contains invalid control characters"
        }

        // Check for invalid file system characters
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if title.rangeOfCharacter(from: invalidChars) != nil {
            return "Recording title contains invalid characters (/, \\, :, *, ?, \", <, >, |)"
        }

        return nil
    }

    // MARK: - Camera Management

    func refreshCameraDevices() {
        availableCameras = RecordingSession.availableCameras()
        ensureDefaultCameraSelection()
        refreshCameraPreview()
    }

    func isCameraSelected(_ camera: CameraInfo) -> Bool {
        selectedCameraIDs.contains(camera.id)
    }

    func toggleCameraSelection(_ camera: CameraInfo, isSelected: Bool) {
        if isSelected {
            guard !selectedCameraIDs.contains(camera.id),
                  selectedCameraIDs.count < MultiCameraLayout.maxSupportedSources
            else { return }
            selectedCameraIDs.append(camera.id)
        } else {
            selectedCameraIDs.removeAll { $0 == camera.id }
        }
        recordingSession?.setCameraSources(selectedCameraIDs)
        refreshCameraPreview()
    }

    func canSelectMoreCameras(for camera: CameraInfo) -> Bool {
        isCameraSelected(camera) || selectedCameraIDs.count < MultiCameraLayout.maxSupportedSources
    }

    func cameraTransportLabel(for camera: CameraInfo) -> String {
        camera.transport.displayName
    }

    private var remoteIDsSet: Set<String> {
        Set(remoteCameraSources)
    }

    private func ensureDefaultCameraSelection() {
        guard enableCamera else { return }
        if selectedCameraIDs.isEmpty,
           let first = availableCameras.first
        {
            selectedCameraIDs = [first.id]
        } else {
            // Remove selections no longer available
            let availableIDs = Set(availableCameras.map(\.id)).union(remoteIDsSet)
            selectedCameraIDs.removeAll { !availableIDs.contains($0) }
        }
    }

    private func resolvedCameraLayout() -> MultiCameraLayout {
        selectedCameraIDs.count > 1 ? cameraLayout : .pictureInPicture
    }

    var currentPreviewSourceID: String? {
        if let local = selectedCameraIDs.first {
            return local
        }
        return remoteCameraSources.first
    }

    func bindPreviewStore(_ store: CameraPreviewStore) {
        previewStore = store
        // Always update the preview handler on the session if it exists
        if let session = recordingSession {
            session.previewHandler = { [weak store] event in
                guard let store else { return }
                Task { @MainActor in
                    store.update(with: event)
                }
            }
        }
        Task {
            try? activatePreviewPipeline()
        }
    }

    @discardableResult
    private func acquireRecordingSession() throws -> RecordingSession {
        let session: RecordingSession
        if let existing = recordingSession {
            session = existing
        } else {
            session = try RecordingSession()
            session.metadataHandler = { event in
                // debugLog("📢 [RecordViewModel] metadataHandler called, posting notification for \(event.sourceID)")
                NotificationCenter.default.post(name: .cameraMetadataUpdated, object: event)
                // debugLog("   └─ Notification posted: .cameraMetadataUpdated")
            }
            session.remoteSourcesHandler = { [weak self] sources in
                Task { @MainActor in
                    self?.handleRemoteSourceUpdate(sources)
                }
            }
            if previewStore == nil {
                previewStore = CameraPreviewStore.shared
            }
            if let store = previewStore {
                session.previewHandler = { event in
                    Task { @MainActor in
                        store.update(with: event)
                    }
                }
            }
            recordingSession = session
        }

        // Always ensure monitor frame handler is set (may be called after session already exists)
        // Note: CVPixelBuffer is not Sendable, but we process it immediately for conversion
        session.monitorFrameHandler = { @Sendable pixelBuffer, timestamp in
            // Convert to CGImage on this thread to avoid data race
            var cgImage: CGImage?
            let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
            guard status == noErr, let cgImage else { return }

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            Task { @MainActor in
                StreamMonitorViewModel.shared.receiveFrame(cgImage, width: width, height: height, timestamp: timestamp)
            }
        }

        return session
    }

    func activatePreviewPipeline() throws {
        let session = try acquireRecordingSession()

        if remoteBridgeEnabled {
            let portValue = UInt16(remoteBridgePort) ?? 0
            let serviceName = suggestedHostname
            debugLog("🔧 [RecordViewModel] Enabling remote camera bridge with port: \(portValue == 0 ? "auto" : String(portValue))")
            try? session.enableRemoteCameraBridge(port: portValue, serviceName: serviceName)

            // Get the actual port that was assigned
            if let server = session.remoteCameraServer {
                actualPort = server.port
                debugLog("✅ [RecordViewModel] Remote camera server active on port \(actualPort)")
            }
        }

        if enableCamera && !selectedCameraIDs.isEmpty {
            try? session.startCameraPreview(for: selectedCameraIDs)
        }
    }

    func refreshCameraPreview() {
        guard let session = recordingSession else { return }

        if enableCamera, !selectedCameraIDs.isEmpty {
            try? session.startCameraPreview(for: selectedCameraIDs)
        } else {
            session.stopCameraPreview()
        }
    }

    func refreshDesktopPreview() {
        guard let session = recordingSession else { return }

        if enableDesktop {
            // Set selected display before starting preview
            session.selectedDisplayID = selectedScreenID

            // Set up preview handler
            session.screenPreviewHandler = { [weak self] cgImage in
                Task { @MainActor in
                    self?.desktopPreviewImage = NSImage(cgImage: cgImage, size: .zero)
                }
            }
            try? session.startScreenPreview()
        } else {
            session.stopScreenPreview()
            desktopPreviewImage = nil
        }
    }

    private func handleRemoteSourceUpdate(_ sources: [String]) {
        let newSources = sources.sorted()

        // Only process if sources actually changed
        guard newSources != remoteCameraSources else {
            return  // No change, skip processing
        }

        debugLog("📱 [RemoteCameras] Received source update: \(sources.count) source(s)")
        for source in sources {
            debugLog("  └─ \(source)")
        }

        remoteCameraSources = newSources

        let availableIDs = Set(availableCameras.map(\.id)).union(remoteCameraSources)
        selectedCameraIDs.removeAll { !availableIDs.contains($0) }

        let missing = sources.filter { !selectedCameraIDs.contains($0) }
        let remainingSlots = max(0, MultiCameraLayout.maxSupportedSources - selectedCameraIDs.count)
        if remainingSlots > 0 {
            selectedCameraIDs.append(contentsOf: missing.prefix(remainingSlots))
            debugLog("✅ [RemoteCameras] Auto-selected \(missing.prefix(remainingSlots).count) new source(s)")
        }

        debugLog("📋 [RemoteCameras] Total selected cameras: \(selectedCameraIDs)")
        recordingSession?.setCameraSources(selectedCameraIDs)
        refreshCameraPreview()
    }

    func isRemoteCameraSelected(_ id: String) -> Bool {
        selectedCameraIDs.contains(id)
    }

    func toggleRemoteCameraSelection(_ id: String, isSelected: Bool) {
        if isSelected {
            guard !selectedCameraIDs.contains(id),
                  selectedCameraIDs.count < MultiCameraLayout.maxSupportedSources
            else { return }
            selectedCameraIDs.append(id)
        } else {
            selectedCameraIDs.removeAll { $0 == id }
        }
        recordingSession?.setCameraSources(selectedCameraIDs)
        refreshCameraPreview()
    }

    var suggestedHostname: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    var connectionInfo: String {
        "arkavo://connect?host=\(suggestedHostname)&port=\(actualPort)"
    }
}

// MARK: - Audio Level Delegate

private final class AudioLevelDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onLevel: @Sendable (Float) -> Void

    init(onLevel: @escaping @Sendable (Float) -> Void) {
        self.onLevel = onLevel
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let level = RecordViewModel.computeRMS(from: sampleBuffer)
        onLevel(level)
    }
}
