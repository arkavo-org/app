import ArkavoKit
#if canImport(ArkavoRecorder)
    import ArkavoKit  // For ARKitCaptureManager on iOS
#endif
import ARKit
import AVFoundation
import Combine
import Foundation
import Network
import SwiftUI
import SystemConfiguration.CaptiveNetwork
#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
    import CoreNFC
#endif

@MainActor
final class RemoteCameraStreamer: NSObject, ObservableObject {
    enum StreamState: Equatable {
        case idle
        case connecting
        case streaming
        case error(String)
    }

    enum ConnectionState: Equatable {
        case idle
        case discovering
        case connecting(String) // Mac name
        case streaming
        case failed(ConnectionError)

        var statusMessage: String {
            switch self {
            case .idle:
                return "Ready to stream"
            case .discovering:
                return "Finding Mac..."
            case .connecting(let macName):
                return "Connecting to \(macName)..."
            case .streaming:
                return "Streaming active"
            case .failed(let error):
                return error.localizedDescription
            }
        }

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.discovering, .discovering),
                 (.streaming, .streaming):
                return true
            case (.connecting(let lhsName), .connecting(let rhsName)):
                return lhsName == rhsName
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    enum ConnectionError: LocalizedError, Equatable {
        case noServersFound
        case connectionTimeout
        case unsupportedMode
        case networkUnavailable

        var errorDescription: String? {
            switch self {
            case .noServersFound:
                return "No Mac found. Make sure ArkavoCreator is running on the same network."
            case .connectionTimeout:
                return "Connection timed out. Please check your network."
            case .unsupportedMode:
                return "This device doesn't support the required ARKit mode."
            case .networkUnavailable:
                return "Network unavailable. Connect to Wi-Fi or enable Personal Hotspot."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .noServersFound:
                return "Ensure ArkavoCreator is open and 'Allow Remote Cameras' is enabled."
            case .connectionTimeout:
                return "Move closer to your Mac or check Wi-Fi signal."
            case .unsupportedMode:
                return "Try with a different device or mode."
            case .networkUnavailable:
                return "Connect to the same network as your Mac."
            }
        }
    }

    struct DiscoveredServer: Identifiable, Equatable, Codable {
        let id: String
        let name: String
        let host: String
        let port: Int
    }

    @Published private(set) var state: StreamState = .idle
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var autoDetectedMode: ARKitCaptureManager.Mode?
    @Published var host: String = ""
    @Published var port: String = String(RemoteCameraConstants.defaultPort)
    @Published var mode: ARKitCaptureManager.Mode = .face {
        didSet {
            // Track that user manually changed the mode
            if mode != oldValue {
                hasManualModeSelection = true
            }
        }
    }
    @Published private(set) var statusMessage: String = "Not connected"
    @Published private(set) var discoveredServers: [DiscoveredServer] = []

    private var hasManualModeSelection = false
    private var noDetectionFrameCount = 0
    private var hasAutoSwitchedMode = false

    private var captureManager: ARKitCaptureManager?
    private var connection: NWConnection?
    private let processingQueue = DispatchQueue(label: "com.arkavo.remote-camera-processing")
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    // private var videoEncoder: VideoStreamEncoder?  // Disabled: VideoStreamEncoder not in Xcode project
    private var currentTrackingState: ARFaceTrackingState = .unknown
    private var lastFrameSent: CFTimeInterval = 0
    private let frameInterval: CFTimeInterval = RemoteCameraConstants.frameInterval
    private var netServiceBrowser: NetServiceBrowser?
    private var bonjourServices: [ObjectIdentifier: NetService] = [:]
    private var discoveredServersMap: [String: DiscoveredServer] = [:]
    private var nwBrowser: NWBrowser?
#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
    private var nfcReader: RemoteCameraNFCReader?
#endif

    private var sourceID: String {
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")
        switch mode {
        case .face:
            return "\(deviceName)-face"
        case .body:
            return "\(deviceName)-body"
        case .combined:
            return "\(deviceName)-combined"
        }
    }

    override init() {
        super.init()
        print("🚀 [RemoteCameraStreamer] Initializing...")
        print("📱 [Device] Name: \(UIDevice.current.name)")
        print("📱 [Device] Model: \(UIDevice.current.model)")
        logNetworkInterfaces()
        startBonjourBrowser()
        startNWBrowser()
    }

