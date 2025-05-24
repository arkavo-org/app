import SwiftUI
import SwiftData

struct ContactsView: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var selectedContact: Profile?
    @State private var showContactActions = false
    
    // Fetch all peer profiles from persistence
    @Query(
        filter: #Predicate<Profile> { profile in
            profile.name != "Me" && profile.name != "InnerCircle"
        },
        sort: \Profile.name
    ) private var contacts: [Profile]
    
    var filteredContacts: [Profile] {
        if searchText.isEmpty {
            return contacts
        } else {
            return contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                (contact.handle?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    HStack {
                        Text("Contacts")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button {
                            showAddContact = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .scaleEffect(contacts.isEmpty ? 1.2 : 1.0)
                                .animation(
                                    contacts.isEmpty ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                                    value: contacts.isEmpty
                                )
                        }
                        .overlay(
                            // Add a pulsing hint when no contacts
                            contacts.isEmpty ? 
                            Text("Add contacts")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .offset(y: 30)
                                .opacity(0.8)
                                .animation(
                                    Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                    value: contacts.isEmpty
                                )
                            : nil
                        )
                    }
                    .padding(.horizontal)
                    
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search contacts", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
                .padding(.bottom, 8)
                
                Divider()
                
                // Contact list
                if filteredContacts.isEmpty && searchText.isEmpty {
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
                AddContactView()
            }
            .sheet(item: $selectedContact) { contact in
                ContactDetailView(contact: contact)
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
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    
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
        }
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var showScanner = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Add New Contact")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                VStack(spacing: 16) {
                    // Scan QR code option
                    Button {
                        showScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                            
                            VStack(alignment: .leading) {
                                Text("Scan QR Code")
                                    .font(.headline)
                                Text("Scan a contact's QR code to connect")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Search nearby option
                    Button {
                        // Trigger P2P discovery
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.title2)
                            
                            VStack(alignment: .leading) {
                                Text("Search Nearby")
                                    .font(.headline)
                                Text("Find contacts using peer-to-peer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Manual entry option
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter Contact ID")
                            .font(.headline)
                        
                        HStack {
                            TextField("Contact ID or handle", text: $searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button("Add") {
                                // Handle manual addition
                            }
                            .disabled(searchText.isEmpty)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
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
    }
}

#Preview {
    ContactsView()
        .environmentObject(SharedState())
}
