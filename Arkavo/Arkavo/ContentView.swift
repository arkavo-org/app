import SwiftUI

enum Tab {
    case home
    case communities
    case social
    case creators
    case profile

    var title: String {
        switch self {
        case .home: "Home"
        case .communities: "Communities"
        case .social: "Social"
        case .creators: "Creators"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "play.circle.fill"
        case .communities: "bubble.left.and.bubble.right.fill"
        case .social: "network"
        case .creators: "star.circle.fill"
        case .profile: "person.circle.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            TikTokView()
                .tabItem {
                    Label(Tab.home.title, systemImage: Tab.home.icon)
                }
                .tag(Tab.home)

            DiscordView()
                .tabItem {
                    Label(Tab.communities.title, systemImage: Tab.communities.icon)
                }
                .tag(Tab.communities)

            BlueskyView()
                .tabItem {
                    Label(Tab.social.title, systemImage: Tab.social.icon)
                }
                .tag(Tab.social)

            PatreonView()
                .tabItem {
                    Label(Tab.creators.title, systemImage: Tab.creators.icon)
                }
                .tag(Tab.creators)

            ProfileView()
                .tabItem {
                    Label(Tab.profile.title, systemImage: Tab.profile.icon)
                }
                .tag(Tab.profile)
        }
    }
}

// Placeholder Views
struct TikTokView: View {
    var body: some View {
        NavigationStack {
            Text("TikTok Clone View")
                .navigationTitle("For You")
        }
    }
}

struct BlueskyView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(1 ... 10, id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text("User \(index)")
                            .font(.headline)
                        Text("This is a sample post #\(index)")
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Timeline")
        }
    }
}

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                        VStack(alignment: .leading) {
                            Text("Username")
                                .font(.headline)
                            Text("@handle")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Settings") {
                    Label("Edit Profile", systemImage: "pencil")
                    Label("Notifications", systemImage: "bell")
                    Label("Privacy", systemImage: "lock")
                    Label("Help", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle("Profile")
        }
    }
}

// Preview
#Preview {
    ContentView()
}
