import OpenTDFKit
import SwiftData
import SwiftUI

struct ArkavoView: View {
    @Environment(\.locale) var locale
    @State var service: ArkavoService
    @State private var persistenceController: PersistenceController?
    @State private var streamMapView: StreamMapView?
    @State private var showingProfileDetails = false
    @State private var isFileDialogPresented = false
    @State private var selectedView: SelectedView = .streamMap
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        @StateObject private var videoStreamViewModel = VideoStreamViewModel()
    #endif
    @Query private var accounts: [Account]

    init(service: ArkavoService) {
        self.service = service
    }

    enum SelectedView {
        case streamMap
        case streamList
        case video
        case protector
    }

    var body: some View {
        ZStack {
            ZStack {
                switch selectedView {
                case .streamMap:
                    StreamMapView()
                        .sheet(isPresented: $showingProfileDetails) {
                            if let account = accounts.first, let profile = account.profile {
                                AccountProfileDetailedView(viewModel: AccountProfileViewModel(profile: profile, activityService: ActivityServiceModel()))
                            }
                        }
                case .video:
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                        VideoStreamView(viewModel: videoStreamViewModel)
                    #endif
                case .streamList:
                    if let streamService = service.streamService {
                        StreamView(service: streamService)
                    } else {
                        Text("Thought service is unavailable")
                    }
                case .protector:
                    ProtectorView(service: service)
                }
                menuView()
            }
            .ignoresSafeArea(edges: .all)
        }
        .onAppear(perform: initialSetup)
        #if os(macOS)
            .fileImporter(
                isPresented: $isFileDialogPresented,
                allowedContentTypes: [.text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first {
                        do {
                            let contentString = try String(contentsOf: url, encoding: .utf8)
                            processContent(contentString)
                        } catch {
                            print("Error reading file: \(error.localizedDescription)")
                        }
                    }
                case let .failure(error):
                    print("Error selecting file: \(error.localizedDescription)")
                }
            }
        #endif
    }

    private func menuView() -> some View {
        VStack {
            GeometryReader { geometry in
                HStack {
                    Spacer()
                        .frame(width: geometry.size.width * 0.8)
                    Menu {
                        Section("Content Protection") {
                            #if os(macOS)
                                Button("Process File...") {
                                    isFileDialogPresented = true
                                }
                                Button("Process") {
                                    Task {
                                        let contentString = """
                                        How BERT Works

                                        Transformer Encoder
                                        BERT is built upon the Transformer architecture, specifically utilizing the encoder part of the Transformer. The encoder comprises multiple layers of self-attention and feed-forward neural networks, allowing BERT to process input data in parallel and capture complex dependencies.

                                        Bidirectional Processing
                                        Traditional language models read text sequentially, either left-to-right or right-to-left. BERT, however, processes text in both directions simultaneously. This bidirectional approach enables BERT to grasp the full context of a word based on all surrounding words, leading to more accurate and nuanced language understanding.

                                        Self-Attention Mechanism
                                        Self-attention allows BERT to weigh the importance of different words in a sentence when encoding a particular word. For example, in the sentence "The bank can guarantee your savings," self-attention helps BERT determine whether "bank" refers to a financial institution or the side of a river based on context.
                                        """
                                        // On macOS: Generate signature
                                        let preprocessor = try ContentPreprocessor()
                                        let signature = try preprocessor.generateSignature(for: contentString)
                                        // For batch processing
//                                    let signatures = try preprocessor.batchProcessRedditPosts(redditPosts)
//                                    // On iOS
//                                    let matcher = ContentMatcher()
//                                    let matches = matcher.findMatches(signature: signature, against: candidateSignatures)
                                        // Save/transmit signature (example using JSON)
                                        let encoder = JSONEncoder()
                                        let signatureData = try encoder.encode(signature)
                                        print("signatureData: \(signatureData.base64EncodedString())")
                                        let compressed = try signature.compressed()
                                        print("compressed: \(compressed)")
                                        let decompressed = try ContentSignature.decompress(compressed)
                                        print("decompressed: \(decompressed)")
                                        // transmit signatureData to iOS devices
                                    }
                                }
                            #endif
                            Button("Scan") {
                                selectedView = .protector
                            }
                        }
                        Section("Stream") {
                            Button("Map") {
                                selectedView = .streamMap
                            }
                            Button("Streams") {
                                selectedView = .streamList
                            }
                            #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                                Button("Video") {
                                    selectedView = .video
                                }
                            #endif
                        }
                        Section("Account") {
                            if let account = accounts.first {
                                if let profile = account.profile {
                                    Button("Profile: \(profile.name)") {
                                        showingProfileDetails = true
                                    }
                                }
                                if let authenticationToken = account.authenticationToken {
                                    if let profile = account.profile {
                                        // TODO: check if session token, then change to logout
                                        Button("Sign In") {
                                            Task {
                                                await service.authenticationManager.signIn(accountName: profile.name, authenticationToken: authenticationToken)
                                            }
                                        }
                                    }
                                } else {
                                    if let profile = account.profile {
                                        Button("Sign Up") {
                                            service.authenticationManager.signUp(accountName: profile.name)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .padding(.top, 40)
                    }
                    .menuStyle(DefaultMenuStyle())
                    .padding(.top, 40)
                    Spacer()
                    Spacer()
                }
            }
        }
    }

    private func initialSetup() {
        persistenceController = PersistenceController.shared
        service.setupCallbacks()
        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
            service.videoStreamViewModel = videoStreamViewModel
        #endif

        // TODO: replace with session token
        if let account = accounts.first, let profile = account.profile {
            let token = service.authenticationManager.createJWT(account: account, publicID: profile.publicID.base58EncodedString)
            if let token {
                service.setupWebSocketManager(token: token)
            } else {
                print("createJWT token nil")
            }
        } else {
            print("No profile no webSocket no token")
        }
    }

    #if os(macOS)
        private func processContent(_ contentString: String) {
            Task {
                do {
                    let preprocessor = try ContentPreprocessor()
                    let signature = try preprocessor.generateSignature(for: contentString)

                    let encoder = JSONEncoder()
                    let signatureData = try encoder.encode(signature)
                    print("signatureData: \(signatureData.base64EncodedString())")

                    let compressed = try signature.compressed()
                    print("compressed: \(compressed)")

                    let decompressed = try ContentSignature.decompress(compressed)
                    print("decompressed: \(decompressed)")
                } catch {
                    print("Error processing content: \(error.localizedDescription)")
                }
            }
        }
    #endif
}
