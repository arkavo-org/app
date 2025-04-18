import MultipeerConnectivity // Needed for MCPeerID in InnerCircleMemberRow
import OpenTDFKit
import SwiftData // Needed for Profile in InnerCircleMemberRow
import SwiftUI

// MARK: - InnerCircle UI Constants and Enums

// Constants for consistent styling within InnerCircle related views
enum InnerCircleConstants {
    static let systemMargin: CGFloat = 16
    static let halfMargin: CGFloat = systemMargin / 2
    static let doubleMargin: CGFloat = systemMargin * 2

    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8

    static let minimumTouchTarget: CGFloat = 44

    // Typography
    static let headerFont: Font = .system(size: 20, weight: .bold)
    static let primaryTextFont: Font = .system(size: 17, weight: .regular)
    static let secondaryTextFont: Font = .system(size: 15, weight: .regular)
    static let statusIndicatorFont: Font = .system(size: 13, weight: .semibold)
    static let captionFont: Font = .system(size: 12, weight: .regular) // Example caption size

    // Colors (Examples based on guide)
    static let primaryActionColor: Color = .blue // #007AFF
    static let trustGreen: Color = .init(red: 52 / 255, green: 199 / 255, blue: 89 / 255) // #34C759
    static let trustYellow: Color = .init(red: 255 / 255, green: 204 / 255, blue: 0 / 255) // #FFCC00
    static let trustRed: Color = .init(red: 255 / 255, green: 59 / 255, blue: 48 / 255) // #FF3B30
    static let backgroundColor: Color = .black // #000000 (Assuming dark mode focus)
    static let cardBackgroundColor: Color = .init(.systemGray6) // #1C1C1E (Example dark mode card bg)
    static let primaryTextColor: Color = .white
    static let secondaryTextColor: Color = .gray
}

// MARK: - InnerCircle Member Views

// Main view for displaying all InnerCircle members
struct InnerCircleView: View {
    let stream: Stream
    @ObservedObject var peerManager: PeerDiscoveryManager // Use @ObservedObject
    @EnvironmentObject var sharedState: SharedState
    @State private var showOfflineMembers: Bool = true
    @State private var searchText: String = ""
    @State private var innerCircleProfiles: [Profile] = [] // All profiles belonging to this InnerCircle
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var refreshObserver: NSObjectProtocol? // Observer token
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            searchAndFilterBar

            // Member count header
            memberCountHeader

            Divider()