    private func logNetworkInterfaces() {
        print("🌐 [Network] Checking available interfaces...")

        // Get WiFi info if available
        #if !targetEnvironment(simulator)
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                    if let ssid = info["SSID"] as? String {
                        print("   WiFi SSID: \(ssid)")
                    }
                    if let bssid = info["BSSID"] as? String {
                        print("   BSSID: \(bssid)")
                    }
                }
            }
        }
        #endif

        print("💡 [Network] Ensure Mac and iPad are on same Wi-Fi network")
        print("💡 [Network] Or enable Personal Hotspot on iPad and connect Mac via USB-C")
    }

    func toggleStreaming() {
        switch state {
        case .idle, .error:
            Task {
                await startStreaming()
            }
        case .connecting, .streaming:
            stopStreaming()
        }
    }

    // MARK: - Smart Connect (One-Tap Experience)

    /// Direct connection with explicit host and port (e.g., from QR code)
    func connectDirect(host: String, port: Int) async {
        print("🔗 [Direct] Connecting to \(host):\(port)")
        self.host = host
        self.port = String(port)

        connectionState = .connecting(host)

        // Only auto-detect if user hasn't manually selected a mode
        if !hasManualModeSelection {
            // Disabled: ARKitModeDetector not in Xcode project
            // let detectedMode = ARKitModeDetector.detectBestMode()
            // print("🎭 [Direct] Auto-detected mode: \(detectedMode)")
            // self.mode = detectedMode
            // self.autoDetectedMode = detectedMode
            print("🎭 [Direct] Using default mode: \(mode)")
            self.autoDetectedMode = mode
        } else {
            print("🎭 [Direct] Using manual mode selection: \(mode)")
            self.autoDetectedMode = mode
        }

        // Start ARKit capture and connection
        await startStreaming()
    }

    func smartConnect() async {
        print("🎯 [SmartConnect] Starting one-tap connection flow...")
        connectionState = .discovering

        // Wait for discovery with timeout
        print("🔍 [SmartConnect] Waiting for Mac discovery (\(RemoteCameraConstants.discoveryTimeout)s timeout)...")
        guard let server = await waitForDiscovery(timeout: RemoteCameraConstants.discoveryTimeout) else {
            print("❌ [SmartConnect] No Mac found after timeout")
            connectionState = .failed(.noServersFound)
            return
        }

        print("✅ [SmartConnect] Found Mac: \(server.name) at \(server.host):\(server.port)")
        connectionState = .connecting(server.name)

        // Only auto-detect if user hasn't manually selected a mode
        if !hasManualModeSelection {
            // Disabled: ARKitModeDetector not in Xcode project
            // let detectedMode = ARKitModeDetector.detectBestMode()
            // print("🎭 [SmartConnect] Auto-detected mode: \(detectedMode)")
            // self.mode = detectedMode
            // self.autoDetectedMode = detectedMode
            print("🎭 [SmartConnect] Using default mode: \(mode)")
            self.autoDetectedMode = mode
        } else {
            print("🎭 [SmartConnect] Using manual mode selection: \(mode)")
            self.autoDetectedMode = mode
        }

        // Select server and connect
        selectServer(server)

        // Start streaming
        print("📡 [SmartConnect] Initiating streaming connection...")
        await startStreaming()

        if case .streaming = state {
            print("✅ [SmartConnect] Successfully streaming!")
            connectionState = .streaming
        } else if case .error(let errorMsg) = state {
            print("❌ [SmartConnect] Connection failed: \(errorMsg)")
            connectionState = .failed(.connectionTimeout)
        }
    }

    func smartDisconnect() {
        stopStreaming()
        connectionState = .idle
    }


    private func waitForDiscovery(timeout: TimeInterval) async -> DiscoveredServer? {
        // Check cache first - try to reconnect to last used Mac
        if let lastMac = loadLastConnectedMac() {
            print("💾 [Discovery] Found cached Mac: \(lastMac.name)")
            if discoveredServers.contains(where: { $0.id == lastMac.id }) {
                print("✅ [Discovery] Cached Mac is available, using it")
                return lastMac
            } else {
                print("⏳ [Discovery] Cached Mac not yet discovered, waiting...")
            }
        } else {
            print("🆕 [Discovery] No cached Mac, discovering for first time...")
        }

        // If no cached Mac or not found, wait for discovery
        let startTime = Date()
        var attemptCount = 0
        while Date().timeIntervalSince(startTime) < timeout {
            attemptCount += 1
            let elapsed = Date().timeIntervalSince(startTime)

            if !discoveredServers.isEmpty {
                // Prefer .local hostnames over IP addresses (better for mDNS resolution)
                let server = discoveredServers.first(where: { $0.host.hasSuffix(".local") }) ?? discoveredServers[0]
                print("✅ [Discovery] Found \(discoveredServers.count) server(s) after \(String(format: "%.1f", elapsed))s")
                print("📍 [Discovery] Connecting to: \(server.name) (\(server.host):\(server.port))")
                print("   └─ Preferred .local hostname: \(server.host.hasSuffix(".local"))")
                saveLastConnectedMac(server)
                return server
            }

            if attemptCount % 4 == 0 {
                print("⏳ [Discovery] Still searching... \(String(format: "%.1f", elapsed))s elapsed, \(discoveredServers.count) servers")
            }

            try? await Task.sleep(nanoseconds: RemoteCameraConstants.discoveryPollingInterval)
        }

        print("❌ [Discovery] Timeout after \(timeout)s, no servers found")
        return nil
    }

    // MARK: - Mac Persistence

    private static let lastMacIDKey = "lastConnectedMacID"
    private static let lastMacNameKey = "lastConnectedMacName"
    private static let lastMacHostKey = "lastConnectedMacHost"
    private static let lastMacPortKey = "lastConnectedMacPort"
    private static let autoConnectEnabledKey = "autoConnectToCreatorEnabled"

    private func saveLastConnectedMac(_ server: DiscoveredServer) {
        UserDefaults.standard.set(server.id, forKey: Self.lastMacIDKey)
        UserDefaults.standard.set(server.name, forKey: Self.lastMacNameKey)
        UserDefaults.standard.set(server.host, forKey: Self.lastMacHostKey)
        UserDefaults.standard.set(server.port, forKey: Self.lastMacPortKey)
    }

    private func loadLastConnectedMac() -> DiscoveredServer? {
        guard let id = UserDefaults.standard.string(forKey: Self.lastMacIDKey),
              let name = UserDefaults.standard.string(forKey: Self.lastMacNameKey),
              let host = UserDefaults.standard.string(forKey: Self.lastMacHostKey) else {
            return nil
        }
        let port = UserDefaults.standard.integer(forKey: Self.lastMacPortKey)
        guard port > 0 else { return nil }

        return DiscoveredServer(id: id, name: name, host: host, port: port)
    }

    func clearLastConnectedMac() {
        UserDefaults.standard.removeObject(forKey: Self.lastMacIDKey)
        UserDefaults.standard.removeObject(forKey: Self.lastMacNameKey)
        UserDefaults.standard.removeObject(forKey: Self.lastMacHostKey)
        UserDefaults.standard.removeObject(forKey: Self.lastMacPortKey)
    }

    // MARK: - Auto-Connect Preference

    static var isAutoConnectEnabled: Bool {
        get {
            // Default to true for mounted phone use case
            if UserDefaults.standard.object(forKey: autoConnectEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoConnectEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoConnectEnabledKey)
        }
    }

    // MARK: - Original Connection Methods

    func startStreaming() async {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusMessage = "Enter your Mac hostname/IP"
            state = .error("Missing host")
            return
        }

        guard let portValue = UInt16(port) else {
            statusMessage = "Invalid port"
            state = .error("Invalid port")
            return
        }

        guard ARKitCaptureManager.isSupported(mode) else {
            statusMessage = "Selected AR mode not supported on this device"
            state = .error("Mode not supported")
            return
        }

        // Request microphone permission before starting ARKit with audio
        let micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        if micPermission == .notDetermined {
            print("🎤 [Permissions] Requesting microphone access...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                statusMessage = "Microphone access denied"
                state = .error("Permission denied")
                print("❌ [Permissions] Microphone access denied by user")
                return
            }
            print("✅ [Permissions] Microphone access granted")
        } else if micPermission == .denied || micPermission == .restricted {
            statusMessage = "Microphone access denied. Enable in Settings > Arkavo"
            state = .error("Permission denied")
            print("❌ [Permissions] Microphone access previously denied")
            return
        }

        stopStreaming()

        state = .connecting
        statusMessage = "Connecting to \(host):\(portValue)…"

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: portValue)!, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                self?.handleConnectionState(newState)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))

        do {
            // Disabled: VideoStreamEncoder not in Xcode project
            // // Create video encoder for H.264 streaming
            // let encoder = try VideoStreamEncoder { [weak self] naluData, isKeyFrame, timestamp in
            //     self?.sendVideoNALU(naluData, isKeyFrame: isKeyFrame, timestamp: timestamp)
            // }
            // try encoder.start()
            // self.videoEncoder = encoder

            // Start ARKit capture
            let captureManager = ARKitCaptureManager()
            captureManager.delegate = self
            try captureManager.start(mode: mode)
            self.captureManager = captureManager
        } catch {
            statusMessage = "Failed to start streaming: \(error.localizedDescription)"
            state = .error("Capture failed")
        }
    }

    func stopStreaming() {
        // Disabled: VideoStreamEncoder not in Xcode project
        // // Stop video encoder
        // if let encoder = videoEncoder {
        //     Task {
        //         try? await encoder.stop()
        //     }
        // }
        // videoEncoder = nil

        // Stop capture
        captureManager?.stop()
        captureManager = nil

        // Close connection
        connection?.cancel()
        connection = nil

        state = .idle
        statusMessage = "Not connected"
    }

    func selectServer(_ server: DiscoveredServer) {
        host = server.host
        port = "\(server.port)"
        statusMessage = "Selected \(server.name)"
    }

