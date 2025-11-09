import ArkavoRecorderShared
#if canImport(ArkavoRecorder)
    import ArkavoRecorder  // For ARKitCaptureManager on iOS
#endif
import ARKit
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
    @Published var port: String = "5757"
    @Published var mode: ARKitCaptureManager.Mode = .face
    @Published private(set) var statusMessage: String = "Not connected"
    @Published private(set) var discoveredServers: [DiscoveredServer] = []

    private var captureManager: ARKitCaptureManager?
    private var connection: NWConnection?
    private let processingQueue = DispatchQueue(label: "com.arkavo.remote-camera-processing")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let ciContext = CIContext()
    private var currentTrackingState: ARFaceTrackingState = .unknown
    private var lastFrameSent: CFTimeInterval = 0
    private let frameInterval: CFTimeInterval = 1 / 15 // ~15 FPS
    private var netServiceBrowser: NetServiceBrowser?
    private var bonjourServices: [ObjectIdentifier: NetService] = [:]
    private var discoveredServersMap: [String: DiscoveredServer] = [:]
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
        }
    }

    override init() {
        super.init()
        print("🚀 [RemoteCameraStreamer] Initializing...")
        print("📱 [Device] Name: \(UIDevice.current.name)")
        print("📱 [Device] Model: \(UIDevice.current.model)")
        logNetworkInterfaces()
        startBonjourBrowser()
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

    func smartConnect() async {
        print("🎯 [SmartConnect] Starting one-tap connection flow...")
        connectionState = .discovering

        // Wait for discovery with timeout
        print("🔍 [SmartConnect] Waiting for Mac discovery (10s timeout)...")
        guard let server = await waitForDiscovery(timeout: 10.0) else {
            print("❌ [SmartConnect] No Mac found after timeout")
            connectionState = .failed(.noServersFound)
            return
        }

        print("✅ [SmartConnect] Found Mac: \(server.name) at \(server.host):\(server.port)")
        connectionState = .connecting(server.name)

        // Auto-detect best mode
        let detectedMode = detectBestMode()
        print("🎭 [SmartConnect] Auto-detected mode: \(detectedMode)")
        self.mode = detectedMode
        self.autoDetectedMode = detectedMode

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

    private func detectBestMode() -> ARKitCaptureManager.Mode {
        // Prefer face tracking if supported (TrueDepth camera)
        let faceSupported = ARKitCaptureManager.isSupported(.face)
        let bodySupported = ARKitCaptureManager.isSupported(.body)

        print("📱 [ModeDetection] Face tracking: \(faceSupported ? "✅" : "❌"), Body tracking: \(bodySupported ? "✅" : "❌")")

        if faceSupported {
            print("🎭 [ModeDetection] Selected: Face tracking (preferred)")
            return .face
        } else if bodySupported {
            print("🚶 [ModeDetection] Selected: Body tracking")
            return .body
        }
        // Fallback to face even if not supported (error will be shown during connection)
        print("⚠️ [ModeDetection] No ARKit support detected, defaulting to Face")
        return .face
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
                let server = discoveredServers[0]
                print("✅ [Discovery] Found \(discoveredServers.count) server(s) after \(String(format: "%.1f", elapsed))s")
                print("📍 [Discovery] Connecting to: \(server.name) (\(server.host):\(server.port))")
                saveLastConnectedMac(server)
                return server
            }

            if attemptCount % 4 == 0 {
                print("⏳ [Discovery] Still searching... \(String(format: "%.1f", elapsed))s elapsed, \(discoveredServers.count) servers")
            }

            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s polling interval
        }

        print("❌ [Discovery] Timeout after \(timeout)s, no servers found")
        return nil
    }

    // MARK: - Mac Persistence

    private static let lastMacIDKey = "lastConnectedMacID"
    private static let lastMacNameKey = "lastConnectedMacName"
    private static let lastMacHostKey = "lastConnectedMacHost"
    private static let lastMacPortKey = "lastConnectedMacPort"

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
            let captureManager = ARKitCaptureManager()
            captureManager.delegate = self
            try captureManager.start(mode: mode)
            self.captureManager = captureManager
        } catch {
            statusMessage = "ARKit start failed: \(error.localizedDescription)"
            state = .error("Capture failed")
        }
    }

    func stopStreaming() {
        captureManager?.stop()
        captureManager = nil
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

    private func send(message: RemoteCameraMessage) {
        guard let connection else { return }
        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                var data = try self.encoder.encode(message)
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

    private func sendFrame(buffer: CVPixelBuffer, timestamp: CMTime) {
        let now = CACurrentMediaTime()
        guard now - lastFrameSent >= frameInterval else { return }
        lastFrameSent = now

        processingQueue.async { [weak self] in
            guard let self,
                  let payload = self.makeFramePayload(buffer: buffer, timestamp: timestamp)
            else { return }
            self.send(message: .frame(payload))
        }
    }

    private func sendMetadata(_ metadata: CameraMetadata) {
        let event = CameraMetadataEvent(sourceID: sourceID, metadata: metadata)
        send(message: .metadata(event))
    }

    private func makeFramePayload(buffer: CVPixelBuffer, timestamp: CMTime) -> RemoteCameraMessage.FramePayload? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard
            let jpeg = ciContext.jpegRepresentation(
                of: ciImage,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
            )
        else {
            return nil
        }

        return RemoteCameraMessage.FramePayload(
            sourceID: sourceID,
            timestamp: CMTimeGetSeconds(timestamp),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            imageData: jpeg
        )
    }

    private func sendFaceMetadata(blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) {
        var normalized: [String: Float] = [:]
        for (key, value) in blendShapes {
            normalized[key.rawValue] = value.floatValue
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

    private func updateDiscoveredServers() {
        discoveredServers = discoveredServersMap.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        print("📋 [Bonjour] Updated server list: \(discoveredServers.count) server(s)")
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
        sendFrame(buffer: buffer, timestamp: timestamp)

        if let blendShapes = metadata.blendShapes {
            sendFaceMetadata(blendShapes: blendShapes)
        } else if let skeleton = metadata.bodySkeleton {
            sendBodyMetadata(skeleton)
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
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_: NetServiceBrowser, didRemove service: NetService, moreComing _: Bool) {
        print("❌ [Bonjour] Service removed: \(service.name)")
        let identifier = ObjectIdentifier(service)
        bonjourServices.removeValue(forKey: identifier)
        let prefix = "\(service.name)|"
        discoveredServersMap = discoveredServersMap.filter { !$0.key.hasPrefix(prefix) }
        updateDiscoveredServers()
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
