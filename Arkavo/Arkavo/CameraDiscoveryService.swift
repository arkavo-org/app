import ArkavoKit
import Foundation
import Network

/// Handles discovery of remote camera servers via Bonjour/mDNS
@MainActor
final class CameraDiscoveryService: NSObject, ObservableObject {
    struct DiscoveredServer: Identifiable, Equatable, Codable {
        let id: String
        let name: String
        let host: String
        let port: Int
    }

    @Published private(set) var discoveredServers: [DiscoveredServer] = []

    private var netServiceBrowser: NetServiceBrowser?
    private var bonjourServices: [ObjectIdentifier: NetService] = [:]
    private var discoveredServersMap: [String: DiscoveredServer] = [:]
    private var nwBrowser: NWBrowser?

    override init() {
        super.init()
        startBonjourBrowser()
        startNWBrowser()
    }

    func stop() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        nwBrowser?.cancel()
        nwBrowser = nil
        bonjourServices.removeAll()
        discoveredServersMap.removeAll()
    }

    /// Wait for a server to be discovered within the timeout period
    /// Returns the last connected Mac if available, otherwise the first discovered server
    func waitForDiscovery(timeout: TimeInterval, lastConnectedMac: DiscoveredServer?) async -> DiscoveredServer? {
        // Check cache first - try to reconnect to last used Mac
        if let lastMac = lastConnectedMac {
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

    // MARK: - Private Methods

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

        browser.browseResultsChangedHandler = { [weak self] results, _ in
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
                        self.addServer(name: name, host: hostString, port: portInt)
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

    private func addServer(name: String, host: String, port: Int) {
        let key = "\(name)|\(host)|\(port)"
        let server = DiscoveredServer(
            id: key,
            name: name,
            host: host,
            port: port
        )
        discoveredServersMap[key] = server
        updateDiscoveredServers()
    }

    private func updateDiscoveredServers() {
        discoveredServers = discoveredServersMap.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        print("📋 [Discovery] Updated server list: \(discoveredServers.count) server(s)")
        for server in discoveredServers {
            print("  └─ \(server.name) at \(server.host):\(server.port)")
        }
    }

    private func removeServer(withPrefix prefix: String) {
        discoveredServersMap = discoveredServersMap.filter { !$0.key.hasPrefix(prefix) }
        updateDiscoveredServers()
    }
}

// MARK: - NetServiceBrowserDelegate & NetServiceDelegate

@MainActor
extension CameraDiscoveryService: @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
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
        removeServer(withPrefix: prefix)
    }

    func netServiceBrowserWillSearch(_: NetServiceBrowser) {
        print("🔍 [Bonjour] Browser will start searching")
    }

    func netServiceBrowserDidStopSearch(_: NetServiceBrowser) {
        print("🛑 [Bonjour] Browser stopped searching")
    }

    func netServiceBrowser(_: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
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
        addServer(name: sender.name, host: hostName, port: sender.port)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("⚠️ Failed to resolve service \(sender): \(errorDict)")
    }
}
