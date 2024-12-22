import ArkavoSocial
import SwiftUI

// MARK: - Models

@MainActor
class DiscordViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var streams: [Stream] = []
    @Published var selectedStream: Stream?

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        Task {
            await loadStreams()
        }
    }

    private func loadStreams() async {
        streams = account.streams
    }

    func shareVideo(_ video: Video, to stream: Stream) async {
        print("Sharing video \(video.id) to stream \(stream.profile.name)")
//        do {
//            try await client.shareVideo(video, to: stream)
//        } catch {
//            print("Error sharing video: \(error)")
//        }
    }

    // Convert Stream to Server view model
    func serverFromStream(_ stream: Stream) -> Server {
        Server(
            id: stream.id.uuidString,
            name: stream.profile.name,
            imageURL: nil,
            icon: iconForStream(stream),
            unreadCount: stream.thoughts.count,
            hasNotification: !stream.thoughts.isEmpty,
            description: stream.profile.blurb ?? "No description available",
            policies: StreamPolicies(
                agePolicy: stream.agePolicy,
                admissionPolicy: stream.admissionPolicy,
                interactionPolicy: stream.interactionPolicy
            )
        )
    }

    private func iconForStream(_ stream: Stream) -> String {
        switch stream.agePolicy {
        case .onlyAdults: "person.fill"
        case .onlyKids: "figure.child"
        case .onlyTeens: "figure.wave"
        case .forAll: "person.3.fill"
        }
    }
}

struct StreamPolicies: Hashable, Equatable {
    let agePolicy: AgePolicy
    let admissionPolicy: AdmissionPolicy
    let interactionPolicy: InteractionPolicy

    func hash(into hasher: inout Hasher) {
        hasher.combine(agePolicy)
        hasher.combine(admissionPolicy)
        hasher.combine(interactionPolicy)
    }

    static func == (lhs: StreamPolicies, rhs: StreamPolicies) -> Bool {
        lhs.agePolicy == rhs.agePolicy &&
            lhs.admissionPolicy == rhs.admissionPolicy &&
            lhs.interactionPolicy == rhs.interactionPolicy
    }
}

struct Server: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let imageURL: String?
    let icon: String
    var unreadCount: Int
    var hasNotification: Bool
    let description: String
    let policies: StreamPolicies

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.imageURL == rhs.imageURL &&
            lhs.icon == rhs.icon &&
            lhs.unreadCount == rhs.unreadCount &&
            lhs.hasNotification == rhs.hasNotification &&
            lhs.description == rhs.description &&
            lhs.policies == rhs.policies
    }
}

// MARK: - Main View

struct GroupChatView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showCreateServer = false
    @State private var showMembersList = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // MARK: - Stream List

                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if viewModel.streams.isEmpty {
                                EmptyStateView()
                            } else {
                                ForEach(viewModel.streams) { stream in
                                    ServerCardView(
                                        server: viewModel.serverFromStream(stream),
                                        stream: stream,
                                        onSelect: {
                                            viewModel.selectedStream = stream
                                            navigationPath.append(stream)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                    }
                    .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width)
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())

                    // MARK: - Chat View (iPad/Mac)

                    if horizontalSizeClass == .regular,
                       let selectedStream = viewModel.selectedStream
                    {
                        ChatView(viewModel: ViewModelFactory.shared.makeChatViewModel(stream: selectedStream))
                    }
                }
            }
            .navigationDestination(for: Stream.self) { stream in
                if horizontalSizeClass == .compact {
                    ChatView(viewModel: ViewModelFactory.shared.makeChatViewModel(stream: stream))
                        .navigationTitle(stream.profile.name)
                }
            }
            .sheet(isPresented: $showCreateServer) {
                NavigationStack {
                    GroupCreateView()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Communities Yet")
                .font(.headline)
            Text("Create or join a community to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - Server Card

struct ServerCardView: View {
    let server: Server
    let stream: Stream
    let onSelect: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // Server Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)

                        Image(systemName: server.icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }

                    // Server Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(server.name)
                                .font(.headline)
                                .foregroundColor(.primary)

                            if server.hasNotification {
                                NotificationBadge(count: server.unreadCount)
                            }
                        }

                        Text(server.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    PolicyRow(icon: "person.3.fill",
                              title: "Age Policy",
                              value: server.policies.agePolicy.rawValue)
                    PolicyRow(icon: "door.left.hand.open",
                              title: "Admission",
                              value: server.policies.admissionPolicy.rawValue)
                    PolicyRow(icon: "bubble.left.and.bubble.right",
                              title: "Interaction",
                              value: server.policies.interactionPolicy.rawValue)

                    Divider()
                        .padding(.vertical, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}

struct PolicyRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .foregroundStyle(.primary)
        }
    }
}

struct ThoughtRow: View {
    let thought: Thought

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(thought.nano.hexEncodedString())
                    .font(.headline)
                Spacer()
                Text(thought.metadata.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(thought.metadata.createdAt.formatted())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
