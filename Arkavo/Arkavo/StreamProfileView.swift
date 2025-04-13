import MultipeerConnectivity // Needed for MCPeerID
import SwiftData
import SwiftUI

// Define custom notification names (ensure this is defined elsewhere or here if not)
extension Notification.Name {
    static let peerTrustRevoked = Notification.Name("peerTrustRevokedNotification")
}

class StreamViewModel: ObservableObject {
    @Published var stream: Stream?

    init(stream: Stream) {
        self.stream = stream
    }

    // Function to refresh the stream data if needed, e.g., after background updates
    @MainActor
    func refreshStreamData(context: ModelContext) {
        guard let currentStreamID = stream?.id else { return }
        // Re-fetch the stream from the context to ensure it's up-to-date
        // Fallback to NSPredicate
        let descriptor = FetchDescriptor<Stream>(predicate: #Predicate { stream in
            stream.id == currentStreamID
        })
        if let updatedStream = try? context.fetch(descriptor).first {
            stream = updatedStream
            print("StreamViewModel: Refreshed stream data for \(updatedStream.profile.name)")
        }
    }
}

struct CompactStreamProfileView: View {
    @StateObject var viewModel: StreamViewModel

    var body: some View {
        HStack {
            Text(viewModel.stream!.profile.name)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct DetailedStreamProfileView: View {
    @StateObject var viewModel: StreamViewModel
    @EnvironmentObject var peerDiscoveryManager: PeerDiscoveryManager // Inject PeerDiscoveryManager
    @Environment(\.modelContext) private var modelContext // Access model context
    @State private var isShareSheetPresented: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingRevokeConfirmation = false
    // Change state variable to hold Profile instead of MCPeerID
    @State private var profileToRevoke: Profile?
    @State private var revocationError: String?
    @State private var showingRevocationError = false
    @State private var revocationSuccessMessage: String?
    @State private var showingRevocationSuccess = false

    // Helper to check if a profile ID corresponds to a connected peer
    private func isConnected(profileID: Data) -> Bool {
        let profileIDString = profileID.base58EncodedString
        // Check if any connected peer's mapped profile ID matches
        return peerDiscoveryManager.peerIDToProfileIDMap.values.contains(profileIDString)
    }

    // Helper to get the MCPeerID for a connected profile ID, if available
    private func getConnectedPeerID(for profileID: Data) -> MCPeerID? {
        let profileIDString = profileID.base58EncodedString
        // Find the MCPeerID key in the map whose value matches the profileIDString
        return peerDiscoveryManager.peerIDToProfileIDMap.first { $0.value == profileIDString }?.key
    }

    // Sorted inner circle profiles for display
    // This computed property will re-evaluate when viewModel.stream changes
    private var sortedInnerCircleProfiles: [Profile] {
        viewModel.stream?.innerCircleProfiles.sorted { $0.name < $1.name } ?? []
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Use the sortedInnerCircleProfiles computed property here
                // It depends on viewModel.stream, so changes should trigger UI updates
                if let stream = viewModel.stream {
                    Form {
                        Section(header: Text("Profile")) {
                            Text("\(stream.profile.name)")
                            if let blurb = stream.profile.blurb, !blurb.isEmpty {
                                Text("\(blurb)")
                            }
                        }
                        Section(header: Text("Policies")) {
                            Text("Admission: \(stream.policiesSafe.admission.rawValue)")
                            Text("Interaction: \(stream.policiesSafe.interaction.rawValue)")
                            Text("Age Policy: \(stream.policiesSafe.age.rawValue)")
                        }
                        Section(header: Text("Public ID")) {
                            Text(stream.publicID.base58EncodedString)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        // Section for Inner Circle Members (Connected and Disconnected)
                        if stream.isInnerCircleStream {
                            Section(header: Text("Inner Circle Members (\(sortedInnerCircleProfiles.count))")) {
                                if sortedInnerCircleProfiles.isEmpty {
                                    Text("No members added to the Inner Circle yet.")
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(sortedInnerCircleProfiles, id: \.id) { profile in
                                        HStack {
                                            // Display profile name
                                            Text(profile.name)
                                            // Indicate connection status
                                            if isConnected(profileID: profile.publicID) {
                                                Text("(Connected)")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            } else {
                                                Text("(Offline)")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                            // Revoke Trust Button (associated with Profile)
                                            Button("Revoke Trust", role: .destructive) {
                                                profileToRevoke = profile // Set the profile to revoke
                                                showingRevokeConfirmation = true
                                            }
                                            .buttonStyle(.borderless)
                                            .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Placeholder or loading view if stream is nil
                    Text("Loading stream details...")
                    ProgressView()
                }
            }
            .navigationTitle("Stream Details") // Changed title for clarity
            #if !os(macOS)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "x.circle")
                        }
                    }
                    // Keep Invite button logic
                    if viewModel.stream?.policiesSafe.admission != .closed {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                isShareSheetPresented = true
                            }) {
                                HStack {
                                    Text("Invite Friends")
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
                .sheet(isPresented: $isShareSheetPresented) {
                    // Ensure stream is not nil before creating URL
                    if let stream = viewModel.stream {
                        ShareSheet(activityItems: [URL(string: "https://app.arkavo.com/stream/\(stream.publicID.base58EncodedString)")!],
                                   isPresented: $isShareSheetPresented)
                    }
                }
            #endif
                // Confirmation Alert for Revoking Trust (using Profile)
                .alert("Revoke Trust?", isPresented: $showingRevokeConfirmation, presenting: profileToRevoke) { profile in
                    Button("Cancel", role: .cancel) {
                        profileToRevoke = nil
                    }
                    Button("Revoke", role: .destructive) {
                        Task {
                            // Pass the Profile object from the alert context
                            await revokeTrust(forProfile: profile)
                        }
                        profileToRevoke = nil // Clear after initiating task
                    }
                } message: { profile in
                    // Updated message
                    Text("Revoking trust for \"\(profile.name)\" will remove their keys from your device and prevent future secure communication in this circle until trust is re-established. If they are currently connected, they will be disconnected. Are you sure?")
                }
                // Alert for showing revocation errors
                .alert("Error Revoking Trust", isPresented: $showingRevocationError, presenting: revocationError) { _ in
                    Button("OK") { revocationError = nil }
                } message: { errorMsg in
                    Text("Failed to revoke trust: \(errorMsg)")
                }
                // Alert for showing revocation success
                .alert("Trust Revoked", isPresented: $showingRevocationSuccess, presenting: revocationSuccessMessage) { _ in
                    Button("OK") { revocationSuccessMessage = nil }
                } message: { message in
                    Text(message) // Display the success message
                }
                // Refresh stream data when the view appears to ensure it's current
                .onAppear {
                    viewModel.refreshStreamData(context: modelContext)
                }
        }
    }

    // Updated function to handle trust revocation for a Profile
    @MainActor
    private func revokeTrust(forProfile profileToRevoke: Profile) async {
        guard let streamID = viewModel.stream?.id else {
            print("❌ RevokeTrust Error: Stream ID is missing from the view model.")
            revocationError = "Internal error: Stream information missing."
            showingRevocationError = true
            return
        }

        let profileIDData = profileToRevoke.publicID
        let profileIDString = profileIDData.base58EncodedString
        let profileName = profileToRevoke.name
        print("RevokeTrust: Starting process for profile: \(profileName) (\(profileIDString)) in stream ID: \(streamID)")
        revocationError = nil // Reset error
        revocationSuccessMessage = nil // Reset success message

        var wasConnected = false

        // 1. Check connection status and disconnect if necessary
        if let peerToDisconnect = await peerDiscoveryManager.findPeer(byProfileID: profileIDData) {
            print("RevokeTrust: Profile \(profileName) is currently connected as peer \(peerToDisconnect.displayName). Initiating disconnection.")
            wasConnected = true
            peerDiscoveryManager.disconnectPeer(peerToDisconnect)
            print("RevokeTrust: Disconnection initiated for \(peerToDisconnect.displayName).")
        } else {
            print("RevokeTrust: Profile \(profileName) is not currently connected. Skipping disconnection step.")
            wasConnected = false
        }

        do {
            // 2. Delete KeyStore data and Notify (using the original profile object passed in)
            try await deleteKeysAndNotify(profileIDData: profileIDData, profileIDString: profileIDString, profileName: profileName)

            // --- Modification Section ---
            // 3. Fetch the Stream from the context to ensure we modify the managed object
            print("RevokeTrust: Fetching stream \(streamID) from context for modification...")
            // Using SwiftData's typed predicate syntax
            let descriptor = FetchDescriptor<Stream>(predicate: #Predicate { stream in
                stream.id == streamID
            })
            guard let streamInContext = try modelContext.fetch(descriptor).first else {
                print("❌ RevokeTrust Error: Failed to fetch stream \(streamID) from context.")
                throw ArkavoError.streamError("Stream not found in context for update.")
            }
            print("RevokeTrust: Fetched stream '\(streamInContext.profile.name)' successfully.")

            // 4. Remove profile from the stream's innerCircleProfiles
            // Ensure the profile object to remove is also fetched or identifiable if needed,
            // but removing by ID should be sufficient if the `removeFromInnerCircle` uses ID.
            print("RevokeTrust: Attempting to remove profile \(profileName) (\(profileIDString)) from stream's Inner Circle list.")
            let initialCount = streamInContext.innerCircleProfiles.count
            streamInContext.removeFromInnerCircle(profileToRevoke) // Assumes uses ID check
            let finalCount = streamInContext.innerCircleProfiles.count
            print("RevokeTrust: Profile removal attempted. Initial count: \(initialCount), Final count: \(finalCount).")

            if initialCount == finalCount, initialCount > 0 {
                // Check if the profile was actually in the list before attempting removal
                if try await !(PersistenceController.shared.fetchStream(withID: streamID)?.innerCircleProfiles.contains(where: { $0.id == profileToRevoke.id }) ?? false) {
                    print("RevokeTrust: Profile \(profileName) was likely already removed or not present in the Inner Circle list.")
                } else {
                    print("⚠️ RevokeTrust Warning: Profile \(profileName) was not removed from innerCircleProfiles array. Check `removeFromInnerCircle` logic or profile ID matching.")
                    // Consider throwing an error here if removal is critical
                }
            } else {
                print("RevokeTrust: Profile \(profileName) removed from local stream object's innerCircleProfiles.")
            }

            // 5. Save the changes to the context
            if modelContext.hasChanges {
                print("RevokeTrust: Saving model context after modifying Inner Circle...")
                try modelContext.save()
                print("✅ RevokeTrust: Model context saved successfully.")
                // Explicitly tell the view model to update its stream state from the context
                // This ensures the @Published property change notification is sent
                viewModel.refreshStreamData(context: modelContext)

            } else {
                print("RevokeTrust: No changes detected in model context after profile removal attempt. Skipping save.")
            }
            // --- End Modification Section ---

            // 6. Set success message
            if wasConnected {
                revocationSuccessMessage = "Successfully disconnected and revoked trust for \"\(profileName)\". Their keys and membership have been removed."
            } else {
                revocationSuccessMessage = "Successfully revoked trust for \"\(profileName)\". Their keys and membership have been removed (they were not currently connected)."
            }
            showingRevocationSuccess = true
            print("✅ RevokeTrust: Process completed successfully for \(profileName).")

        } catch {
            // Error occurred during key deletion, notification, stream fetch, or save
            print("❌ RevokeTrust Error: Failed during revocation process for \(profileName): \(error)")
            revocationError = "Failed to complete trust revocation. \(error.localizedDescription)"
            showingRevocationError = true
            // Attempt to refresh the view model even on error to reflect any partial changes
            viewModel.refreshStreamData(context: modelContext)
        }
    }

    @MainActor
    private func deleteKeysAndNotify(profileIDData: Data, profileIDString: String, profileName: String) async throws {
        // Delete KeyStore data using PersistenceController
        print("RevokeTrust [deleteKeysAndNotify]: Fetching profile \(profileName) (\(profileIDString)) for key deletion...")
        // Fetch the profile again using the ID to ensure we have the instance from the context
        guard let profileToDeleteKeys = try await PersistenceController.shared.fetchProfile(withPublicID: profileIDData) else {
            print("⚠️ RevokeTrust [deleteKeysAndNotify]: Profile \(profileName) (\(profileIDString)) not found in persistence. Cannot delete keys, maybe already removed?")
            // If profile is gone, keys are implicitly gone. Treat as success for revocation.
            return
        }

        print("RevokeTrust [deleteKeysAndNotify]: Deleting KeyStore data for profile \(profileToDeleteKeys.name)...")
        try await PersistenceController.shared.deleteKeyStoreDataFor(profile: profileToDeleteKeys)
        print("✅ RevokeTrust [deleteKeysAndNotify]: Successfully deleted KeyStore data for \(profileToDeleteKeys.name).")

        // Post Notification
        NotificationCenter.default.post(
            name: .peerTrustRevoked,
            object: nil,
            userInfo: ["revokedProfileID": profileIDData] // Keep using profileIDData
        )
        print("✅ RevokeTrust [deleteKeysAndNotify]: Posted peerTrustRevoked notification for profile ID: \(profileIDString)")
    }
}

#if os(iOS) || os(visionOS)
    struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        @Binding var isPresented: Bool

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            return controller
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }

#elseif os(macOS)
    struct ShareSheet: View {
        let activityItems: [Any]
        @Binding var isPresented: Bool

        var body: some View {
            VStack {
                ForEach(activityItems.indices, id: \.self) { index in
                    let item = activityItems[index]
                    if let url = item as? URL {
                        ShareLink(item: url) {
                            Label("Share URL", systemImage: "link")
                        }
                    } else if let string = item as? String {
                        ShareLink(item: string) {
                            Label("Share Text", systemImage: "text.quote")
                        }
                    }
                }
                Button("Done") {
                    isPresented = false
                }
            }
            .padding()
        }
    }
#endif

struct CreateStreamProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateStreamViewModel()
    var onSave: (Profile, AdmissionPolicy, InteractionPolicy, AgePolicy) -> Void

    var body: some View {
        VStack {
            HStack {
                Text("Create Stream")
                    .font(.title)
                    .padding(.leading, 16)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .padding(.trailing, 16)
            }
            Form {
                Section {
                    Text("A stream lets you start conversations about any topic. You can choose who joins and interacts with your stream.")
                        .font(.footnote)
                }
                Section {
                    TextField("What We are Discussing", text: $viewModel.name)
                    if !viewModel.nameError.isEmpty {
                        Text(viewModel.nameError).foregroundColor(.red)
                    }
                    TextField("Topic of Interest", text: $viewModel.blurb)
                    if !viewModel.blurbError.isEmpty {
                        Text(viewModel.blurbError).foregroundColor(.red)
                    }
                }
                Section(header: Text("Policies")) {
                    Picker("Admission", selection: $viewModel.admissionPolicy) {
                        ForEach(AdmissionPolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    Picker("Interaction", selection: $viewModel.interactionPolicy) {
                        ForEach(InteractionPolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    Picker("Age", selection: $viewModel.agePolicy) {
                        ForEach(AgePolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                }
            }
            Button(action: {
                let profile = Profile(name: viewModel.name, blurb: viewModel.blurb)
                onSave(profile, viewModel.admissionPolicy, viewModel.interactionPolicy, viewModel.agePolicy)
                dismiss()
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isValid ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(!viewModel.isValid)
        }
        .onChange(of: viewModel.name) { _, _ in viewModel.validateName() } // Updated for iOS 17+
        .onChange(of: viewModel.blurb) { _, _ in viewModel.validateBlurb() } // Updated for iOS 17+
        .onAppear { // Validate on appear as well
            viewModel.validateName()
            viewModel.validateBlurb()
        }
    }
}

class CreateStreamViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var blurb: String = ""
    @Published var participantCount: Int = 2
    @Published var admissionPolicy: AdmissionPolicy = .open
    @Published var interactionPolicy: InteractionPolicy = .open
    @Published var agePolicy: AgePolicy = .onlyKids
    @Published var nameError: String = ""
    @Published var blurbError: String = ""
    @Published var isValid: Bool = false

    func validateName() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameError = "Name cannot be empty"
        } else if name.count > 50 {
            nameError = "Name must be 50 characters or less"
        } else {
            nameError = ""
        }
        updateValidity()
    }

    func validateBlurb() {
        if blurb.count > 200 {
            blurbError = "Blurb must be 200 characters or less"
        } else {
            blurbError = ""
        }
        updateValidity()
    }

    private func updateValidity() {
        isValid = nameError.isEmpty && blurbError.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func createStreamProfile() -> (Profile, Int, AdmissionPolicy, InteractionPolicy)? {
        if isValid {
            let profile = Profile(name: name, blurb: blurb.isEmpty ? nil : blurb)
            return (profile, participantCount, admissionPolicy, interactionPolicy)
        }
        return nil
    }
}