            // Members list
            membersScrollView
        }
        .onAppear {
            setupView() // Call setup function
            setupNotificationObservers() // Setup observers
        }
        .onDisappear {
            removeNotificationObservers() // Remove observers
        }
        .overlay(statusMessageOverlay)
        // Refresh UI when key exchange states change
        .onChange(of: peerManager.peerKeyExchangeStates) { _, _ in
            // This ensures the UI updates when a state changes for any peer
            print("InnerCircleView: Detected change in peerKeyExchangeStates")
        }
    }

    // MARK: - Setup and Teardown

    // Initial setup when the view appears
    private func setupView() {
        Task {
            await loadInnerCircleProfiles()
        }
        checkForStatusMessage()
    }

    // Setup notification observers
    private func setupNotificationObservers() {
        // Listen for notifications to refresh the member list
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .refreshInnerCircleMembers,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await loadInnerCircleProfiles()
            }
        }
    }

    // Remove notification observers
    private func removeNotificationObservers() {
        if let observer = refreshObserver {
            NotificationCenter.default.removeObserver(observer)
            refreshObserver = nil
        }
    }

    // Check for and display any pending status messages
    private func checkForStatusMessage() {
        if let message = sharedState.getState(forKey: "statusMessage") as? String, !message.isEmpty {
            statusMessage = message
            showStatusMessage = true
            // Clear the message after retrieving it
            sharedState.setState("", forKey: "statusMessage")
        }
    }

    // MARK: - Computed Properties (Refactored for Simplicity)

    // All currently connected online profiles from peer manager
    private var onlineProfiles: [Profile] {
        Array(peerManager.connectedPeerProfiles.values)
    }

    // All offline profiles (in InnerCircle but not currently connected)
    private var offlineProfiles: [Profile] {
        // Get IDs of online profiles for efficient lookup
        let onlineProfileIDs = Set(onlineProfiles.map(\.id))
        // Filter the full list of InnerCircle members
        return innerCircleProfiles.filter { profile in
            !onlineProfileIDs.contains(profile.id)
        }
    }

    // Filtered online profiles based on search text
    private var filteredOnlineProfiles: [Profile] {
        let profiles = onlineProfiles // Start with online profiles
        if searchText.isEmpty {
            return profiles // No filter needed
        } else {
            // Apply search filter
            return profiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // Filtered offline profiles based on search text
    private var filteredOfflineProfiles: [Profile] {
        let profiles = offlineProfiles // Start with offline profiles
        if searchText.isEmpty {
            return profiles // No filter needed
        } else {
            // Apply search filter
            return profiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // MARK: - Helper Functions

    // Check if a profile is currently online via P2P
    private func isProfileOnline(_ profile: Profile) -> Bool {
        // Check if any profile in the connectedPeerProfiles dictionary has the same ID
        peerManager.connectedPeerProfiles.values.contains { $0.id == profile.id }
    }

    // Load all InnerCircle profiles by fetching the stream from the context
    @MainActor // Ensure context access is on the main thread
    private func loadInnerCircleProfiles() async {
        print("InnerCircleView: Attempting to fetch stream '\(stream.profile.name)' (ID: \(stream.publicID.base58EncodedString)) from context.")

        let context = PersistenceController.shared.container.mainContext
        let streamID = stream.persistentModelID // Get the persistent ID of the stream passed in

        // Fetch the stream using its persistent ID
        guard let fetchedStream = context.model(for: streamID) as? Stream else {
            print("❌ InnerCircleView: Failed to fetch stream with ID \(streamID) from context.")
            innerCircleProfiles = [] // Clear profiles on failure
            return
        }

        print("InnerCircleView: Successfully fetched stream '\(fetchedStream.profile.name)' from context.")
        print("InnerCircleView: Fetched stream has \(fetchedStream.innerCircleProfiles.count) profiles in its relationship.")

        // Assign the profiles from the *fetched* stream object to the @State variable.
        // This assignment is what should trigger the UI update.
        innerCircleProfiles = fetchedStream.innerCircleProfiles

        print("InnerCircleView: Assigned \(innerCircleProfiles.count) profiles to @State innerCircleProfiles.")
        if innerCircleProfiles.isEmpty, !fetchedStream.innerCircleProfiles.isEmpty {
            print("⚠️ InnerCircleView: Warning - @State innerCircleProfiles is empty even though fetched stream object had profiles.")
        } else if !innerCircleProfiles.isEmpty {
            print("InnerCircleView: First loaded profile name: \(innerCircleProfiles.first?.name ?? "N/A")")
        }
    }

    // Get connection time for an online profile
    private func getConnectionTime(for profile: Profile) -> Date? {
        // Find the MCPeerID for this profile
        for (peer, peerProfile) in peerManager.connectedPeerProfiles {
            if peerProfile.id == profile.id {
                return peerManager.peerConnectionTimes[peer]
            }
        }
        return nil
    }

    // MARK: - Subviews

    private var searchAndFilterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search", text: $searchText)
                .font(.subheadline)
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        .background(Color(.secondarySystemBackground))
    }

    private var memberCountHeader: some View {
        HStack {
            // Use the computed properties for counts
            Text("(\(onlineProfiles.count) online, \(offlineProfiles.count) offline)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                Task {
                    await loadInnerCircleProfiles()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
    }

    private var membersScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Online members section
                let onlineToShow = filteredOnlineProfiles
                if !onlineToShow.isEmpty {
                    sectionHeader(title: "Online", count: onlineToShow.count)

                    ForEach(onlineToShow) { profile in
                        InnerCircleMemberRow(
                            profile: profile,
                            isOnline: true,
                            connectionTime: getConnectionTime(for: profile),
                            stream: stream,
                            peerManager: peerManager // Pass peerManager
                        )
                        .padding(.horizontal, systemMargin) // Use systemMargin
                        .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                        .environmentObject(sharedState)
                    }
                }

                // Offline members section
                let offlineToShow = filteredOfflineProfiles
                if showOfflineMembers, !offlineToShow.isEmpty {
                    sectionHeader(title: "Offline", count: offlineToShow.count)

                    ForEach(offlineToShow) { profile in
                        InnerCircleMemberRow(
                            profile: profile,
                            isOnline: false,
                            // lastSeen removed
                            stream: stream,
                            peerManager: peerManager // Pass peerManager
                        )
                        .padding(.horizontal, systemMargin) // Use systemMargin
                        .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                        .environmentObject(sharedState)
                    }
                }

                // Empty state
                if onlineToShow.isEmpty, offlineToShow.isEmpty || !showOfflineMembers {
                    emptyStateView
                }
            }
            .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        }
    }

    // Section header view
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
        .background(Color(.systemGroupedBackground))
    }

    // Empty state view
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("No Members Found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ?
                "There are no members to display." :
                "No members match your search.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, systemMargin) // Use systemMargin
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, systemMargin * 2.5) // Use systemMargin multiple (40pt)
    }

    // Status message overlay
    @ViewBuilder
    private var statusMessageOverlay: some View {
        if showStatusMessage {
            VStack {
                Text(statusMessage)
                    .foregroundColor(.white)
                    .padding(systemMargin) // Use systemMargin
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(10)
                    .padding(systemMargin) // Use systemMargin
                    .onAppear {
                        // Auto-dismiss after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showStatusMessage = false
                        }
                    }
                Spacer()
            }
        }
    }
}

