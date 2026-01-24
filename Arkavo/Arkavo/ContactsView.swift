import SwiftData
import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var sharedState: SharedState
    @EnvironmentObject var agentService: AgentService
    @StateObject private var contactService = UnifiedContactService()
    @State private var searchText = ""
    @State private var selectedContact: Profile?
    @State private var contactToDelete: Profile?
    @State private var showDeleteConfirmation = false
    @State private var showFilterMenu = false
    @State private var showSearchBar = false

    var filteredContacts: [Profile] {
        contactService.filteredContacts(searchText: searchText)
    }

    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header area - search toggle and filter button (space for + button on left)
                if !contactService.isLoading && !contactService.allContacts.isEmpty {
                    HStack(spacing: 12) {
                        Spacer()

                        // Search toggle button
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showSearchBar.toggle()
                                if !showSearchBar {
                                    searchText = ""
                                }
                            }
                        } label: {
                            Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(showSearchBar ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        // Filter button
                        FilterButton(
                            currentFilter: $contactService.currentFilter,
                            isExpanded: $showFilterMenu
                        )
                    }
                    .padding(.leading, 60) // Space for + button
                    .padding(.trailing, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }

                // Contact list
                if contactService.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if filteredContacts.isEmpty && searchText.isEmpty {
                    WaveEmptyStateView()
                } else if filteredContacts.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)

                        Text("No results")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Search bar - shown when toggled
                            if showSearchBar {
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)

                                    TextField("Search", text: $searchText)
                                        .font(.body)

                                    if !searchText.isEmpty {
                                        Button {
                                            withAnimation { searchText = "" }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.subheadline)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Contact cards
                            ForEach(filteredContacts) { contact in
                                ContactCard(contact: contact, agentService: agentService) {
                                    selectedContact = contact
                                }
                                .contextMenu {
                                    if contact.contactTypeEnum != .deviceAgent {
                                        Button(role: .destructive) {
                                            contactToDelete = contact
                                            showDeleteConfirmation = true
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }
                    .refreshable {
                        await contactService.loadContacts()
                    }
                }
            }
        }
        .sheet(isPresented: $sharedState.showCreateView) {
            ContactsCreateView()
        }
        .sheet(item: $selectedContact) { contact in
            UnifiedContactDetailView(contact: contact, agentService: agentService) { profileToDelete in
                contactToDelete = profileToDelete
                showDeleteConfirmation = true
            }
        }
        .alert("Remove Contact?", isPresented: $showDeleteConfirmation, presenting: contactToDelete) { contact in
            Button("Cancel", role: .cancel) {
                contactToDelete = nil
            }
            Button("Remove", role: .destructive) {
                Task {
                    await deleteContact(contact)
                }
            }
        } message: { contact in
            Text("You can add \(contact.name) again later.")
        }
        .task {
            contactService.configure(agentService: agentService)
        }
    }

    private func deleteContact(_ contact: Profile) async {
        do {
            try await contactService.deleteContact(contact)
            contactToDelete = nil
        } catch {
            print("Failed to delete contact: \(error)")
        }
    }
}

// MARK: - Filter Button (Liquid Glass)

struct FilterButton: View {
    @Binding var currentFilter: ContactFilter
    @Binding var isExpanded: Bool

    var body: some View {
        Menu {
            ForEach(ContactFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        currentFilter = filter
                    }
                } label: {
                    HStack {
                        Text(filter.rawValue)
                        if currentFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.subheadline)
                if currentFilter != .all {
                    Text(currentFilter.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(currentFilter == .all ? .secondary : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(currentFilter == .all ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Contact Card

struct ContactCard: View {
    let contact: Profile
    let agentService: AgentService
    let onTap: () -> Void

    private var isOnline: Bool {
        if contact.isAgent {
            return agentService.isConnected(to: contact.agentID ?? "")
        }
        return contact.keyStorePublic != nil
    }

    private var accentColor: Color {
        contact.isAgent ? .teal : .blue
    }

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.2), accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    if contact.isAgent {
                        Image(systemName: contact.contactTypeEnum == .deviceAgent ? "iphone" : "globe")
                            .font(.title3)
                            .foregroundStyle(accentColor)
                    } else {
                        Text(contact.name.prefix(1).uppercased())
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(accentColor)
                    }

                    // Online indicator
                    Circle()
                        .fill(isOnline ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                        .offset(x: 18, y: 18)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let purpose = contact.agentPurpose, contact.isAgent {
                        Text(purpose)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let handle = contact.handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.quaternary)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(ContactCardButtonStyle())
        .accessibilityIdentifier("contact-\(contact.id)")
    }
}

// MARK: - Button Style

struct ContactCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ContactsView()
        .environmentObject(SharedState())
        .environmentObject(AgentService())
}
