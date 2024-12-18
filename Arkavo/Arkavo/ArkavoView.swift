import OpenTDFKit
import SwiftData
import SwiftUI

struct ArkavoView: View {
    @Environment(\.locale) var locale
    @State var service: ArkavoService
    @State private var persistenceController: PersistenceController?
    @State private var streamMapView: StreamMapView?
    @State private var showingProfileDetails = false
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        @StateObject private var videoStreamViewModel = VideoStreamViewModel()
    #endif
    @State private var selectedView: SelectedView = .streamMap
    @Query private var accounts: [Account]
    @State private var isFileDialogPresented = false
    @State private var errorMessage: String?
    @State private var showingError = false

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
                    if let service = service.protectorService {
                        ProtectorView(service: service)
                    }
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
                            errorMessage = "Unable to read file: \(error.localizedDescription)"
                            showingError = true
                        }
                    }
                case let .failure(error):
                    errorMessage = "Failed to select file: \(error.localizedDescription)"
                    showingError = true
                }
            }
            .alert("Error", isPresented: $showingError, presenting: errorMessage) { _ in
                Button("OK") {
                    showingError = false
                    errorMessage = nil
                }
            } message: { errorMessage in
                Text(errorMessage)
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

    #if os(macOS)
        private func processContent(_ contentString: String) {
            Task {
                do {
                    let preprocessor = try ContentPreprocessor()
                    let signature = try preprocessor.generateSignature(for: contentString)
                    if let account = accounts.first, let profile = account.profile {
                        try await service.protectorService?.sendContentSignatureEvent(signature, creatorPublicID: profile.publicID)
                    }
                } catch {
                    errorMessage = "Error processing content: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    #endif

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
}