// Row view for individual InnerCircle members
struct InnerCircleMemberRow: View {
    let profile: Profile
    let isOnline: Bool
    var connectionTime: Date? = nil
    // Removed lastSeen property as it's no longer in Profile
    // var lastSeen: Date? = nil
    @EnvironmentObject var sharedState: SharedState
    var stream: Stream
    @ObservedObject var peerManager: PeerDiscoveryManager // Use @ObservedObject
    @State private var showRemoveConfirmation = false
    @State private var showDisconnectConfirmation = false // State for disconnect confirmation
    @State private var publicKeyCount: Int? = nil // State for public key count
    @State private var privateKeyCount: Int? = nil // State for private key count
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16

    // Computed property to get the current key exchange state for this profile (if online)
    private var keyExchangeState: KeyExchangeState? {
        guard isOnline, let peer = peerManager.findPeer(byProfileID: profile.publicID) else {
            return nil
        }
        return peerManager.peerKeyExchangeStates[peer]?.state
    }

    // Computed property to determine if the key exchange button should be disabled
    private var isKeyExchangeButtonDisabled: Bool {
        guard isOnline, let state = keyExchangeState else {
            return true // Disable if offline or no state found
        }
        // Disable unless idle or failed (allow retry from failed)
        switch state {
        case .idle, .failed:
            return false
        default:
            return true
        }
    }