#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
    func scanWithNFC() {
        nfcReader = RemoteCameraNFCReader()
        nfcReader?.delegate = self
        nfcReader?.begin()
    }
#endif

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            state = .streaming
            statusMessage = "Streaming to \(host)"
            sendHandshake()
        case let .failed(error):
            state = .error(error.localizedDescription)
            statusMessage = "Connection failed: \(error.localizedDescription)"
            stopStreaming()
        case .cancelled:
            state = .idle
            statusMessage = "Disconnected"
        default:
            break
        }
    }

    private func sendHandshake() {
        let message = RemoteCameraMessage.handshake(sourceID: sourceID, deviceName: UIDevice.current.name)
        send(message: message)
    }

    private func encodeFrame(buffer: CVPixelBuffer, timestamp: CMTime) {
        let now = CACurrentMediaTime()
        guard now - lastFrameSent >= frameInterval else { return }
        lastFrameSent = now

        // Encode with H.264 (callback will handle sending)
        // Disabled: VideoStreamEncoder not in Xcode project
        // try? videoEncoder?.encode(buffer, timestamp: timestamp)
    }

    private func sendVideoNALU(_ naluData: Data, isKeyFrame: Bool, timestamp: CMTime) {
        let payload = RemoteCameraMessage.VideoNALUPayload(
            sourceID: sourceID,
            timestamp: CMTimeGetSeconds(timestamp),
            isKeyFrame: isKeyFrame,
            naluData: naluData
        )
        send(message: .videoNALU(payload))
    }

    private func sendMetadata(_ metadata: CameraMetadata) {
        let event = CameraMetadataEvent(sourceID: sourceID, metadata: metadata)
        print("📨 [RemoteCameraStreamer] Encoding metadata message for sourceID: \(sourceID)")
        send(message: .metadata(event))
        print("   └─ Metadata message queued for send")
    }

    private func send(message: RemoteCameraMessage) {
        guard let connection else { return }
        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                var data = try self.jsonEncoder.encode(message)
                data.append(0x0A)
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        print("⚠️ RemoteCameraStreamer send error: \(error)")
                    }
                })
            } catch {
                print("⚠️ RemoteCameraStreamer encoding error: \(error)")
            }
        }
    }

    private func sendFaceMetadata(blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) {
        var normalized: [String: Float] = [:]
        for (key, value) in blendShapes {
            normalized[key.rawValue] = value.floatValue
        }
        print("📤 [RemoteCameraStreamer] Sending face metadata: \(normalized.count) blend shapes")
        if let firstShape = normalized.first {
            print("   └─ Sample: \(firstShape.key) = \(String(format: "%.3f", firstShape.value))")
        }
        let face = ARFaceMetadata(blendShapes: normalized, trackingState: currentTrackingState)
        sendMetadata(.arFace(face))
    }

    private func sendBodyMetadata(_ skeleton: ARSkeleton3D) {
        var joints: [ARBodyMetadata.Joint] = []
        let transforms = skeleton.jointModelTransforms
        for (index, name) in skeleton.definition.jointNames.enumerated() {
            guard index < transforms.count else { continue }
            joints.append(.init(name: name, transform: transforms[index].asFloats))
        }
        let body = ARBodyMetadata(joints: joints)
        sendMetadata(.arBody(body))
    }

    private func startBonjourBrowser() {
        print("🔍 [Bonjour] Starting service discovery for \(RemoteCameraConstants.serviceType)")
        netServiceBrowser?.stop()
        let browser = NetServiceBrowser()
        browser.includesPeerToPeer = true
        browser.delegate = self
        browser.searchForServices(ofType: RemoteCameraConstants.serviceType, inDomain: "local.")
        netServiceBrowser = browser
    }

    private func startNWBrowser() {
        print("🔍 [NWBrowser] Starting Network framework discovery...")
        nwBrowser?.cancel()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: RemoteCameraConstants.serviceType, domain: "local."), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    print("✅ [NWBrowser] Ready and searching")
                case .failed(let error):
                    print("❌ [NWBrowser] Failed: \(error)")
                case .cancelled:
                    print("🛑 [NWBrowser] Cancelled")
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            Task { @MainActor in
                print("📡 [NWBrowser] Results changed: \(results.count) endpoint(s)")
                for result in results {
                    switch result.endpoint {
                    case .service(let name, let type, let domain, let interface):
                        print("  └─ Found: \(name) (\(type)) on \(interface?.name ?? "unknown")")
                        self.resolveNWEndpoint(result)
                    default:
                        break
                    }
                }
            }
        }

        browser.start(queue: .main)
        nwBrowser = browser
    }

    private func resolveNWEndpoint(_ result: NWBrowser.Result) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    if case .service(let name, _, _, _) = result.endpoint,
                       let innerEndpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = innerEndpoint {
                        let hostString = "\(host)"
                        let portInt = Int(port.rawValue)
                        print("✅ [NWBrowser] Resolved: \(name) -> \(hostString):\(portInt)")

                        let key = "\(name)|\(hostString)|\(portInt)"
                        let server = DiscoveredServer(
                            id: key,
                            name: name,
                            host: hostString,
                            port: portInt
                        )
                        self.discoveredServersMap[key] = server
                        self.updateDiscoveredServers()
                    }
                    connection.cancel()
                case .failed:
                    connection.cancel()
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func updateDiscoveredServers() {
        discoveredServers = discoveredServersMap.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        print("📋 [Discovery] Updated server list: \(discoveredServers.count) server(s)")
        for server in discoveredServers {
            print("  └─ \(server.name) at \(server.host):\(server.port)")
        }
    }
}

