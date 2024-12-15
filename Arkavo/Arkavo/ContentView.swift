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
        case .communities: "Community"
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
    @State private var isCollapsed = false
    @State private var showMenuButton = true
    @State private var showCreateView = false
    @StateObject private var feedViewModel = TikTokFeedViewModel()
    @StateObject private var groupViewModel = DiscordViewModel()

    let collapseTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                // Main Content
                switch selectedTab {
                case .home:
                    if showCreateView {
                        TikTokRecordingView { result in
                            if let uploadResult = result {
                                // FIXME:
                                print("FIXME - Upload Result \(uploadResult)")
//                                feedViewModel.addNewVideo(from: uploadResult, contributors: <#[Contributor]#>)
                            }
                            showCreateView = false
                        }
                    } else {
                        TikTokFeedView(viewModel: feedViewModel, showCreateView: $showCreateView)
                    }
                case .communities:
                    if showCreateView {
                        CreateServerView(viewModel: groupViewModel, showCreateView: $showCreateView)
                    } else {
                        DiscordView(viewModel: groupViewModel, showCreateView: $showCreateView)
                    }
                case .social:
                    BlueskyView(showCreateView: $showCreateView)
                case .creators:
                    PatreonView(showCreateView: $showCreateView)
                case .profile:
                    ProfileView(showCreateView: $showCreateView)
                }

                // Create Button
                if !showCreateView {
                    Button {
                        showCreateView = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.top, 0)
                    .padding(.leading, 8)
                }
            }

            // Navigation Container
            ZStack {
                if !isCollapsed {
                    // Expanded TabView
                    HStack(spacing: 30) {
                        ForEach([Tab.home, .communities, .social, .creators, .profile], id: \.self) { tab in
                            Button {
                                handleTabSelection(tab)
                            } label: {
                                Image(systemName: tab.icon)
                                    .font(.title3)
                                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .transition(AnyTransition.asymmetric(
                        insertion: .scale(scale: 0.1, anchor: .center)
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.1, anchor: .center)
                            .combined(with: .opacity)
                    ))
                }

                // Menu button (centered)
                if showMenuButton, isCollapsed {
                    Button {
                        expandMenu()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .transition(.opacity)
                }
            }
            .padding()
        }
        .onReceive(collapseTimer) { _ in
            if !isCollapsed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring()) {
                        isCollapsed = true
                        showMenuButton = true
                    }
                }
            }
        }
    }

    private func expandMenu() {
        withAnimation(.easeOut(duration: 0.1)) {
            showMenuButton = false
        }

        withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
            isCollapsed = false
        }
    }

    private func handleTabSelection(_ tab: Tab) {
        selectedTab = tab
        showCreateView = false
        withAnimation(.spring()) {
            isCollapsed = false
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
    @Binding var showCreateView: Bool

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
        }
        .sheet(isPresented: $showCreateView) {
            Text("Create Profile things")
        }
    }
}

// Preview
#Preview {
    ContentView()
}