    var body: some View {
        HStack {
            // Avatar
            avatarView
                .frame(width: 40, height: 40)

            // Profile info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if isOnline {
                    if let time = connectionTime {
                        Text("Connected \(timeAgoString(time))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Online")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    // Display Key Exchange Status (if online) and Key Count (always)
                    HStack(spacing: 6) { // Group status and count
                        // Removed redundant inner if isOnline check
                        keyExchangeStatusView() // Show status only when online
                        profileKeyCountView() // Renamed: Show key counts regardless of online status
                    }
                    .font(.caption2) // Smaller font for status line
                    .padding(.top, 1)

                } else {
                    // Offline: Show only the key count view
                    profileKeyCountView() // Renamed
                        .font(.caption2)
                        .padding(.top, 1)
                }
            }

            Spacer()

            // Status indicator (Online/Offline dot)
            statusIndicator

            // Message button - Only enabled for online peers
            Button(action: {
                // Open chat with this member
                if isOnline {
                    openDirectChat()
                }
            }) {
                Image(systemName: "message")
                    .font(.subheadline)
                    .foregroundColor(isOnline ? .blue : .gray)
                    .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
                    .background(Circle().fill(isOnline ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!isOnline)

            // Key Exchange Button - Only show for online peers
            if isOnline {
                keyExchangeButton() // <-- INTEGRATED KEY EXCHANGE BUTTON

                // Disconnect Button - Only show for online peers
                disconnectButton() // <-- NEW DISCONNECT BUTTON
            }

            // Remove member button (Keep this for removing from InnerCircle entirely)
            Button(action: {
                showRemoveConfirmation = true
            }) {
                Image(systemName: "person.fill.xmark")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
                    .background(Circle().fill(Color.red.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .alert("Remove Member", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    removeFromInnerCircle()
                }
            } message: {
                Text("Are you sure you want to remove \(profile.name) from your InnerCircle? They will no longer be able to communicate directly with you.")
            }
        }
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        .padding(.horizontal, systemMargin * 0.75) // Use systemMargin multiple (12pt)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        // Add alert for disconnect confirmation
        .alert("Disconnect P2P with \(profile.name)?", isPresented: $showDisconnectConfirmation) { // Updated Title
            Button("Cancel", role: .cancel) {}
            Button("Disconnect") { // Removed destructive role
                disconnectPeer()
            }
        } message: {
            // Updated Message
            Text("This will end your direct peer-to-peer connection. \(profile.name) will remain in your InnerCircle, but key exchange and secure messaging will require reconnecting.")
        }
        .onAppear {
            Task {
                await calculateKeyCounts()
            }
        }
    }

    // Helper function to calculate public and private key counts from profile data
    private func calculateKeyCounts() async {
        // Reset counts initially
        await MainActor.run {
            publicKeyCount = nil
            privateKeyCount = nil
        }

        // Calculate Public Key Count
        if let publicKeyData = profile.keyStorePublic, !publicKeyData.isEmpty {
            do {
                let publicKeyStore = PublicKeyStore(curve: .secp256r1) // Assuming curve
                try await publicKeyStore.deserialize(from: publicKeyData)
                let count = await (publicKeyStore.publicKeys).count
                // print("Calculated public key count for \(profile.name): \(count)")
                await MainActor.run { publicKeyCount = count } // Update state
            } catch {
                print("❌ Error calculating public key count for \(profile.name): \(error)")
                // Keep publicKeyCount as nil on error
            }
        } else {
            print("Profile \(profile.name) has no/empty public KeyStore data.")
        }

        // Calculate Private Key Count (if data exists)
        if let privateKeyData = profile.keyStorePrivate, !privateKeyData.isEmpty {
            do {
                let privateKeyStore = KeyStore(curve: .secp256r1) // Assuming curve
                try await privateKeyStore.deserialize(from: privateKeyData)
                let count = await privateKeyStore.getKeyCount()
                // print("Calculated private key count for \(profile.name): \(count)")
                await MainActor.run { privateKeyCount = count } // Update state
            } catch {
                // Log error, including profile name for context
                print("❌ Error calculating private key count for profile \(profile.name): \(error)")
                // Keep privateKeyCount as nil on error
            }
        } else {
            // This is expected for peers shown in this view.
            // Log less verbosely or remove if too noisy.
            // print("Profile \(profile.name) has no private KeyStore data (expected for peer).")
        }
    }

    // Open direct chat with this member
    private func openDirectChat() {
        // Set the InnerCircle stream as selected
        sharedState.selectedStreamPublicID = stream.publicID

        // Show chat overlay
        sharedState.showChatOverlay = true

        // Store the selected profile for direct messaging
        sharedState.setState(profile, forKey: "selectedDirectMessageProfile")
    }

    // Avatar view
    private var avatarView: some View {
        let initials = profile.name.prefix(2).uppercased()
        let color = avatarColor(for: profile.publicID)

        return ZStack {
            Circle()
                .fill(color)
            Text(initials)
                .font(.subheadline.bold())
                .foregroundColor(.white)
        }
    }

    // Status indicator
    private var statusIndicator: some View {
        Group {
            if isOnline {
                // Online indicator
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            } else {
                // Offline indicator
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
            }
        }
    }

    // Generate avatar color from profile ID
    private func avatarColor(for data: Data) -> Color {
        var hash = 0
        for byte in data {
            hash = hash &* 31 &+ Int(byte)
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }

    // Format time ago string
    private func timeAgoString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        if timeInterval < 60 { return "just now" }
        if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        }
        if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        if timeInterval < 604_800 { // 7 days
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // Remove member from InnerCircle
    private func removeFromInnerCircle() {
        Task { @MainActor in // Ensure execution on main actor
            do {
                // 1. Find the MCPeerID associated with the profile being removed
                var peerToDisconnect: MCPeerID?
                for (peer, connectedProfile) in peerManager.connectedPeerProfiles {
                    if connectedProfile.id == profile.id {
                        peerToDisconnect = peer
                        break
                    }
                }

                // 2. Remove KeyStore data for this profile
                // Use PersistenceController directly as it's a singleton or accessible
                try await PersistenceController.shared.deleteKeyStoreDataFor(profile: profile)

                // 3. Remove the profile from this stream's members list
                stream.removeFromInnerCircle(profile)
                try await PersistenceController.shared.saveChanges() // Save changes after modifying stream

                // 4. Disconnect the peer if they are currently connected
                if let peer = peerToDisconnect {
                    print("Disconnecting peer \(peer.displayName) associated with removed profile \(profile.name)")
                    peerManager.disconnectPeer(peer) // Use the existing method
                } else {
                    print("Peer for profile \(profile.name) was not connected, no disconnection needed.")
                }

                // 5. Update the UI to reflect the member is removed
                // The list should refresh when InnerCircleView's loadInnerCircleProfiles is called

                // 6. Show an optional toast/banner notifying that the member was removed
                sharedState.setState("Successfully removed \(profile.name) from your InnerCircle", forKey: "statusMessage")

                // 7. Trigger a refresh of the members list
                NotificationCenter.default.post(name: .refreshInnerCircleMembers, object: nil)

            } catch {
                print("Error removing member from InnerCircle: \(error)")
                // Show error message
                sharedState.setState("Failed to remove \(profile.name): \(error.localizedDescription)", forKey: "errorMessage")
            }
        }
    }

    // MARK: - Disconnect Action

    // Disconnect from the peer
    private func disconnectPeer() {
        guard let peer = peerManager.findPeer(byProfileID: profile.publicID) else {
            print("❌ Disconnect Error: Could not find MCPeerID for profile \(profile.name) to disconnect.")
            // Optionally show an error to the user
            sharedState.setState("Could not find peer to disconnect.", forKey: "errorMessage")
            return
        }
        print("Disconnecting from peer: \(peer.displayName)")
        peerManager.disconnectPeer(peer)
        // UI should update automatically based on peerManager's published changes
    }

    // MARK: - Key Exchange UI Helpers

    // View to display the current key exchange status text and icon
    @ViewBuilder
    private func keyExchangeStatusView() -> some View {
        if let state = keyExchangeState {
            let (text, icon, color) = displayInfo(for: state)
            HStack(spacing: 3) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10) // Smaller icon
                        .foregroundColor(color)
                }
                Text(text)
                    .foregroundColor(color)
            }
            // Add animation for state changes
            .animation(.easeInOut(duration: 0.3), value: state)
        } else {
            // Default view if no state (or offline) - Indicate keys are ready/default state
            HStack(spacing: 3) {
                Image(systemName: "lock.shield") // Use a neutral icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundColor(.gray) // Neutral color
                Text("Secure") // Neutral text
                    .foregroundColor(.gray)
            }
        }
    }

    // Renamed: View to display profile's public/private key counts
    @ViewBuilder
    private func profileKeyCountView() -> some View {
        HStack(spacing: 8) { // Add spacing between public/private counts
            // Public Key Count Display
            Group {
                if let count = publicKeyCount {
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill") // Icon for public keys
                            .resizable().aspectRatio(contentMode: .fit).frame(width: 10, height: 10)
                        Text("\(count)")
                    }
                    .help("Available Public Keys: \(count)")
                } else if profile.keyStorePublic != nil, !profile.keyStorePublic!.isEmpty {
                    ProgressView().scaleEffect(0.5).frame(width: 10, height: 10) // Loading for public
                } else {
                    EmptyView() // No public data
                }
            }
            .foregroundColor(.gray)

            // Private Key Count Display (Removed isLocal check - this view only shows peers)
            // This section will now effectively be hidden as privateKeyCount will always be nil for peers.
            // We could remove it entirely, but keeping the structure allows for potential future changes.
            // The calculation in calculateKeyCounts will handle not attempting to load private data for peers.
            Group {
                if let count = privateKeyCount { // This will likely never be true for peers
                    HStack(spacing: 3) {
                        Image(systemName: "lock.keyhole") // Icon for private keys
                            .resizable().aspectRatio(contentMode: .fit).frame(width: 10, height: 10)
                        Text("\(count)")
                    }
                    .help("Available Private Keys: \(count)")
                } else if profile.keyStorePrivate != nil, !profile.keyStorePrivate!.isEmpty {
                    // Show loading indicator *only if* data exists but count is not yet calculated
                    ProgressView().scaleEffect(0.5).frame(width: 10, height: 10) // Loading for private
                } else {
                    // Show empty view if there's no private data at all
                    EmptyView() // No private data for local user (or error calculating)
                }
            }
            .foregroundColor(.orange) // Different color for private count
            // End of Private Key Count Display section
        }
    }

