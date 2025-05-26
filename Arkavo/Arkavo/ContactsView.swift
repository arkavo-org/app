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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Contact avatar
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Text(contact.name.prefix(1).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let handle = contact.handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Show connection status
                    HStack(spacing: 4) {
                        if contact.hasHighEncryption {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }

                        if contact.keyStorePublic != nil {
                            Text("Connected")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Text("Not connected")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Action indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
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
                    // Contact header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 100, height: 100)

                            Text(contact.name.prefix(1).uppercased())
                                .font(.system(size: 48))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }

                        Text(contact.name)
                            .font(.title)
                            .fontWeight(.bold)

                        if let handle = contact.handle {
                            Text("@\(handle)")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top)

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
                                // Navigate to chat
                                sharedState.selectedCreatorPublicID = contact.publicID
                                sharedState.showChatOverlay = true
                                dismiss()
                            } label: {
                                Label("Send Message", systemImage: "message.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        } else {
                            Button {
                                // Initiate P2P connection
                                // This would trigger the P2P discovery/connection flow
                            } label: {
                                Label("Connect", systemImage: "link")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
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
