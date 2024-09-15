import AuthenticationServices
import Combine
import CryptoKit
import LocalAuthentication
import MapKit
import OpenTDFKit
import SwiftData
import SwiftUI

struct ArkavoView: View {
    var service = ArkavoService(WebSocketManager())
    @Environment(\.locale) var locale
    // data
    @State private var persistenceController: PersistenceController?
    // map
    @State private var streamMapView: StreamMapView?
    // account
    @State private var showingProfileCreation = false
    @State private var showingProfileDetails = false
    // video
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        @StateObject private var videoStreamViewModel = VideoStreamViewModel()
    #endif
    // view control
    @State private var selectedView: SelectedView = .streamList
    @State private var tokenCheckTimer: Timer?
    @Query private var accounts: [Account]

    init() {}

    enum SelectedView {
        case welcome
        case streamMap
        case streamWordCloud
        case streamList
        case video
    }

    var body: some View {
        ZStack {
            ZStack {
                switch selectedView {
                case .welcome:
                    WelcomeView(onCreateProfile: {
                        showingProfileCreation = true
                    })
                    .sheet(isPresented: $showingProfileCreation) {
                        AccountProfileCreateView(
                            onSave: { profile in
                                Task {
                                    await saveProfile(profile: profile)
                                }
                            },
                            selectedView: $selectedView
                        )
                    }
                case .streamMap:
                    StreamMapView(webSocketManager: service.webSocketManager,
                                  nanoTDFManager: service.nanoTDFManager,
                                  kasPublicKey: ArkavoService.kasPublicKey)
                        .onAppear {
                            // Store reference to StreamMapView when it appears
                            streamMapView = StreamMapView(webSocketManager: service.webSocketManager,
                                                          nanoTDFManager: service.nanoTDFManager,
                                                          kasPublicKey: ArkavoService.kasPublicKey)
                        }
                        .sheet(isPresented: $showingProfileDetails) {
                            if let account = accounts.first, let profile = account.profile {
                                AccountProfileDetailedView(viewModel: AccountProfileViewModel(profile: profile))
                            }
                        }
                case .streamWordCloud:
                    let words: [(String, CGFloat)] = [
                        ("Feedback", 60), ("Technology", 50), ("Fitness", 45), ("Activism", 55),
                        ("Sports", 40), ("Career", 35), ("Education", 30), ("Beauty", 25),
                        ("Fashion", 20), ("Gaming", 15), ("Entertainment", 30), ("Climate Change", 25),
                    ]
                    StreamCloudView(
                        viewModel: WordCloudViewModel(
                            words: words,
                            animationType: .explosion
                        )
                    )
                case .video:
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                        VideoStreamView(viewModel: videoStreamViewModel)
                    #endif
                case .streamList:
                    let thoughtStreamViewModel = ThoughtStreamViewModel(service: service.thoughtService)
                    StreamView(viewModel: StreamViewModel(thoughtStreamViewModel: thoughtStreamViewModel))
                }
                if selectedView != .welcome {
                    VStack {
                        GeometryReader { geometry in
                            HStack {
                                Spacer()
                                    .frame(width: geometry.size.width * 0.8)
                                Menu {
                                    Section("Stream") {
                                        Button("Map") {
                                            selectedView = .streamMap
                                        }
                                        Button("My") {
                                            selectedView = .streamList
                                        }
                                        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                                            Button("Video") {
                                                selectedView = .video
                                            }
                                        #endif
                                        Button("Engage") {
                                            selectedView = .streamWordCloud
                                        }
                                    }
                                    Section("Account") {
                                        if let account = accounts.first {
                                            if let profile = account.profile {
                                                Button("Profile: \(profile.name)") {
                                                    showingProfileDetails = true
                                                }
                                            } else {
                                                Button("Create Profile") {
                                                    showingProfileCreation = true
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
                                    Image(systemName: "gear")
                                        .padding()
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .menuStyle(DefaultMenuStyle())
                                .padding(.top, 40)
                                Spacer()
                                Spacer()
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .all)
        }
        .onAppear(perform: initialSetup)
    }

    private func initialSetup() {
        service.setupCallbacks()
        persistenceController = PersistenceController.shared
        if let account = accounts.first, let profile = account.profile {
            let token = service.authenticationManager.createJWT(profileName: profile.name)
            if let token {
                service.setupWebSocketManager(token: token)
            } else {
                print("createJWT token nil")
            }
        } else {
            print("No profile no webSocket no token")
        }
        // Initialize VideoSteamViewModel
        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
            videoStreamViewModel.initialize(
                webSocketManager: service.webSocketManager,
                nanoTDFManager: service.nanoTDFManager
            )
        #endif
        if let account = accounts.first {
            if account.profile == nil {
                selectedView = .welcome
            } else {
                selectedView = .streamMap
            }
        } else {
            selectedView = .welcome
            // TODO: check if account needs to be created in edge case when deleted app and reinstalled
        }
    }

    private func saveProfile(profile: Profile) async {
        guard let persistenceController else {
            print("PersistenceController not initialized")
            return
        }
        do {
            let account = try persistenceController.getOrCreateAccount()
            account.profile = profile
            try persistenceController.saveChanges()

            service.authenticationManager.signUp(accountName: profile.name)
            startTokenCheck()
            await MainActor.run {
                selectedView = .streamMap
            }
        } catch {
            print("Failed to save profile: \(error)")
        }
    }

    private func startTokenCheck() {
        tokenCheckTimer?.invalidate() // Invalidate any existing timer
        tokenCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            checkForAuthenticationToken()
        }
    }

    private func checkForAuthenticationToken() {
        Task {
            await MainActor.run {
                if let account = accounts.first, account.authenticationToken != nil {
                    tokenCheckTimer?.invalidate()
                    tokenCheckTimer = nil
                    service.setupWebSocketManager(token: account.authenticationToken!)
                }
            }
        }
    }
}

class NanoTDFManager: ObservableObject {
    private var nanoTDFs: [Data: NanoTDF] = [:]
    @Published private(set) var count: Int = 0
    @Published private(set) var inProcessCount: Int = 0
    @Published private(set) var processDuration: TimeInterval = 0

    private var processTimer: Timer?
    private var processStartTime: Date?

    func addNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) {
        nanoTDFs[identifier] = nanoTDF
        count += 1
        updateInProcessCount(inProcessCount + 1)
    }

    func getNanoTDF(withIdentifier identifier: Data) -> NanoTDF? {
        nanoTDFs[identifier]
    }

    func removeNanoTDF(withIdentifier identifier: Data) {
        guard identifier.count > 32 else {
            print("Identifier must be greater than 32 bytes long")
            return
        }
        if nanoTDFs.removeValue(forKey: identifier) != nil {
            count -= 1
            updateInProcessCount(inProcessCount - 1)
        }
    }

    private func updateInProcessCount(_ newCount: Int) {
        if newCount > 0, inProcessCount == 0 {
            startProcessTimer()
        } else if newCount == 0, inProcessCount > 0 {
            stopProcessTimer()
        }
        inProcessCount = newCount
    }

    private func startProcessTimer() {
        processStartTime = Date()
        processTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startTime = processStartTime else { return }
            print("processDuration \(Date().timeIntervalSince(startTime))")
        }
    }

    private func stopProcessTimer() {
//        print("stopProcessTimer")
        guard let startTime = processStartTime else { return }
        processDuration = Date().timeIntervalSince(startTime)
        print("processDuration \(processDuration)")
        processTimer?.invalidate()
        processTimer = nil
        processStartTime = nil
    }

    func isEmpty() -> Bool {
        nanoTDFs.isEmpty
    }
}
