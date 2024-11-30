import ArkavoSocial
import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedSection: NavigationSection = .dashboard
    @Environment(\.colorScheme) var colorScheme
    let patreonClient: PatreonClient

    var body: some View {
        NavigationSplitView {
            Sidebar(selectedSection: $selectedSection)
        } detail: {
            VStack(spacing: 0) {
                SectionContainer(
                    selectedSection: selectedSection,
                    patreonClient: patreonClient
                )
            }
            .navigationTitle(selectedSection.rawValue)
            .navigationSubtitle(selectedSection.subtitle)
            .toolbar {
                if patreonClient.isAuthenticated {
                    ToolbarItemGroup {
                        Button(action: {}) {
                            Image(systemName: "bell")
                        }
                        .help("Notifications")
                        Menu {
                            Button("Profile", action: {})
                            Button("Preferences...", action: {})
                            Divider()
                            Button("Sign Out", action: {
                                patreonClient.logout()
                            })
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Navigation Section Updates

enum NavigationSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case content = "Content Manager"
    case patrons = "Patron Management"
    case protection = "Content Protection"
    case social = "Social Distribution"
    case settings = "Settings"

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .content: "doc.badge.plus"
        case .patrons: "person.2.circle"
        case .protection: "lock.shield"
        case .social: "square.and.arrow.up.circle"
        case .settings: "gear"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Overview"
        case .content: "Manage Your Content"
        case .patrons: "Manage Your Community"
        case .protection: "Content Security"
        case .social: "Share Your Content"
        case .settings: "App Settings"
        }
    }
}

// MARK: - Section Container View

struct SectionContainer: View {
    let selectedSection: NavigationSection
    let patreonClient: PatreonClient
    @Namespace private var animation

    var body: some View {
        ZStack {
            switch selectedSection {
            case .dashboard:
                // Pass client and config to PatreonRootView
                PatreonRootView(patreonClient: patreonClient)
                    .transition(.moveAndFade())
                    .id("dashboard")
            case .patrons:
                PatronManagementView(patreonClient: patreonClient)
                    .transition(.moveAndFade())
                    .id("patrons")
            case .content:
                ContentManagerView()
                    .transition(.moveAndFade())
                    .id("content")
            default:
                DefaultSectionView(section: selectedSection)
                    .transition(.moveAndFade())
                    .id(selectedSection.rawValue)
            }
        }
        .animation(.smooth, value: selectedSection)
    }
}

// MARK: - Default Section View

struct DefaultSectionView: View {
    let section: NavigationSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(section.rawValue)
                    .font(.title)
                    .padding(.bottom)

                ContentCard()
            }
            .padding()
        }
    }
}

// MARK: - Custom Transitions

extension AnyTransition {
    static func moveAndFade() -> AnyTransition {
        AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }
}

// MARK: - Sidebar View

struct Sidebar: View {
    @Binding var selectedSection: NavigationSection

    var body: some View {
        List(selection: $selectedSection) {
            Section {
                ForEach(NavigationSection.allCases[0 ..< 5], id: \.self) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.systemImage)
                    }
                }
            }
            Section {
                NavigationLink(value: NavigationSection.settings) {
                    Label(NavigationSection.settings.rawValue,
                          systemImage: NavigationSection.settings.systemImage)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Sidebar Row View

struct SidebarRow: View {
    let section: NavigationSection

    var body: some View {
        Label(
            title: { Text(section.rawValue) },
            icon: { Image(systemName: section.systemImage) }
        )
    }
}

// MARK: - Top Bar View

struct TopBar: View {
    let title: String
    @State private var showNotifications = false
    @State private var showProfileMenu = false

    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            HStack(spacing: 16) {
                Button(action: { showNotifications.toggle() }) {
                    Image(systemName: "bell")
                        .symbolVariant(showNotifications ? .fill : .none)
                }
                .help("Notifications")

                Menu {
                    Button("Profile", action: {})
                    Button("Preferences", action: {})
                    Divider()
                    Button("Sign Out", action: {})
                } label: {
                    HStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }
}

// MARK: - Content Card View

struct ContentCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)

            ForEach(0 ..< 3) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.accentColor)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Content Title")
                            .font(.body)
                        Text("Updated 2 hours ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("View") {
                        // Action
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