@MainActor
extension RemoteCameraStreamer: ARKitCaptureManagerDelegate {
    func arKitCaptureManager(
        _: ARKitCaptureManager,
        didOutput buffer: CVPixelBuffer,
        timestamp: CMTime,
        metadata: ARKitFrameMetadata
    ) {
        encodeFrame(buffer: buffer, timestamp: timestamp)

        // In combined mode, send both face and body metadata when available
        let hasFace = metadata.blendShapes != nil
        let hasBody = metadata.bodySkeleton != nil

        if hasFace && hasBody {
            print("🎭🦴 [RemoteCameraStreamer] Combined tracking: face (\(metadata.blendShapes!.count) shapes) + body")
            sendFaceMetadata(blendShapes: metadata.blendShapes!)
            sendBodyMetadata(metadata.bodySkeleton!)
            noDetectionFrameCount = 0  // Reset counter
        } else if let blendShapes = metadata.blendShapes {
            print("🎭 [RemoteCameraStreamer] Face tracking: \(blendShapes.count) blend shapes")
            sendFaceMetadata(blendShapes: blendShapes)
            noDetectionFrameCount = 0  // Reset counter
        } else if let skeleton = metadata.bodySkeleton {
            print("🦴 [RemoteCameraStreamer] Body tracking: skeleton detected")
            sendBodyMetadata(skeleton)
            noDetectionFrameCount = 0  // Reset counter
        } else {
            // No detection - implement smart fallback
            noDetectionFrameCount += 1

            // After threshold frames (~2 seconds at 30fps) with no detection, try switching modes
            if !hasManualModeSelection && !hasAutoSwitchedMode && noDetectionFrameCount >= RemoteCameraConstants.modeDetectionFrameThreshold {
                print("🔄 [RemoteCameraStreamer] No detection for 2s - attempting smart camera switch...")

                if mode == .face && ARKitCaptureManager.isSupported(.body) {
                    print("   → Switching from face to body mode (back camera might be facing user)")
                    Task { @MainActor in
                        hasAutoSwitchedMode = true
                        mode = .body
                        autoDetectedMode = .body
                        // Restart ARKit with new mode
                        stopStreaming()
                        Task {
                            try? await Task.sleep(nanoseconds: RemoteCameraConstants.discoveryPollingInterval)
                            await startStreaming()
                        }
                    }
                } else if mode == .body && ARKitCaptureManager.isSupported(.face) {
                    print("   → Switching from body to face mode (front camera might be facing user)")
                    Task { @MainActor in
                        hasAutoSwitchedMode = true
                        mode = .face
                        autoDetectedMode = .face
                        // Restart ARKit with new mode
                        stopStreaming()
                        Task {
                            try? await Task.sleep(nanoseconds: RemoteCameraConstants.discoveryPollingInterval)
                            await startStreaming()
                        }
                    }
                }
            }

            if noDetectionFrameCount % RemoteCameraConstants.noDetectionLoggingInterval == 0 {  // Log every second
                print("⚠️ [RemoteCameraStreamer] No detection (\(noDetectionFrameCount) frames) - Mode: \(mode)")
            }
        }
    }

