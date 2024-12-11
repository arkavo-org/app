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
            TikTokFeedView()
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

struct ProfileView: View {
    @State private var selectedTab: ProfileTab = .posts
    @State private var user = DIDUser(
        id: "1",
        handle: "user.bsky.social",
        displayName: "Username",
        avatarURL: "",
        isVerified: false,
        did: "did:plc:example123",
        description: "A decentralized social network user",
        followers: 123,
        following: 456,
        postsCount: 789,
        serviceEndpoint: "https://bsky.social"
    )

    enum ProfileTab {
        case posts, replies, media, likes
    }

    var body: some View {
        NavigationStack {
            List {
                // Profile Header Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            AsyncImage(url: URL(string: user.avatarURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 60))
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                HStack {
                                    Text(user.displayName)
                                        .font(.headline)
                                    if user.isVerified {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                Text("@\(user.handle)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(user.did)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let description = user.description {
                            Text(description)
                                .font(.subheadline)
                        }

                        HStack(spacing: 24) {
                            VStack {
                                Text("\(user.following)")
                                    .font(.headline)
                                Text("Following")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack {
                                Text("\(user.followers)")
                                    .font(.headline)
                                Text("Followers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack {
                                Text("\(user.postsCount)")
                                    .font(.headline)
                                Text("Posts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }

                // Settings Section
                Section("Settings") {
                    NavigationLink {
                        // Edit Profile View
                        Text("Edit Profile")
                    } label: {
                        Label("Edit Profile", systemImage: "pencil")
                    }

                    NavigationLink {
                        // Notifications View
                        Text("Notifications")
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }

                    NavigationLink {
                        // Privacy View
                        Text("Privacy")
                    } label: {
                        Label("Privacy", systemImage: "lock")
                    }

                    NavigationLink {
                        // Help View
                        Text("Help")
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }

                // DID Information Section
                Section("Decentralized Identity") {
                    VStack(alignment: .leading) {
                        Text("Service Endpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(user.serviceEndpoint)
                            .font(.callout)
                    }

                    VStack(alignment: .leading) {
                        Text("DID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(user.did)
                            .font(.callout)
                    }
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
