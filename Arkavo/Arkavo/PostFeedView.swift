import ArkavoSocial
import CryptoKit
import FlatBuffers
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
        thoughts = SampleData.recentThoughts
        isLoading = false
    }

    func getCurrentCreator() -> Creator {
        let tier = if account.identityAssuranceLevel == .ial1 || profile.hasHighIdentityAssurance {
            "Verified"
        } else if profile.hasHighEncryption {
            "Premium"
        } else {
            "Basic"
        }

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
            imageURL: "",
            latestUpdate: profile.blurb ?? "",
            tier: tier,
            socialLinks: [],
            notificationCount: 0,
            bio: bio
        )
    }

    func createAndSendThought(content: String) async throws {
        // Create message data
        let messageData = content.data(using: .utf8) ?? Data()

        // Create thought service model
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: Data(), // No specific stream for feed posts
            mediaType: .text,
            content: messageData
        )

        // Create FlatBuffers policy
        var builder = FlatBufferBuilder()

        // Create format info
        let formatVersionString = builder.create(string: "1.0")
        let formatProfileString = builder.create(string: "standard")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
            &builder,
            type: .plain,
            versionOffset: formatVersionString,
            profileOffset: formatProfileString
        )

        // Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: .text,
            dataEncoding: .utf8,
            formatOffset: formatInfo
        )

        // Create rating
        let rating = Arkavo_Rating.createRating(
            &builder,
            violent: .mild,
            sexual: .mild,
            profane: .mild,
            substance: .none_,
            hate: .none_,
            harm: .none_,
            mature: .mild,
            bully: .none_
        )

        // Create purpose
        let purpose = Arkavo_Purpose.createPurpose(
            &builder,
            educational: 0.2,
            entertainment: 0.8,
            news: 0.0,
            promotional: 0.0,
            personal: 0.8,
            opinion: 0.2,
            transactional: 0.0,
            harmful: 0.0,
            confidence: 0.9
        )

        // Create ID and related vectors
        let idVector = builder.createVector(bytes: thoughtModel.publicID)
        let relatedVector = builder.createVector(bytes: Data())

        // Create topics vector
        let topics: [UInt32] = [1, 2, 3]
        let topicsVector = builder.createVector(topics)

        // Create metadata root
        let metadata = Arkavo_Metadata.createMetadata(
            &builder,
            created: Int64(Date().timeIntervalSince1970),
            idVectorOffset: idVector,
            relatedVectorOffset: relatedVector,
            ratingOffset: rating,
            purposeOffset: purpose,
            topicsVectorOffset: topicsVector,
            contentOffset: contentFormat
        )

        builder.finish(offset: metadata)

        // Verify FlatBuffer
        var buffer = builder.sizedBuffer
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)

        // Get policy data
        let policyData = Data(
            bytes: buffer.memory.advanced(by: buffer.reader),
            count: Int(buffer.size)
        )

        // Serialize payload
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData
        )

        let thought = Thought(
            id: UUID(),
            nano: nanoData
        )

        // Save thought
        _ = try PersistenceController.shared.saveThought(thought)
        try await PersistenceController.shared.saveChanges()

        // Update UI
        await MainActor.run {
            thoughts.insert(thought, at: 0)
        }
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
                Color.black
                    .frame(width: size.width, height: size.height)

                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        Text(thought.metadata.summary)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .padding(systemMargin * 2)
                    Spacer()
                }

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
    @State private var error: Error?
    @State private var showError = false
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

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
                    }
                    .padding(systemMargin * 2)

                    Spacer()

                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) {
                        Button("Cancel") {
                            sharedState.showCreateView = false
                        }
                        .foregroundColor(.white)
                        .padding()

                        Spacer()

                        Button(action: {
                            // Add image selection logic
                        }) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        .padding()

                        Button {
                            Task {
                                do {
                                    try await viewModel.createAndSendThought(content: thoughtText)
                                    sharedState.showCreateView = false
                                } catch {
                                    self.error = error
                                    showError = true
                                }
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
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "An unknown error occurred")
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
