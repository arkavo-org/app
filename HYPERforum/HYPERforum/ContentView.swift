import ArkavoAgent
import ArkavoSocial
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAuthSheet = false

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainForumView()
            } else {
                WelcomeView(showingAuthSheet: $showingAuthSheet)
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Binding var showingAuthSheet: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // Cyberpunk gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Logo and title
                VStack(spacing: 20) {
                    Text("ΞΞ")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.4, blue: 0.0), // Arkavo Orange
                                    Color(red: 1.0, green: 0.6, blue: 0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.0).opacity(0.5), radius: 20)

                    Text("HYPΞRforum")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Cyber-Renaissance Communication")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 5)
                }

                Spacer()

                // Features
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Group Discussions",
                        description: "Real-time threaded conversations"
                    )

                    FeatureRow(
                        icon: "brain.head.profile",
                        title: "AI Council",
                        description: "Personal AI agents augment your discourse"
                    )

                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "End-to-End Encrypted",
                        description: "OpenTDF secured messages"
                    )

                    FeatureRow(
                        icon: "person.badge.key.fill",
                        title: "Passkey Authentication",
                        description: "Secure, passwordless sign-in"
                    )
                }
                .padding(.horizontal, 40)

                Spacer()

                // Sign in button
                Button(action: {
                    showingAuthSheet = true
                }) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign In with Passkey")
                            .font(.headline)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.4, blue: 0.0),
                                Color(red: 1.0, green: 0.5, blue: 0.1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .sheet(isPresented: $showingAuthSheet) {
                    AuthenticationView()
                }
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Main Forum View

struct MainForumView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var webAuthnManager: WebAuthnManager
    @State private var selectedSidebar: SidebarItem = .groups
    @State private var groups: [ForumGroup] = ForumGroup.sampleGroups

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedSidebar) {
                Section("HΞR") {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                }

                Section("My Groups") {
                    ForEach(groups) { group in
                        HStack {
                            Circle()
                                .fill(group.color)
                                .frame(width: 8, height: 8)
                            Text(group.name)
                        }
                    }
                }
            }
            .navigationTitle("HYPΞRforum")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Settings") {}
                        Button("Sign Out") {
                            Task {
                                await webAuthnManager.signOut()
                                appState.signOut()
                            }
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
        } detail: {
            // Main content
            switch selectedSidebar {
            case .groups:
                GroupsView(groups: groups)
            case .discussions:
                DiscussionsView()
            case .council:
                CouncilView()
            case .settings:
                SettingsView()
            }
        }
    }
}

// MARK: - Supporting Types

enum SidebarItem: String, CaseIterable, Identifiable {
    case groups
    case discussions
    case council
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groups: return "Groups"
        case .discussions: return "Discussions"
        case .council: return "AI Council"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .groups: return "person.3.fill"
        case .discussions: return "bubble.left.and.bubble.right.fill"
        case .council: return "brain.head.profile"
        case .settings: return "gearshape.fill"
        }
    }
}

// ForumGroup model moved to Models.swift

// MARK: - Placeholder Views

struct GroupsView: View {
    let groups: [ForumGroup]
    @State private var selectedGroup: ForumGroup?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(groups) { group in
                    GroupCard(group: group)
                        .onTapGesture {
                            selectedGroup = group
                        }
                }
            }
            .padding()
        }
        .navigationTitle("Groups")
        .navigationDestination(item: $selectedGroup) { group in
            ChatView(group: group)
        }
    }
}

struct GroupCard: View {
    let group: ForumGroup
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(group.color)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                    Text("\(group.memberCount) members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 1 : 0.5)
            }

            Text(group.description.isEmpty ? "Active discussion forum for \(group.name.lowercased()) topics with AI-augmented insights." : group.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if let lastMessage = group.lastMessage {
                HStack {
                    Text("Last: ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    + Text(lastMessage.content)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? group.color.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
    }
}

struct DiscussionsView: View {
    var body: some View {
        VStack {
            Text("Discussions")
                .font(.largeTitle)
            Text("Your recent and active discussions will appear here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CouncilView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))

            Text("AI Council")
                .font(.largeTitle)

            Text("Your personal AI agents are ready to assist")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Activate Council") {
                // Activate council
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark Mode", isOn: .constant(true))
                ColorPicker("Accent Color", selection: .constant(Color(red: 1.0, green: 0.4, blue: 0.0)))
            }

            Section("Privacy") {
                Toggle("Enable Encryption", isOn: .constant(true))
                Toggle("Show Online Status", isOn: .constant(false))
            }

            Section("Notifications") {
                Toggle("Group Messages", isOn: .constant(true))
                Toggle("Council Insights", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

struct AuthenticationView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var webAuthnManager: WebAuthnManager
    @Environment(\.dismiss) var dismiss

    @State private var accountName = ""
    @State private var isRegistering = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))

            Text(isRegistering ? "Register with Passkey" : "Authenticate with Passkey")
                .font(.title2)

            Text(isRegistering ? "Create a new account with your passkey" : "Use your device's secure authentication to sign in")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Account name input
            TextField("Account name (e.g., username)", text: $accountName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            if webAuthnManager.isAuthenticating {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(isRegistering ? "Creating account..." : "Authenticating...")
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 15) {
                    Button(isRegistering ? "Register" : "Sign In") {
                        Task {
                            await performAuthentication()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(accountName.isEmpty)

                    Button(isRegistering ? "Already have an account? Sign in" : "Need an account? Register") {
                        isRegistering.toggle()
                        showError = false
                    }
                    .foregroundColor(.secondary)
                }
            }

            Button("Cancel") {
                dismiss()
            }
            .padding(.bottom)
        }
        .frame(width: 450, height: 550)
        .padding()
    }

    func performAuthentication() async {
        showError = false
        errorMessage = ""

        do {
            if isRegistering {
                // Register new user
                try await webAuthnManager.register(handle: accountName)
                // After registration, automatically sign in
                try await webAuthnManager.authenticate(accountName: accountName)
            } else {
                // Authenticate existing user
                try await webAuthnManager.authenticate(accountName: accountName)
            }

            // Success! Update app state
            appState.signIn(user: accountName)
            dismiss()
        } catch {
            // Show error to user
            showError = true
            errorMessage = webAuthnManager.authError ?? error.localizedDescription
            print("Authentication error: \(error)")
        }
    }
}

// MARK: - View Model

@MainActor
class ForumViewModel: ObservableObject {
    @Published var messages: [String] = []
    private let client: ArkavoClient

    init(client: ArkavoClient) {
        self.client = client
    }

    func sendMessage(_ message: String) {
        messages.append(message)
    }
}
