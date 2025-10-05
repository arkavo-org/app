import SwiftData
import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var selectedContact: Profile?
    @State private var showContactActions = false
    @State private var contacts: [Profile] = []
    @State private var isLoading = true
    @State private var contactToDelete: Profile?
    @State private var showDeleteConfirmation = false

    var filteredContacts: [Profile] {
        if searchText.isEmpty {
            contacts
        } else {
            contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                    (contact.handle?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            if !isLoading && !contacts.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search contacts", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Contact list
            if isLoading {
                // Show loading state
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredContacts.isEmpty, searchText.isEmpty {
                // Show awaiting animation when no contacts at all
                WaveEmptyStateView()
            } else if filteredContacts.isEmpty {
                // Show search empty state when filtering
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("No contacts found")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Try a different search term")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredContacts) { contact in
                            ContactRow(contact: contact) {
                                selectedContact = contact
                                showContactActions = true
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    contactToDelete = contact
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            if contact.id != filteredContacts.last?.id {
                                Divider()
                                    .padding(.leading, 80)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            ContactsCreateView()
        }
        .sheet(isPresented: $sharedState.showCreateView) {
            ContactsCreateView()
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailView(contact: contact) { profileToDelete in
                contactToDelete = profileToDelete
                showDeleteConfirmation = true
            }
        }
        .alert("Delete Contact?", isPresented: $showDeleteConfirmation, presenting: contactToDelete) { contact in
            Button("Cancel", role: .cancel) {
                contactToDelete = nil
                showDeleteConfirmation = false
            }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteContact(contact)
                    showDeleteConfirmation = false
                }
            }
        } message: { contact in
            Text("Are you sure you want to delete \(contact.name)? You'll also be removed from any chats you only share with this person.")
        }
        .task {
            await loadContacts()
        }
        .refreshable {
            await loadContacts()
        }
    }

    private func loadContacts() async {
        isLoading = true
        do {
            let peerProfiles = try await PersistenceController.shared.fetchAllPeerProfiles()
            // Filter out "Me" and "InnerCircle" profiles
            await MainActor.run {
                contacts = peerProfiles.filter { profile in
                    profile.name != "Me" && profile.name != "InnerCircle"
                }
            }
        } catch {
            print("Failed to fetch contacts: \(error)")
            await MainActor.run {
                contacts = []
            }
        }
        isLoading = false
    }

    private func deleteContact(_ contact: Profile) async {
        do {
            // Delete the profile and its associated data
            try await PersistenceController.shared.deletePeerProfile(contact)

            // Reload contacts to refresh the UI
            await loadContacts()

            // Clear the reference
            contactToDelete = nil
        } catch {
            print("Failed to delete contact: \(error)")
        }
    }
}

struct ContactRow: View {
    let contact: Profile
    let onTap: () -> Void
    @State private var isPressed = false

    var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                // Contact avatar with gradient
                ZStack {
                    Circle()
                        .fill(avatarGradient.opacity(0.3))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(avatarGradient, lineWidth: 2)
                        )

                    Text(contact.name.prefix(1).uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(avatarGradient)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(contact.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let handle = contact.handle {
                        Text("@\(handle)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Show connection status with icons
                    HStack(spacing: 8) {
                        if contact.hasHighEncryption {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Secure")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }

                        if contact.keyStorePublic != nil {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Connected")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                Text("Not connected")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                Spacer()

                // Action indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(0.6)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityIdentifier("contact-\(contact.id)")
    }
}

struct ContactDetailView: View {
    let contact: Profile
    let onDelete: (Profile) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @State private var showDeleteButton = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Contact header with gradient
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ).opacity(0.3)
                                )
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.blue, Color.purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                )
                                .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)

                            Text(contact.name.prefix(1).uppercased())
                                .font(.system(size: 52))
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        VStack(spacing: 8) {
                            Text(contact.name)
                                .font(.title)
                                .fontWeight(.bold)

                            if let handle = contact.handle {
                                Text("@\(handle)")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 20)

                    // Connection status
                    VStack(alignment: .leading, spacing: 16) {
                        Label {
                            Text(contact.keyStorePublic != nil ? "Connected" : "Not Connected")
                                .foregroundColor(contact.keyStorePublic != nil ? .green : .orange)
                        } icon: {
                            Image(systemName: contact.keyStorePublic != nil ? "link.circle.fill" : "link.circle")
                                .foregroundColor(contact.keyStorePublic != nil ? .green : .orange)
                        }

                        if contact.hasHighEncryption {
                            Label {
                                Text("High Encryption")
                                    .foregroundColor(.green)
                            } icon: {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                            }
                        }

                        if contact.hasHighIdentityAssurance {
                            Label {
                                Text("Identity Verified")
                                    .foregroundColor(.green)
                            } icon: {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Actions
                    VStack(spacing: 12) {
                        if contact.keyStorePublic != nil {
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                // Navigate to chat
                                sharedState.selectedCreatorPublicID = contact.publicID
                                sharedState.showChatOverlay = true
                                dismiss()
                            } label: {
                                Label("Send Message", systemImage: "message.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                        } else {
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                // Initiate P2P connection
                                // This would trigger the P2P discovery/connection flow
                            } label: {
                                Label("Connect", systemImage: "link")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                        }

                        Button {
                            // Show more options
                        } label: {
                            Label("More Options", systemImage: "ellipsis.circle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    // Additional info
                    if let blurb = contact.blurb, !blurb.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)

                            Text(blurb)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Delete button in danger zone
                    Button {
                        showDeleteButton = true
                    } label: {
                        Label("Delete Contact", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
                .padding(.bottom)
            }
            .navigationTitle("Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Contact?", isPresented: $showDeleteButton) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    dismiss()
                    onDelete(contact)
                }
            } message: {
                Text("Are you sure you want to delete \(contact.name)? You'll also be removed from any chats you only share with this person.")
            }
        }
    }
}

#Preview {
    ContactsView()
        .environmentObject(SharedState())
}
