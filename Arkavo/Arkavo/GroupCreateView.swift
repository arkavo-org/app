import MultipeerConnectivity
import SwiftUI
import UIKit // Needed for UIApplication

// Define TrustStatus enum here (moved from GroupView.peerRow)
// TODO: Consider moving this to a shared location if used elsewhere.
enum TrustStatus {
    case unknown, pending, verified, trusted, compromised

    var color: Color {
        switch self {
        case .unknown: .gray
        case .pending: .orange
        case .verified: .blue
        case .trusted: InnerCircleConstants.trustGreen // Use constant
        case .compromised: InnerCircleConstants.trustRed // Use constant
        }
    }

    var icon: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .pending: "hourglass"
        case .verified: "checkmark.seal"
        case .trusted: "lock.shield.fill" // Use constant icon name if available
        case .compromised: "exclamationmark.triangle.fill" // Use constant icon name if available
        }
    }

    var description: String {
        switch self {
        case .unknown: "Unknown"
        case .pending: "Verification Pending"
        case .verified: "Verified"
        case .trusted: "Trusted"
        case .compromised: "Compromised"
        }
    }
}

struct GroupCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: GroupViewModel

    @State private var groupName = ""
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager() // Add PeerManager
    @State private var isPeerSearchActive = false // Add state for search
    @State private var pulsate: Bool = false // Add state for pulsation animation
    @State private var selectedInnerCircleProfiles: [Profile] = [] // Profiles selected for the new group

    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isNameFieldFocused: Bool

    // Define constants needed by moved functions
    private let systemMargin: CGFloat = 16 // Define systemMargin

    var body: some View {
        Form {
            Section {
                TextField("Group Name", text: $groupName)
                    .focused($isNameFieldFocused)
                    .autocapitalization(.words)
                    .textContentType(.organizationName)
            } header: {
                Text("Group Details")
            } footer: {
                Text("This will be the name of your new group")
            }
            peerDiscoverySection()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    sharedState.showCreateView = false
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Create") {
                    Task {
                        await createGroup()
                        sharedState.showCreateView = false
                        dismiss()
                    }
                }
                // Enable button only if groupName is not empty (after trimming whitespace)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // --- START: Moved Peer Discovery Functions & Views from GroupView ---

    // --- 3. Peer Discovery Tools Section ---
    private func peerDiscoverySection() -> some View {
        // Note: This section might need adjustments based on where it's placed
        // within the GroupCreateView's Form structure.
        // Using Section for better integration into Form.
        Section("Connect to Peers (Optional)") {
            VStack(alignment: .leading, spacing: InnerCircleConstants.halfMargin) {
                // Contains the Discover button and the list of discovered/connecting peers
                innerCirclePeerDiscoveryUI()
                // Removed background/cornerRadius - let Section handle styling
            }
        }
    }

    // Inner Circle peer discovery UI (P2P related) - Refactored
    private func innerCirclePeerDiscoveryUI() -> some View {
        VStack(spacing: InnerCircleConstants.systemMargin) { // Use constant for spacing within this section
            // --- NEW: Prominent Search CTA ---
            Button {
                Task { await togglePeerSearch() }
            } label: {
                HStack(spacing: InnerCircleConstants.halfMargin) { // Use constant
                    Image(systemName: isPeerSearchActive ? "stop.circle.fill" : "antenna.radiowaves.left.and.right.circle.fill")
                        .font(.system(size: 22)) // Use guide size
                    Text(isPeerSearchActive ? "Stop Discovery" : "Discover Peers")
                        .font(InnerCircleConstants.primaryTextFont) // Use constant font
                        .fontWeight(.semibold) // Make text slightly bolder
                    if isPeerSearchActive {
                        Spacer() // Push pulse to right only when active
                        ProgressView().scaleEffect(0.8) // Simple pulse/activity indicator
                            .tint(InnerCircleConstants.primaryActionColor)
                    }
                }
                .padding(.vertical, InnerCircleConstants.halfMargin) // Use constant
                .padding(.horizontal, InnerCircleConstants.systemMargin) // Use constant
                .frame(maxWidth: .infinity)
                .background(isPeerSearchActive ? InnerCircleConstants.trustRed.opacity(0.15) : InnerCircleConstants.primaryActionColor.opacity(0.15)) // Use constant colors
                .foregroundColor(isPeerSearchActive ? InnerCircleConstants.trustRed : InnerCircleConstants.primaryActionColor) // Use constant colors
                .cornerRadius(InnerCircleConstants.cornerRadius) // Use constant
            }
            .buttonStyle(.plain) // Remove default button chrome

            // Discovered peers list view (or empty state)
            discoveredPeersView // Renamed for clarity
        }
    }

    // Toggle peer search state
    private func togglePeerSearch() async {
        isPeerSearchActive.toggle()

        if isPeerSearchActive {
            do {
                // Select this stream and start searching
                try await peerManager.setupMultipeerConnectivity()
                try peerManager.startSearchingForPeers()

                // Automatically present the browser controller for manual peer selection
                presentBrowserController() // Show browser by default
            } catch {
                // If there was an error starting peer search, show it to the user
                print("Failed to start peer search: \(error.localizedDescription)")
                // Update status via peerManager's published properties
                isPeerSearchActive = false // Revert state if failed
                // TODO: Show error to user in UI
                errorMessage = "Failed to start peer discovery: \(error.localizedDescription)"
                showError = true
            }
        } else {
            // Stop searching
            peerManager.stopSearchingForPeers()
        }
    }

    // Renamed and Refactored: Shows discovered/connecting peers
    private var discoveredPeersView: some View {
        VStack(spacing: InnerCircleConstants.halfMargin) { // Use constant
            let peerCount = peerManager.connectedPeers.count // Still relevant for count
            let connectionStatus = peerManager.connectionStatus // Still relevant for status

            // Show search status banner when active (Simplified)
            HStack {
                connectionStatusIndicator(status: connectionStatus)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                    Text("\(peerCount) \(peerCount == 1 ? "Peer" : "Peers")")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                }
            }
            // Show search status banner when active (Simplified)
            if case .searching = connectionStatus {
                Text("Scanning for nearby devices...")
                    .font(InnerCircleConstants.captionFont) // Use constant
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, InnerCircleConstants.halfMargin) // Use constant
            }

            // Show error message if there's an error (Keep existing logic)
            if case let .failed(error) = connectionStatus {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error.localizedDescription).font(.caption).foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                .padding(.horizontal, systemMargin / 4) // Use systemMargin multiple (4pt)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            // Divider only needed if peers are shown
            if peerCount > 0 {
                Divider().padding(.vertical, InnerCircleConstants.halfMargin) // Use constant
            }

            if peerCount > 0 {
                // Title for peers section (Adjust if showing "Discovered" vs "Connected")
                Text("Discovered Devices (\(peerCount))") // Updated title
                    .font(InnerCircleConstants.secondaryTextFont) // Use constant
                    .fontWeight(.medium)
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, InnerCircleConstants.halfMargin / 2) // Use constant

                // Show list of discovered/connected peers using the refactored peerRow
                LazyVStack(spacing: InnerCircleConstants.halfMargin) { // Use LazyVStack and constant
                    ForEach(peerManager.connectedPeers, id: \.self) { peer in
                        peerRow(peer: peer, profile: peerManager.connectedPeerProfiles[peer], peerManager: peerManager)
                    }
                }
            } else if isPeerSearchActive {
                // Show searching state only if no peers found yet
                searchingStateView()
            } else {
                // Show empty state if idle and no peers
                emptyStateView()
            }
        }
    }

    // Connection status indicator
    private func connectionStatusIndicator(status: ConnectionStatus) -> some View {
        HStack(spacing: 5) { // Added spacing
            Group { // Group for applying frame consistently
                switch status {
                case .idle:
                    Circle().fill(Color.gray)
                case .searching:
                    // Use pulsing animation for searching
                    Circle()
                        .fill(Color.blue)
                        .opacity(0.8)
                        .scaleEffect(pulsate ? 1.2 : 0.8) // Add pulsation
                        .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsate)
                case .connecting:
                    Circle().fill(Color.orange) // Changed color for connecting
                case .connected:
                    Circle().fill(Color.green)
                case .failed:
                    Circle().fill(Color.red)
                }
            }
            .frame(width: 10, height: 10) // Slightly larger indicator

            Text(statusText(for: status))
                .font(InnerCircleConstants.statusIndicatorFont) // Use constant
                .foregroundColor(statusColor(for: status))
        }
        .padding(.vertical, InnerCircleConstants.halfMargin / 2) // Add small vertical padding
        .onAppear { pulsate = true } // Start pulsation on appear
        .onDisappear { pulsate = false } // Stop pulsation on disappear
    }

    private func statusText(for status: ConnectionStatus) -> String {
        switch status {
        case .idle: "Inactive"
        case .searching: "Searching"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .idle: .gray
        case .searching: .blue
        case .connecting: .orange
        case .connected: .green
        case .failed: .red
        }
    }

    // Empty state view when no search is active
    private func emptyStateView() -> some View {
        VStack(spacing: systemMargin / 2) { // Use systemMargin multiple (8pt)
            Spacer().frame(height: systemMargin * 1.25) // Use systemMargin multiple (20pt)
            Image(systemName: "person.2.slash")
                .font(.system(size: 36)) // Use guide size
                .foregroundColor(.gray) // Use guide color

            Text("No Peers Discovered") // Updated title
                .font(InnerCircleConstants.headerFont.weight(.medium)) // Use constant font, adjust weight
                .foregroundColor(InnerCircleConstants.primaryTextColor) // Use constant

            Text("Tap 'Discover Peers' to find nearby devices.") // Simplified text for create view
                .font(InnerCircleConstants.secondaryTextFont) // Use constant
                .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                .multilineTextAlignment(.center)
                .padding(.horizontal, InnerCircleConstants.systemMargin) // Use constant
        }
        .padding(.vertical, InnerCircleConstants.doubleMargin) // Use constant for vertical padding
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, systemMargin / 2) // Use systemMargin multiple (8pt)
    }

    // Searching state view when actively looking for peers
    private func searchingStateView() -> some View {
        VStack(spacing: systemMargin / 2) { // Use systemMargin multiple (8pt)
            Spacer().frame(height: systemMargin * 0.625) // Use systemMargin multiple (10pt)
            SignalPulseView().frame(width: 50, height: 50)
            Text("Scanning for Devices...").font(.callout).foregroundColor(.secondary)
            Text("Ensure other devices are also searching.").font(.caption2).foregroundColor(.secondary.opacity(0.8))
            Spacer().frame(height: systemMargin * 0.625) // Use systemMargin multiple (10pt)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, systemMargin / 2) // Use systemMargin multiple (8pt)
    }

    // Present the browser controller manually
    private func presentBrowserController() {
        if let browserVC = peerManager.getPeerBrowser(),
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootController = windowScene.windows.first?.rootViewController
        {
            // Dismiss existing presentation if any before presenting new one
            rootController.presentedViewController?.dismiss(animated: false)
            rootController.present(browserVC, animated: true)
        } else {
            print("Could not get browser view controller or root view controller.")
        }
    }

    private func peerRow(peer: MCPeerID, profile: Profile?, peerManager: PeerDiscoveryManager) -> some View {
        // Determine trust status (Placeholder - needs real logic)
        let trustStatus: TrustStatus = profile != nil ? .verified : .pending // Example logic
        // KeyStore Percentage - Placeholder: This needs data about the *peer's* keystore or local status in context
        let keyStorePercentage = 0.85 // Placeholder value

        return HStack(spacing: InnerCircleConstants.systemMargin) { // Use constant
            // Avatar with trust indicator
            ZStack(alignment: .bottomTrailing) {
                // Trust indicator badge
                Circle()
                    .fill(trustStatus.color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: trustStatus.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white) // Ensure contrast
                    )
                    .accessibilityLabel(Text("Trust status: \(trustStatus.description)"))
            }

            // Peer Info
            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.name ?? peer.displayName)
                    .font(InnerCircleConstants.primaryTextFont) // Use constant
                    .fontWeight(.semibold)
                    .foregroundColor(InnerCircleConstants.primaryTextColor) // Use constant

                Text(trustStatus.description)
                    .font(InnerCircleConstants.statusIndicatorFont) // Use constant
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant

                // Connection Time (if available and connected)
                if let time = peerManager.peerConnectionTimes[peer] {
                    Text("Connected \(connectionTimeString(time))")
                        .font(InnerCircleConstants.captionFont) // Use constant
                        .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                } else if profile == nil {
                    Text("Connecting...") // Show connecting if profile not loaded
                        .font(InnerCircleConstants.captionFont)
                        .foregroundColor(InnerCircleConstants.secondaryTextColor)
                }
            }

            Spacer()

            // Action Buttons
            HStack(spacing: InnerCircleConstants.halfMargin) { // Use constant
                // Add Peer Button (Only for verified peers)
                if let verifiedProfile = profile {
                    let isSelected = selectedInnerCircleProfiles.contains { $0.id == verifiedProfile.id }
                    Button {
                        // Action: Only toggle selection state locally for this view
                        if !isSelected {
                            selectedInnerCircleProfiles.append(verifiedProfile)
                            print("Selected \(verifiedProfile.name) for new group.")
                        } else {
                            selectedInnerCircleProfiles.removeAll { $0.id == verifiedProfile.id }
                            print("Deselected \(verifiedProfile.name) for new group.")
                        }
                        // NOTE: No changes are made to the actual InnerCircle stream model or persisted here.
                        // This state is used only when the 'Create' button is tapped.
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold)) // Keep icon size
                            .foregroundColor(isSelected ? .green : InnerCircleConstants.primaryActionColor)
                            .frame(minWidth: InnerCircleConstants.minimumTouchTarget, minHeight: InnerCircleConstants.minimumTouchTarget)
                    }
                    .accessibilityLabel(Text(isSelected ? "Remove \(verifiedProfile.name) from group" : "Add \(verifiedProfile.name) to group"))
                    .help(isSelected ? "Remove from group" : "Add to group")
                }

                // Example: Key Renewal Button (Placeholder Logic)
                if trustStatus == .trusted { // Only show for trusted peers
                    Button {
                        // TODO: Implement Key Renewal Initiation
                        print("Initiate Key Renewal with \(peer.displayName)")
                    } label: {
                        Image(systemName: "key.fill") // Icon for renewal
                            .font(.system(size: 18, weight: .semibold)) // Use guide size
                            .foregroundColor(keyStorePercentage < 0.1 ? InnerCircleConstants.trustYellow : InnerCircleConstants.secondaryTextColor) // Highlight if low
                            .frame(minWidth: InnerCircleConstants.minimumTouchTarget, minHeight: InnerCircleConstants.minimumTouchTarget) // Ensure touch target
                    }
                    .accessibilityLabel(Text("Renew keys with \(profile?.name ?? peer.displayName)"))
                    .disabled(keyStorePercentage >= 0.1) // Example disable logic
                }
            }
        }
        .padding(.horizontal, InnerCircleConstants.halfMargin) // Spacing between cards
    }

    // Format the connection time
    private func connectionTimeString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        // Use the static constant defined in this struct
        if timeInterval < 60 { return "just now" }
        if timeInterval < 3600 { let minutes = Int(timeInterval / 60); return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
        if timeInterval < 86400 { let hours = Int(timeInterval / 3600); return "\(hours) hour\(hours == 1 ? "" : "s") ago" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // Animated signal pulse for searching animation
    struct SignalPulseView: View {
        @State private var scale: CGFloat = 1.0
        @State private var rotation: Double = 0.0
        @State private var pulsate: Bool = false // Local state for this view

        var body: some View {
            ZStack {
                ZStack {
                    ForEach(0 ..< 3) { i in
                        Circle().stroke(Color.blue.opacity(0.7 - Double(i) * 0.2), lineWidth: 1).scaleEffect(scale - CGFloat(i) * 0.1)
                    }
                }.scaleEffect(pulsate ? 1.2 : 0.8)
                Circle().trim(from: 0.2, to: 0.8).stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3])).rotationEffect(.degrees(rotation)).scaleEffect(0.7)
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 12, height: 12)
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                }
            }
            .onAppear {
                // Use the local pulsate state for animation control
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsate = true }
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) { rotation = 360 }
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) { scale = 1.1 }
            }
            .onDisappear {
                pulsate = false // Stop animation on disappear if needed
            }
        }
    }

    // --- END: Moved Peer Discovery Functions & Views ---

    private func createGroup() async {
        do {
            let groupProfile = Profile(name: groupName)

            let newStream = Stream(
                creatorPublicID: ViewModelFactory.shared.getCurrentProfile()!.publicID,
                profile: groupProfile,
                policies: Policies(admission: .openInvitation, interaction: .open, age: .onlyKids) // Example policies
            )
            print("Creating new stream: \(newStream.profile.name) (\(newStream.publicID.base58EncodedString))")

            // --- Add selected peers to the new stream's InnerCircle ---
            // Fetch the profiles from the context to ensure they are managed instances
            var managedSelectedProfiles: [Profile] = []
            for selectedProfile in selectedInnerCircleProfiles {
                if let managedProfile = try await PersistenceController.shared.fetchProfile(withPublicID: selectedProfile.publicID) {
                    managedSelectedProfiles.append(managedProfile)
                } else {
                    print("⚠️ Warning: Could not fetch managed profile for \(selectedProfile.name) (\(selectedProfile.publicID.base58EncodedString)). Skipping addition to new stream.")
                }
            }
            newStream.innerCircleProfiles = managedSelectedProfiles // Assign the managed profiles
            print("   Added \(newStream.innerCircleProfiles.count) selected profiles to the new stream's InnerCircle.")
            // --- END Add selected peers ---

            // Add the new stream to the account
            let account = ViewModelFactory.shared.getCurrentAccount()!
            // Ensure the stream is inserted into the context before associating with the account
            PersistenceController.shared.mainContext.insert(newStream)
            account.streams.append(newStream)
            print("   Added new stream to account.")

            // Save all changes (account relationship, new stream, inner circle members)
            try await PersistenceController.shared.saveChanges()
            print("   Saved changes to persistence.")

            // Update shared state to navigate to the new stream
            await MainActor.run {
                sharedState.selectedStreamPublicID = newStream.publicID
                // Optionally navigate or update UI further
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create group: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
