import AVFoundation
import MultipeerConnectivity
import SwiftUI

struct ContactsCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @EnvironmentObject var agentService: AgentService
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager()
    @State private var isSearchingNearby = false
    @State private var showShareSheet = false
    @State private var shareableLink: String = ""
    @State private var showAgentScanner = false
    @State private var showAgentDiscovery = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                            .symbolRenderingMode(.hierarchical)

                        Text("Connect with Others")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Add contacts or connect with agents")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Connection Options
                    VStack(spacing: 20) {
                        // MARK: - People Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("People")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)

                            // Connect Nearby Option
                            ConnectionOptionButton(
                                icon: "dot.radiowaves.left.and.right",
                                iconColor: .blue,
                                title: "Connect Nearby",
                                description: "Add someone you know who's right beside you—verify in person to grow your trusted network.",
                                isLoading: isSearchingNearby
                            ) {
                                startNearbyConnection()
                            }

                            // Invite Remotely Option
                            ConnectionOptionButton(
                                icon: "square.and.arrow.up.circle.fill",
                                iconColor: .green,
                                title: "Invite Remotely",
                                description: "Send your Arkavo link with the iOS Share Sheet to connect with someone you already know—no matter the distance."
                            ) {
                                showInviteRemotely()
                            }
                        }

                        // MARK: - Agents Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Agents")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)

                            // Scan Agent QR Option
                            ConnectionOptionButton(
                                icon: "qrcode.viewfinder",
                                iconColor: .purple,
                                title: "Scan Agent QR",
                                description: "Scan a QR code to authorize an agent and add it to your contacts."
                            ) {
                                showAgentScanner = true
                            }

                            // Discover Agents Option
                            ConnectionOptionButton(
                                icon: "antenna.radiowaves.left.and.right",
                                iconColor: .orange,
                                title: "Discover Agents",
                                description: "Find AI agents on your local network—these can help with tasks, answer questions, and more.",
                                isLoading: agentService.isDiscovering
                            ) {
                                showAgentDiscovery = true
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Security Note
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .font(.title3)
                                .foregroundColor(.blue)

                            Text("Secure Connections")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        Text("All connections use end-to-end encryption with One-Time TDF technology to ensure your conversations remain private.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)

                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = URL(string: shareableLink) {
                ContactShareSheet(activityItems: [url], isPresented: $showShareSheet)
            }
        }
        .sheet(isPresented: $isSearchingNearby) {
            NearbyConnectionView(peerManager: peerManager) {
                isSearchingNearby = false
            }
        }
        .sheet(isPresented: $showAgentScanner) {
            AgentQRScannerView { request in
                showAgentScanner = false
                // Handle the authorization request
                sharedState.pendingAgentAuthRequest = request
            }
        }
        .sheet(isPresented: $showAgentDiscovery) {
            AgentDiscoverySheet(agentService: agentService) {
                showAgentDiscovery = false
            }
        }
    }

    private func startNearbyConnection() {
        isSearchingNearby = true
    }

    private func showInviteRemotely() {
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            shareableLink = "https://app.arkavo.com/connect/\(profile.publicID.base58EncodedString)"
            showShareSheet = true
        }
    }
}

// MARK: - Connection Option Button

struct ConnectionOptionButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundColor(iconColor)
                        .frame(width: 50, height: 50)
                        .background(iconColor.opacity(0.1))
                        .clipShape(Circle())

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Agent QR Scanner View

struct AgentQRScannerView: View {
    let onScan: (AgentAuthorizationRequest) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var scannedCode: String?
    @State private var error: String?
    @State private var showingAuth = false
    @State private var authRequest: AgentAuthorizationRequest?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let request = authRequest {
                    // Show authorization view
                    AgentAuthorizationView(
                        request: request,
                        onAuthorize: {
                            onScan(request)
                        },
                        onCancel: {
                            authRequest = nil
                            scannedCode = nil
                        }
                    )
                } else {
                    // Show scanner
                    QRCodeScannerView { code in
                        processScannedCode(code)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }

                    Text("Point your camera at an agent's QR code to authorize it.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .navigationTitle("Scan Agent QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func processScannedCode(_ code: String) {
        scannedCode = code
        error = nil

        // Parse the arkavo:// URL
        guard let url = URL(string: code),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let request = AgentAuthorizationRequest.from(components: components) else {
            error = "Invalid QR code. Expected an Arkavo agent authorization code."
            return
        }

        authRequest = request
    }
}

// MARK: - QR Code Scanner View

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScanner()
    }