    // Button for initiating or retrying key exchange
    @ViewBuilder
    private func keyExchangeButton() -> some View {
        let keyState: KeyExchangeState = keyExchangeState ?? .idle // Default to idle if nil
        let isFailed = if case KeyExchangeState.failed = keyState { true } else { false }
        let (text, _, color) = displayInfo(for: keyState) // Get text and color
        let isDisabled = isKeyExchangeButtonDisabled

        Button {
            // Find the peer and initiate regeneration
            if let peer = peerManager.findPeer(byProfileID: profile.publicID) {
                Task {
                    do {
                        print("UI: Initiating key regeneration with peer \(peer.displayName) for profile \(profile.name)")
                        try await peerManager.initiateKeyRegeneration(with: peer)
                        print("UI: Key regeneration initiated successfully for \(profile.name)")
                    } catch {
                        print("❌ UI: Failed to initiate key regeneration for \(profile.name): \(error)")
                        // Optionally show an error to the user (e.g., using an alert or status message)
                        sharedState.setState("Key exchange failed: \(error.localizedDescription)", forKey: "errorMessage") // Example error handling
                    }
                }
            } else {
                print("❌ UI: Could not find MCPeerID for profile \(profile.name) to initiate key exchange.")
            }
        } label: {
            Group {
                switch keyState {
                case .idle:
                    Image(systemName: "key.radiowaves.forward")
                        .foregroundColor(.blue)
                case KeyExchangeState.failed:
                    Image(systemName: "arrow.clockwise") // Retry icon
                        .foregroundColor(.orange)
                case .completed:
                    Image(systemName: "checkmark.shield")
                        .foregroundColor(.green)
                case .requestSent, .requestReceived, .offerSent, .offerReceived, .ackSent, .ackReceived, .commitSent:
                    ProgressView() // Show spinner while in progress
                        .scaleEffect(0.6) // Smaller spinner
                        .frame(width: 16, height: 16) // Ensure consistent size
                        .tint(.orange) // Tint spinner orange during progress
                case .commitReceivedWaitingForKeys:
                    ProgressView() // Show spinner while waiting for peer keys
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                        .tint(.orange)
                }
            }
            .font(.subheadline) // Match message icon size
            .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
            // Use clear background when disabled or completed, otherwise use tinted background
            .background(Circle().fill((isDisabled && !isFailed) ? Color.clear : color.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // Add tooltip/help text
        .help(isDisabled ? text : (isFailed ? "Retry Key Exchange" : "Initiate Key Exchange"))
        // Add animation for state changes
        .animation(.easeInOut(duration: 0.3), value: keyState)
    }

    // MARK: - Disconnect Button UI

    // Button for disconnecting from an online peer
    @ViewBuilder
    private func disconnectButton() -> some View {
        Button {
            showDisconnectConfirmation = true
        } label: {
            Image(systemName: "antenna.radiowaves.left.and.right.slash") // Updated SF Symbol
                .font(.subheadline) // Match other action button icon size
                .foregroundColor(.blue) // Use blue color for network action
                .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
                .background(Circle().fill(Color.blue.opacity(0.1))) // Blue tinted background
        }
        .buttonStyle(.plain)
        .disabled(!isOnline) // Disable if not P2P connected
        .opacity(isOnline ? 1.0 : 0.4) // Apply opacity when disabled
        .help("Disconnect from \(profile.name)") // Accessibility hint
        .accessibilityLabel("Disconnect from \(profile.name)") // Accessibility label
    }

    // MARK: - Key Exchange Display Info Helper

    // Helper to get display info based on KeyExchangeState
    private func displayInfo(for state: KeyExchangeState) -> (text: String, icon: String?, color: Color) {
        switch state {
        case .idle:
            return ("Ready to Exchange", "key.radiowaves.forward", .blue)
        case .requestSent:
            return ("Request Sent", "paperplane", .orange)
        case .requestReceived:
            return ("Request Received", "envelope.badge", .orange)
        case .offerSent:
            return ("Offer Sent", "paperplane.fill", .orange)
        case .offerReceived:
            return ("Offer Received", "envelope.open.badge.clock", .orange)
        case .ackSent:
            return ("Ack Sent", "checkmark.message", .orange)
        case .ackReceived:
            return ("Ack Received", "checkmark.message.fill", .orange)
        case .commitSent:
            return ("Sharing Keys", "paperplane.fill", .orange) // Changed text/icon
        case .commitReceivedWaitingForKeys:
            return ("Receiving Keys", "envelope.open.badge.clock", .orange) // New state display
        case .completed:
            return ("Keys Exchanged", "checkmark.shield.fill", .green)
        case let .failed(reason):
            // Keep reason short for UI
            let shortReason = reason.prefix(30) + (reason.count > 30 ? "..." : "")
            // Provide a more user-friendly default if reason is empty
            let displayText = reason.isEmpty ? "Failed" : "Failed: \(shortReason)"
            return (displayText, "exclamationmark.triangle.fill", .red)
        }
    }
}

// MARK: - Corner Radius Helper

// Helper for applying corner radius to specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
