import ArkavoKit
import SwiftUI
import UserNotifications

enum Tab {
    case home
    case chats
    case memberships
    case social
    case profile

    var title: String {
        switch self {
        case .home: "Home"
        case .chats: "Chats"
        case .memberships: "Memberships"
        case .social: "Social"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "play.circle.fill"
        case .chats: "bubble.left.and.bubble.right.fill"
        case .memberships: "heart.fill"
        case .social: "network"
        case .profile: "person.circle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var sharedState: SharedState
    @EnvironmentObject var agentService: AgentService
    @StateObject private var membershipStore = PatreonMembershipStore()
    @State private var isCollapsed = false
    @State private var showMenuButton = true
//    @StateObject private var protectorService = ProtectorService()
    @State private var showTooltip = false
    @State private var timeOnScreen: TimeInterval = 0
    let tooltipTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let collapseTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    
    private var isPatreonLinked: Bool {
        KeychainManager.isPatreonAccountLinked()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                // Main Content
                switch sharedState.selectedTab {
                case .home:
                    if sharedState.isOfflineMode && !sharedState.showCreateView {
                        // Show network connection prompt when offline
                        NetworkConnectionPrompt(
                            onConnect: { domain in
                                sharedState.selectedNetworkDomain = domain
                                sharedState.shouldShowRegistration = true
                            },
                            onSkip: {
                                sharedState.selectedTab = .chats
                            }
                        )
                    } else {
                        VideoContentView()
                    }
                case .chats:
                    // All conversations: 1:1, groups, and agents
                    ChatsView()
                        .onDisappear {
                            sharedState.selectedStreamPublicID = nil
                        }
                case .memberships:
                    PatreonMembershipsView()
                case .social:
                    if sharedState.isOfflineMode {
                        // Show network connection prompt when offline
                        NetworkConnectionPrompt(
                            onConnect: { domain in
                                sharedState.selectedNetworkDomain = domain
                                sharedState.shouldShowRegistration = true
                            },
                            onSkip: {
                                sharedState.selectedTab = .chats
                            }
                        )
                    } else {
                        PostFeedView()
                    }
                case .profile:
                    // Set selected creator to self when showing profile
                    CreatorView()
                        .onAppear {
                            if let profile = ViewModelFactory.shared.getCurrentProfile() {
                                sharedState.selectedCreatorPublicID = profile.publicID
                            }
                        }
                }

                // Create Button with Tooltip
                if !(sharedState.showCreateView || sharedState.showChatOverlay) {
                    HStack(alignment: .top, spacing: 8) {
                        // Create Button
                        Button {
                            sharedState.showCreateView = true
                            showTooltip = false
                            timeOnScreen = 0
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Create")
                        .padding(.top, 0)
                        .padding(.leading, 8)
                        .modifier(BounceAnimationModifier(isAwaiting: sharedState.isAwaiting || showTooltip))

                        // Tooltip
                        if showTooltip {
                            Text(sharedState.getTooltipText())
                                .font(.callout)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.black.opacity(0.8)),
                                )
                                .transition(.opacity.combined(with: .slide))
                        }
                    }
                }
            }

            // Navigation Container
            ZStack {
                if !isCollapsed {
                    // Expanded TabView
                    HStack(spacing: isPatreonLinked ? 16 : 20) {
                        let tabs: [Tab] = isPatreonLinked 
                            ? [.home, .chats, .memberships, .social, .profile]
                            : [.home, .chats, .social, .profile]
                        
                        ForEach(tabs, id: \.self) { tab in
                            Button {
                                handleTabSelection(tab)
                            } label: {
                                ZStack {
                                    Image(systemName: tab.icon)
                                        .font(.title3)
                                        .foregroundColor(sharedState.selectedTab == tab ? .primary : .secondary)
                                    
                                    // Badge for memberships tab
                                    if tab == .memberships && membershipStore.hasUnreadContent {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 10, y: -8)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, isPatreonLinked ? 16 : 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .transition(AnyTransition.asymmetric(
                        insertion: .scale(scale: 0.1, anchor: .center)
                            .combined(with: .opacity),
                        removal: .scale(scale: 0.1, anchor: .center)
                            .combined(with: .opacity),
                    ))
                }

                // Menu button (centered)
                if showMenuButton, isCollapsed {
                    Button {
                        expandMenu()
                    } label: {
                        ZStack {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                            
                            // Badge on menu button when memberships have unread content
                            if isPatreonLinked && membershipStore.hasUnreadContent {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 12, y: -12)
                            }
                        }
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
        .onReceive(tooltipTimer) { _ in
            if !sharedState.showCreateView, !sharedState.showChatOverlay {
                timeOnScreen += 1

                // Show tooltip after 3 seconds if content is awaiting
                if timeOnScreen >= 3, timeOnScreen < 9, sharedState.isAwaiting, !showTooltip {
                    withAnimation(.easeInOut) {
                        showTooltip = true
                    }
                }

                // Hide tooltip after being shown for 6 seconds
                if timeOnScreen >= 9, showTooltip {
                    withAnimation(.easeInOut) {
                        showTooltip = false
                    }
                }
            }
        }
        .onChange(of: sharedState.selectedTab) { _, newTab in
            // Reset timer when tab changes
            timeOnScreen = 0
            showTooltip = false
            
            // When memberships tab is selected, refresh data
            if newTab == .memberships {
                Task {
                    await membershipStore.loadMembershipsWithUnread()
                }
            }
        }
        .task {
            // Request notification permission on first launch
            UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { granted, _ in
                print("[ContentView] Notification permission: \(granted)")
            }
            
            // Initial load of membership data if Patreon is linked
            if isPatreonLinked {
                await membershipStore.loadMembershipsWithUnread()
            }
        }
        // Also respond to isAwaiting changes
        .onChange(of: sharedState.isAwaiting) { _, isNowAwaiting in
            // If content is now awaiting and we've been on screen for 3+ seconds, show tooltip
            if isNowAwaiting, timeOnScreen >= 3, timeOnScreen < 9, !showTooltip {
                withAnimation(.easeInOut) {
                    showTooltip = true
                }
            }
            // If content is no longer awaiting, hide tooltip
            else if !isNowAwaiting, showTooltip {
                withAnimation(.easeInOut) {
                    showTooltip = false
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
        sharedState.selectedTab = tab
        sharedState.showCreateView = false
        withAnimation(.spring()) {
            isCollapsed = false
        }
    }
}

struct BounceAnimationModifier: ViewModifier {
    let isAwaiting: Bool
    @State private var bounceOffset: CGFloat = 0
    @State private var scaleEffect: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .offset(y: bounceOffset)
            .scaleEffect(scaleEffect)
            .onChange(of: isAwaiting) { _, isNowLoading in
                if isNowLoading {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
            .onAppear {
                if isAwaiting {
                    startAnimation()
                }
            }
    }

    private func startAnimation() {
        withAnimation(
            .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true),
        ) {
            bounceOffset = -10 // More pronounced bounce
        }
        withAnimation(
            .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
        ) {
            scaleEffect = 1.2 // Slight scaling for emphasis
        }
    }

    private func stopAnimation() {
        withAnimation(.easeOut) {
            bounceOffset = 0
            scaleEffect = 1.0
        }
    }
}

struct EmptyStateView: View {
    let tab: Tab

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(getEmptyStateMessage())
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }

    private func getEmptyStateMessage() -> String {
        switch tab {
        case .chats:
            "No conversations yet. Tap '+' to start a new chat or create a group."
        case .home:
            "Share your first video! Tap '+' to get started."
        case .memberships:
            "Support creators on Patreon to see their exclusive content here."
        case .social:
            "Start the conversation! Tap '+' to create your first post."
        case .profile:
            "Tell others about yourself by tapping '+' to update your bio."
        }
    }
}