    private func setupScanner() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        captureSession = AVCaptureSession()

        guard let captureSession = captureSession else { return }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {
            captureSession?.stopRunning()
            onCodeScanned?(stringValue)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}

// MARK: - Agent Discovery Sheet

struct AgentDiscoverySheet: View {
    let agentService: AgentService
    let onDismiss: () -> Void
    @State private var selectedAgent: AgentEndpoint?

    var discoveredAgents: [AgentEndpoint] {
        // Filter out device agent since it's always in contacts
        agentService.discoveredAgents.filter { !$0.id.lowercased().contains("local") }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if discoveredAgents.isEmpty {
                    Spacer()

                    VStack(spacing: 20) {
                        if agentService.isDiscovering {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                                .symbolEffect(.variableColor.iterative.reversing)

                            Text("Searching for agents...")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)

                            Text("No agents found")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Button("Start Discovery") {
                                agentService.startDiscovery()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text("Make sure agents are running on your local network.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                } else {
                    List {
                        Section {
                            ForEach(discoveredAgents, id: \.id) { agent in
                                AgentDiscoveryRow(agent: agent, agentService: agentService) {
                                    // Agent will be automatically added to contacts via UnifiedContactService
                                    onDismiss()
                                }
                            }
                        } header: {
                            Text("Available Agents")
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Discover Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            if !agentService.isDiscovering {
                agentService.startDiscovery()
            }
        }
    }
}

// MARK: - Agent Discovery Row

struct AgentDiscoveryRow: View {
    let agent: AgentEndpoint
    let agentService: AgentService
    let onSelect: () -> Void
    @State private var isConnecting = false

    var isConnected: Bool {
        agentService.isConnected(to: agent.id)
    }

    var body: some View {
        Button {
            if !isConnected {
                connectToAgent()
            }
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.metadata.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(agent.metadata.purpose)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label(agent.metadata.model, systemImage: "cpu")
                            .font(.caption2)
                            .foregroundColor(.blue)

                        Circle()
                            .fill(isConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(isConnected ? "Connected" : "Available")
                            .font(.caption2)
                            .foregroundColor(isConnected ? .green : .orange)
                    }
                }

                Spacer()

                if isConnecting {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func connectToAgent() {
        isConnecting = true
        Task {
            do {
                try await agentService.connect(to: agent)
            } catch {
                print("Failed to connect to agent: \(error)")
            }
            isConnecting = false
        }
    }
}

// MARK: - Nearby Connection View

struct NearbyConnectionView: View {
    @ObservedObject var peerManager: PeerDiscoveryManager
    let onDismiss: () -> Void
    @State private var selectedPeer: MCPeerID?
    @State private var showingConfirmation = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if peerManager.connectedPeers.isEmpty {
                    Spacer()

                    VStack(spacing: 20) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .symbolEffect(.variableColor.iterative.reversing)

                        Text("Searching for nearby devices...")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        Text("Make sure the other person has Arkavo open and is also searching for connections.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    Spacer()
                } else {
                    List {
                        Section {
                            ForEach(peerManager.connectedPeers, id: \.self) { peer in
                                Button {
                                    selectedPeer = peer
                                    showingConfirmation = true
                                } label: {
                                    HStack {
                                        Image(systemName: "person.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(peer.displayName)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            Text("Tap to connect")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        } header: {
                            Text("Connected Peers")
                                .font(.headline)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }

                VStack(spacing: 8) {
                    Label("Verify in Person", systemImage: "checkmark.shield")
                        .font(.footnote)
                        .foregroundColor(.green)

                    Text("For security, confirm the device name with the person before connecting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .navigationTitle("Connect Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        peerManager.stopSearchingForPeers()
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                do {
                    try await peerManager.setupMultipeerConnectivity()
                    try peerManager.startSearchingForPeers()
                } catch {
                    print("Failed to start peer discovery: \(error)")
                }
            }
        }
        .onDisappear {
            peerManager.stopSearchingForPeers()
        }
        .alert("Connect with \(selectedPeer?.displayName ?? "Unknown")?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedPeer = nil
            }
            Button("Connect") {
                if selectedPeer != nil {
                    onDismiss()
                }
            }
        } message: {
            Text("Make sure this is the person you want to connect with. They will receive a connection request.")
        }
    }
}

// MARK: - Share Sheet Helper

struct ContactShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

// MARK: - ArkavoKit Import

import ArkavoKit

#Preview {
    ContactsCreateView()
        .environmentObject(SharedState())
        .environmentObject(AgentService())
}
