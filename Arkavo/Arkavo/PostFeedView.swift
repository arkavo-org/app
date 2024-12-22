import ArkavoSocial
import CryptoKit
import Foundation
import SwiftUI

// MARK: - View Models

@MainActor
class PostFeedViewModel: ObservableObject {
    private let client: ArkavoClient
    private let account: Account
    private let profile: Profile

    @Published var thoughts: [Thought] = []
    @Published var currentThoughtIndex = 0
    @Published var isLoading = false
    @Published var error: Error?

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile

        // Load initial thoughts
        Task {
            await loadThoughts()
        }
    }

    private func loadThoughts() async {
        isLoading = true
        // TODO: Load thoughts from backend
        // For now using sample data
        thoughts = SampleData.recentThoughts
        isLoading = false
    }

    func getCurrentCreator() -> Creator {
        // Determine tier based on identity assurance level and encryption
        let tier = if account.identityAssuranceLevel == .ial1 || profile.hasHighIdentityAssurance {
            "Verified"
        } else if profile.hasHighEncryption {
            "Premium"
        } else {
            "Basic"
        }

        // Combine profile information for the bio
        let bio = [
            profile.blurb,
            !profile.interests.isEmpty ? "Interests: \(profile.interests)" : nil,
            !profile.location.isEmpty ? "📍 \(profile.location)" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: "\n")

        return Creator(
            id: profile.publicID.base58EncodedString,
            name: profile.name,
            imageURL: "", // Profile doesn't have an avatar URL
            latestUpdate: profile.blurb ?? "",
            tier: tier,
            socialLinks: [], // Profile doesn't have social links yet
            notificationCount: 0,
            bio: bio
        )
    }
}

// MARK: - PostFeedView

struct PostFeedView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel = ViewModelFactory.shared.makePostFeedViewModel()
    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            if sharedState.showCreateView {
                PostCreateView(viewModel: viewModel)
                    .transition(.move(edge: .bottom))
            } else {
                mainFeedView
            }
        }
        .animation(.spring(), value: sharedState.showCreateView)
    }

    private var mainFeedView: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.thoughts) { thought in
                                ImmersiveThoughtCard(
                                    thought: thought,
                                    size: geometry.size
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .onChange(of: viewModel.currentThoughtIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(viewModel.thoughts[newIndex].id, anchor: .center)
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onEnded { gesture in
                                let verticalMovement = gesture.translation.height
                                let swipeThreshold: CGFloat = 50

                                if abs(verticalMovement) > swipeThreshold {
                                    withAnimation {
                                        if verticalMovement > 0, viewModel.currentThoughtIndex > 0 {
                                            viewModel.currentThoughtIndex -= 1
                                        } else if verticalMovement < 0, viewModel.currentThoughtIndex < viewModel.thoughts.count - 1 {
                                            viewModel.currentThoughtIndex += 1
                                        }
                                    }
                                }
                            }
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - ImmersiveThoughtCard

struct ImmersiveThoughtCard: View {
    let thought: Thought
    let size: CGSize
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Background
                Color.black
                    .frame(width: size.width, height: size.height)

                // Content overlay
                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        Text(thought.metadata.summary)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .padding(systemMargin * 2)
                    Spacer()

                    // Right side - Action buttons
                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) {
                        Spacer()
                    }
                }

                // Contributors section
                VStack {
                    Spacer()
                    HStack {
                        ContributorsView(contributors: thought.metadata.contributors)
                            .padding(.horizontal, systemMargin)
                            .padding(.bottom, systemMargin * 8)
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - PostCreateView

struct PostCreateView: View {
    @EnvironmentObject var sharedState: SharedState
    @ObservedObject var viewModel: PostFeedViewModel
    @State private var thoughtText = ""
    @State private var selectedImages: [UIImage] = []
    private let systemMargin: CGFloat = 16

    // Function to detect mentions in text
    private func detectMentions(_ text: String) -> [(String, Range<String.Index>)] {
        var mentions: [(String, Range<String.Index>)] = []
        let pattern = "@[\\w\\.]+"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let range = Range(match.range, in: text) else { return }
            mentions.append((String(text[range]), range))
        }

        return mentions
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                // Content overlay with TextEditor
                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        if thoughtText.isEmpty {
                            Text("Share your thought...")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        TextEditor(text: $thoughtText)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .onChange(of: thoughtText) { _, newValue in
                                let _ = detectMentions(newValue)
                            }
                    }
                    .padding(systemMargin * 2)

                    Spacer()

                    // Right side - Action buttons
                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) {
                        Button("Cancel") {
                            sharedState.showCreateView = false
                        }
                        .foregroundColor(.white)
                        .padding()

                        Spacer()

                        // Media upload button
                        Button(action: {
                            // Add image selection logic
                        }) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        .padding()

                        // Post button
                        Button {
                            Task {
                                await createThought()
                                sharedState.showCreateView = false
                            }
                        } label: {
                            Text("Post")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(thoughtText.isEmpty ? Color.gray : Color.blue)
                                .cornerRadius(20)
                        }
                        .disabled(thoughtText.isEmpty)
                        .padding()
                    }
                    .padding(.trailing, systemMargin)
                }

                // Selected images preview
                if !selectedImages.isEmpty {
                    VStack {
                        Spacer()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(selectedImages, id: \.self) { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding()
                        }
                        .background(Color.black.opacity(0.5))
                    }
                }
            }
        }
    }

    func createThought() async {
        do {
            // Create a new Thought with the current text
            let thought = Thought(id: UUID(), nano: Data())
            thought.metadata = ThoughtMetadata(
                creator: UUID(),
                mediaType: .text,
                createdAt: Date(),
                summary: thoughtText,
                contributors: [
                    Contributor(
                        id: "current_user_id",
                        creator: viewModel.getCurrentCreator(),
                        role: "Author"
                    ),
                ]
            )

            // Add the thought to the feed
            await MainActor.run {
                viewModel.thoughts.insert(thought, at: 0)
            }

            // Save the thought
            try await PersistenceController.shared.saveChanges()
        } catch {
            print("Error creating thought: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sample Data

enum SampleData {
    static let creator = Creator(
        id: "1",
        name: "Alice Johnson 🌟",
        imageURL: "https://images.unsplash.com/photo-1494790108377-be9c29b29330",
        latestUpdate: "Product Designer @Mozilla | Web3 & decentralization enthusiast 🔮",
        tier: "Premium",
        socialLinks: [],
        notificationCount: 0,
        bio: "Product Designer @Mozilla | Web3 & decentralization enthusiast 🔮 | Building the future of social media | she/her | bay area 🌉"
    )

    static let recentThoughts: [Thought] = {
        let thought1 = Thought(id: UUID(), nano: Data())
        thought1.metadata = ThoughtMetadata(
            creator: UUID(),
            mediaType: .text,
            createdAt: Date().addingTimeInterval(-3600),
            summary: "Just finished a deep dive into ActivityPub and AT Protocol integration. The future of social media is decentralized! 🚀",
            contributors: [Contributor(id: "1", creator: creator, role: "Author")]
        )

        let thought2 = Thought(id: UUID(), nano: Data())
        thought2.metadata = ThoughtMetadata(
            creator: UUID(),
            mediaType: .text,
            createdAt: Date().addingTimeInterval(-7200),
            summary: "Speaking at @DecentralizedWeb Summit next month about design patterns in federated social networks. Who else is going to be there?",
            contributors: [Contributor(id: "1", creator: creator, role: "Author")]
        )

        return [thought1, thought2]
    }()
}
