import SwiftUI
import MultipeerConnectivity

struct ContactsCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager()
    @State private var isSearchingNearby = false
    @State private var showShareSheet = false
    @State private var shareableLink: String = ""
    
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
                        
                        Text("Build your trusted network")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Connection Options
                    VStack(spacing: 20) {
                        // Connect Nearby Option
                        Button {
                            startNearbyConnection()
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.title)
                                        .foregroundColor(.blue)
                                        .frame(width: 50, height: 50)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())
                                    
                                    Spacer()
                                    
                                    if isSearchingNearby {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Connect Nearby")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text("Add someone you know who's right beside you—verify in person to grow your trusted network.")
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
                        
                        // Invite Remotely Option
                        Button {
                            showInviteRemotely()
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.green)
                                        .frame(width: 50, height: 50)
                                        .background(Color.green.opacity(0.1))
                                        .clipShape(Circle())
                                    
                                    Spacer()
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Invite Remotely")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text("Send your Arkavo link with the iOS Share Sheet to connect with someone you already know—no matter the distance.")
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
    }
    
    private func startNearbyConnection() {
        isSearchingNearby = true
        // The NearbyConnectionView will handle the actual peer discovery
    }
    
    private func showInviteRemotely() {
        // Generate a shareable link for the user's profile
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            shareableLink = "https://app.arkavo.com/connect/\(profile.publicID.base58EncodedString)"
            showShareSheet = true
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
                // Searching Animation
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
                    // Found Peers List
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
                
                // Instructions
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
            do {
                try peerManager.startSearchingForPeers()
            } catch {
                print("Failed to start peer discovery: \(error)")
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
                    // Connection is already established since they appear in connectedPeers
                    // Just dismiss the view
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
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            isPresented = false
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContactsCreateView()
        .environmentObject(SharedState())
}