    func arKitCaptureManager(_: ARKitCaptureManager, didUpdate trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            currentTrackingState = .normal
        case .notAvailable:
            currentTrackingState = .notTracking
        case .limited:
            currentTrackingState = .limited
        @unknown default:
            currentTrackingState = .unknown
        }
    }

    func arKitCaptureManager(_: ARKitCaptureManager, didFailWith error: Error) {
        state = .error(error.localizedDescription)
        statusMessage = "ARKit error: \(error.localizedDescription)"
        stopStreaming()
    }
}

@MainActor
extension RemoteCameraStreamer: @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    func netServiceBrowser(_: NetServiceBrowser, didFind service: NetService, moreComing _: Bool) {
        print("🔍 [Bonjour] Found service: \(service.name) (resolving...)")
        let identifier = ObjectIdentifier(service)
        bonjourServices[identifier] = service
        service.includesPeerToPeer = true
        service.delegate = self
        service.resolve(withTimeout: RemoteCameraConstants.serviceResolutionTimeout)
    }

    func netServiceBrowser(_: NetServiceBrowser, didRemove service: NetService, moreComing _: Bool) {
        print("❌ [Bonjour] Service removed: \(service.name)")
        let identifier = ObjectIdentifier(service)
        bonjourServices.removeValue(forKey: identifier)
        let prefix = "\(service.name)|"
        discoveredServersMap = discoveredServersMap.filter { !$0.key.hasPrefix(prefix) }
        updateDiscoveredServers()
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("🔍 [Bonjour] Browser will start searching")
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("🛑 [Bonjour] Browser stopped searching")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        print("❌ [Bonjour] Browser failed to search")
        if let domain = errorDict["NSNetServicesErrorDomain"],
           let code = errorDict["NSNetServicesErrorCode"] {
            print("   Error - Domain: \(domain), Code: \(code)")
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard
            let hostName = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            sender.port != -1
        else {
            print("⚠️ [Bonjour] Failed to resolve: \(sender.name)")
            return
        }

        print("✅ [Bonjour] Resolved: \(sender.name) -> \(hostName):\(sender.port)")
        let key = "\(sender.name)|\(hostName)|\(sender.port)"
        let server = DiscoveredServer(
            id: key,
            name: sender.name,
            host: hostName,
            port: sender.port
        )
        discoveredServersMap[key] = server
        updateDiscoveredServers()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("⚠️ Failed to resolve service \(sender): \(errorDict)")
    }
}

