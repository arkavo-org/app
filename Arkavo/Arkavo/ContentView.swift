import ArkavoSocial
import SwiftUI

enum Tab {
    case home
    case communities
    case social
//    case creators
//    case protect
    case profile

    var title: String {
        switch self {
        case .home: "Home"
        case .communities: "Community"
        case .social: "Social"
//        case .creators: "Creators"
//        case .protect: "Protect"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "play.circle.fill"
        case .communities: "bubble.left.and.bubble.right.fill"
        case .social: "network"
//        case .creators: "star.circle.fill"
//        case .protect: "shield.checkerboard"
        case .profile: "person.circle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var isCollapsed = false
    @State private var showMenuButton = true
//    @StateObject private var protectorService = ProtectorService()

    let collapseTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                // Main Content
                switch sharedState.selectedTab {
                case .home:
                    VideoContentView()
                case .communities:
                    GroupView()
                        .onDisappear {
                            sharedState.selectedStreamPublicID = nil
                        }
                case .social:
                    PostFeedView()
//                case .creators:
//                    if sharedState.showCreateView, sharedState.selectedCreator != nil {
//                        if let creator = sharedState.selectedCreator {
//                            CreatorSupportView(creator: creator) {
//                                sharedState.showCreateView = false
//                                sharedState.selectedCreator = nil
//                            }
//                        }
//                    } else {
//                        CreatorView()
//                    }
//                case .protect:
//                    ProtectorView(service: protectorService)
                case .profile:
                    // Set selected creator to self when showing profile
                    CreatorView()
                        .onAppear {
                            if let profile = ViewModelFactory.shared.getCurrentProfile() {
                                sharedState.selectedCreatorPublicID = profile.publicID
                            }
                        }
                }

                // Create Button
                if !(sharedState.showCreateView || sharedState.showChatOverlay) {
                    Button {
                        sharedState.showCreateView = true
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
                    .modifier(BounceAnimationModifier(isAwaiting: sharedState.isAwaiting))
                }
            }

            // Navigation Container
            ZStack {
                if !isCollapsed {
                    // Expanded TabView
                    HStack(spacing: 30) {
                        ForEach([Tab.home, .communities, .social, .profile], id: \.self) { tab in
                            Button {
                                handleTabSelection(tab)
                            } label: {
                                Image(systemName: tab.icon)
                                    .font(.title3)
                                    .foregroundColor(sharedState.selectedTab == tab ? .primary : .secondary)
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
        sharedState.selectedTab = tab
        sharedState.showCreateView = false
        withAnimation(.spring()) {
            isCollapsed = false
        }
    }
}

struct WaveLoadingView: View {
    let message: String
    @State private var waveOffset = 0.0
    @State private var boatOffset = 0.0

    var body: some View {
        VStack(spacing: 40) {
            // Wave and logo container
            GeometryReader { _ in
                ZStack {
                    // Waves spanning full width
                    WaveShape(offset: waveOffset, waveHeight: 20)
                        .fill(Color(red: 0, green: 0.32, blue: 0.66))
                        .opacity(0.8)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity) // Full width

                    WaveShape(offset: waveOffset + 0.5, waveHeight: 15)
                        .fill(Color(red: 0, green: 0.32, blue: 0.66))
                        .opacity(0.4)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity) // Full width

                    // Animated Logo
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120) // Kept large size
                        .foregroundColor(.orange)
                        .offset(y: CGFloat(sin(boatOffset) * 10))
                        .rotationEffect(.degrees(sin(boatOffset) * 3))
                }
            }
            .frame(height: 200) // Fixed height container

            // Message with dots
            HStack(spacing: 4) {
                Text(message + " ...")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                waveOffset = -.pi * 2
            }
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                boatOffset = .pi * 2
            }
        }
    }
}

struct WaveShape: Shape {
    var offset: Double
    var waveHeight: Double

    var animatableData: Double {
        get { offset }
        set { offset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2

        // More points for smoother wave
        path.move(to: CGPoint(x: 0, y: midHeight))

        // Create smoother wave with more points
        for x in stride(from: 0, to: width, by: 1) {
            let relativeX = x / width
            let sine = sin(relativeX * .pi * 2 + offset)
            let y = midHeight + sine * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Ensure wave fills to bottom
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()

        return path
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
                .repeatForever(autoreverses: true)
        ) {
            bounceOffset = -10 // More pronounced bounce
        }
        withAnimation(
            .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
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