#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
@MainActor
extension RemoteCameraStreamer: RemoteCameraNFCReaderDelegate {
    func remoteCameraNFCReader(_: RemoteCameraNFCReader, didResolve host: String, port: String) {
        self.host = host
        self.port = port
        statusMessage = "NFC paired with \(host)"
    }

    func remoteCameraNFCReader(_: RemoteCameraNFCReader, didFailWith error: Error) {
        statusMessage = "NFC error: \(error.localizedDescription)"
    }
}
#endif

private extension simd_float4x4 {
    var asFloats: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w,
        ]
    }
}

#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
    import CoreNFC
    import Foundation

    @MainActor
    protocol RemoteCameraNFCReaderDelegate: AnyObject {
        func remoteCameraNFCReader(_ reader: RemoteCameraNFCReader, didResolve host: String, port: String)
        func remoteCameraNFCReader(_ reader: RemoteCameraNFCReader, didFailWith error: Error)
    }

    final class RemoteCameraNFCReader: NSObject, @preconcurrency NFCNDEFReaderSessionDelegate {
        weak var delegate: RemoteCameraNFCReaderDelegate?
        private var session: NFCNDEFReaderSession?

        func begin() {
            guard NFCNDEFReaderSession.readingAvailable else {
                notifyFailure(
                    NSError(domain: "RemoteCameraNFC", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "NFC not supported on this device",
                    ])
                )
                return
            }

            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
            session.alertMessage = "Hold near the ArkavoCreator NFC pairing tag."
            session.begin()
            self.session = session
        }

        func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
            notifyFailure(error)
            self.session = nil
        }

        func readerSessionDidBecomeActive(_: NFCNDEFReaderSession) {}

        func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
            guard let tag = tags.first else { return }

            session.connect(to: tag) { [weak self] error in
                if let error {
                    self?.notifyFailure(error)
                    session.invalidate()
                    return
                }

                tag.readNDEF { message, error in
                    if let error {
                        self?.notifyFailure(error)
                        session.invalidate()
                        return
                    }

                    guard
                        let payload = message?.records.first,
                        let string = RemoteCameraNFCReader.decodeTextPayload(payload)
                    else {
                        self?.notifyFailure(
                            NSError(domain: "RemoteCameraNFC", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "Invalid NFC payload",
                            ])
                        )
                        session.invalidate()
                        return
                    }

                    self?.processResolvedString(string, session: session)
                    session.invalidate()
                }
            }
        }

        func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
            guard let record = messages.first?.records.first,
                  let string = RemoteCameraNFCReader.decodeTextPayload(record)
            else {
                return
            }
            processResolvedString(string, session: session)
            session.invalidate()
        }

        private static func decodeTextPayload(_ payload: NFCNDEFPayload) -> String? {
            guard payload.typeNameFormat == .nfcWellKnown,
                  payload.type.count == 1,
                  payload.type.first == 0x54,
                  let statusByte = payload.payload.first
            else {
                return nil
            }

            let languageCodeLength = Int(statusByte & 0x3F)
            let textData = payload.payload.dropFirst(1 + languageCodeLength)
            return String(data: textData, encoding: .utf8)
        }

        private static func parseConnectionString(_ string: String) -> (String, String)? {
            let trimmed = string
                .replacingOccurrences(of: "arkavo://", with: "")
                .replacingOccurrences(of: "ARKAVO://", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let components = trimmed.split(separator: ":")
            guard components.count >= 2 else { return nil }

            let host = String(components.dropLast().joined(separator: ":"))
            let port = String(components.last!)
            return (host, port)
        }

        private func processResolvedString(_ string: String, session: NFCNDEFReaderSession) {
            if let (host, port) = RemoteCameraNFCReader.parseConnectionString(string) {
                notifyResolved(host: host, port: port)
            } else {
                notifyFailure(
                    NSError(domain: "RemoteCameraNFC", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Could not parse NFC host/port",
                    ])
                )
            }
            session.alertMessage = "Paired with ArkavoCreator."
        }

        private func notifyResolved(host: String, port: String) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.remoteCameraNFCReader(self, didResolve: host, port: port)
            }
        }

        private func notifyFailure(_ error: Error) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.remoteCameraNFCReader(self, didFailWith: error)
            }
        }
    }

    extension RemoteCameraNFCReader: @unchecked Sendable {}
#endif
