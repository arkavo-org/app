import AuthenticationServices
import Combine
import CryptoKit
import LocalAuthentication
import MapKit
import OpenTDFKit
import SwiftData
import SwiftUI

struct ArkavoView: View {
    private let nanoTDFManager = NanoTDFManager()
    private let authenticationManager = AuthenticationManager()
    @Environment(\.locale) var locale
    // OpenTDFKit
    @StateObject private var webSocketManager = WebSocketManager()
    @State private var inProcessCount = 0
    @State private var kasPublicKey: P256.KeyAgreement.PublicKey?
    // data
    @State private var persistenceController: PersistenceController?
    // map
    @State private var streamMapView: StreamMapView?
    // connection
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isReconnecting = false
    @State private var hasInitialConnection = false
    // account
    @State private var showingProfileCreation = false
    @State private var showingProfileDetails = false
    // thought
    @StateObject private var thoughtStreamViewModel = ThoughtStreamViewModel()
    // video
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        @StateObject private var videoStreamViewModel = VideoStreamViewModel()
    #endif
    // view control
    @State private var selectedView: SelectedView = .streamMap
    @State private var tokenCheckTimer: Timer?
    @Query private var accounts: [Account]
    @Query private var profiles: [Profile]

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
                    StreamMapView(webSocketManager: webSocketManager,
                                  nanoTDFManager: nanoTDFManager,
                                  kasPublicKey: $kasPublicKey)
                        .onAppear {
                            // Store reference to StreamMapView when it appears
                            streamMapView = StreamMapView(webSocketManager: webSocketManager,
                                                          nanoTDFManager: nanoTDFManager,
                                                          kasPublicKey: $kasPublicKey)
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
                            thoughtStreamViewModel: thoughtStreamViewModel,
                            words: words,
                            animationType: .explosion
                        )
                    )
                case .video:
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                        VideoStreamView(viewModel: videoStreamViewModel)
                    #endif
                case .streamList:
                    StreamView()
                }
                if selectedView != .welcome {
                    VStack {
                        GeometryReader { geometry in
                            HStack {
                                Spacer()
                                    .frame(width: geometry.size.width * 0.8)
                                Menu {
                                    Section("Navigation") {
                                        Button("Map") {
                                            selectedView = .streamMap
                                        }
                                        Button("My Streams") {
                                            selectedView = .streamList
                                        }
                                        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                                            Button("Video") {
                                                selectedView = .video
                                            }
                                        #endif
                                        Button("Engage!") {
                                            selectedView = .streamWordCloud
                                        }
                                    }
                                    Section("Account") {
                                        if let account = accounts.first {
                                            if let profile = account.profile {
                                                VStack(alignment: .leading) {
                                                    Text("Profile: \(profile.name)")
                                                }
                                            } else {
                                                Button("Create Profile") {
                                                    showingProfileCreation = true
                                                }
                                            }
                                            if let authenticationToken = account.authenticationToken {
                                                if let profile = account.profile {
                                                    Button("Sign In") {
                                                        Task {
                                                            await authenticationManager.signIn(accountName: profile.name, authenticationToken: authenticationToken)
                                                        }
                                                    }
                                                }
                                            } else {
                                                if let profile = account.profile {
                                                    Button("Sign Up") {
                                                        authenticationManager.signUp(accountName: profile.name)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Section("Demo") {
                                        Button("Cities") {
                                            streamMapView?.loadGeoJSON()
                                        }
                                        Button("Clusters") {
                                            streamMapView?.loadRandomCities()
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

    private var initialWelcomeView: some View {
        VStack(spacing: 20) {
            Text("Welcome to Arkavo!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Your content is always under your control - everywhere")
                .multilineTextAlignment(.center)
                .padding()
            Text("Your privacy is our priority. Create your profile using just your name and Apple Passkey — no passwords, no hassle.")
                .multilineTextAlignment(.center)
                .padding()
            VStack(alignment: .leading, spacing: 10) {
                Text("What makes us different?")
                    .font(.headline)
                BulletPoint(text: "Leader in Privacy")
                BulletPoint(text: "Leader in Content Security")
                BulletPoint(text: "Military-grade data security powered by OpenTDF.")
                BulletPoint(text: "Start group chats now, with more exciting features coming soon!")
            }
            .padding()
            Text("Ready to join?")
                .font(.headline)
            Button(action: {
                showingProfileCreation = true
            }) {
                Text("Create Profile")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(minWidth: 200)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
    }

    private func initialSetup() {
        setupCallbacks()
        setupWebSocketManager()
        persistenceController = PersistenceController.shared
        // Initialize ThoughtStreamViewModel
        thoughtStreamViewModel.initialize(
            webSocketManager: webSocketManager,
            nanoTDFManager: nanoTDFManager,
            kasPublicKey: $kasPublicKey
        )
        // Initialize VideoSteamViewModel
        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
            videoStreamViewModel.initialize(
                webSocketManager: webSocketManager,
                nanoTDFManager: nanoTDFManager,
                kasPublicKey: $kasPublicKey
            )
        #endif
        if let account = accounts.first {
            if account.profile == nil {
                selectedView = .welcome
            } else {
                selectedView = .streamMap
                thoughtStreamViewModel.profile = account.profile
            }
        } else {
            selectedView = .welcome
            // TODO: check if account needs to be created in edge case when deleted app and reinstalled
        }
    }

    private func setupCallbacks() {
        webSocketManager.setKASPublicKeyCallback { publicKey in
            if kasPublicKey != nil {
                // FIXME: remove when streams are broadcast
                streamMapView?.loadGeoJSON()
                return
            }
            DispatchQueue.main.async {
                print("Received KAS Public Key")
                kasPublicKey = publicKey
            }
        }

        webSocketManager.setRewrapCallback { id, symmetricKey in
            handleRewrapCallback(id: id, symmetricKey: symmetricKey)
        }
    }

    private func setupWebSocketManager() {
        // Subscribe to connection state changes
        webSocketManager.$connectionState
            .sink { state in
                if state == .connected, !hasInitialConnection {
                    DispatchQueue.main.async {
                        print("Initial connection established. Sending public key and KAS key message.")
                        hasInitialConnection = webSocketManager.sendPublicKey() && webSocketManager.sendKASKeyMessage()
                    }
                } else if state == .disconnected {
                    hasInitialConnection = false
                }
            }
            .store(in: &cancellables)
        if let account = accounts.first, let profile = account.profile {
            let token = authenticationManager.createJWT(profileName: profile.name)
            if let token {
                webSocketManager.setupWebSocket(token: token)
                webSocketManager.connect()
            } else {
                print("createJWT token nil")
            }
        } else {
            print("No profile no webSocket no token")
        }
    }

    private func resetWebSocketManager() {
        isReconnecting = true
        hasInitialConnection = false
        webSocketManager.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Increased delay to 1 second
            setupWebSocketManager()
            isReconnecting = false
        }
    }

    private func handleRewrapCallback(id: Data?, symmetricKey: SymmetricKey?) {
        guard let id, let symmetricKey else {
            print("DENY")
            return
        }

        guard let nanoTDF = nanoTDFManager.getNanoTDF(withIdentifier: id) else { return }
        nanoTDFManager.removeNanoTDF(withIdentifier: id)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let payload = try nanoTDF.getPayloadPlaintext(symmetricKey: symmetricKey)

                // Try to deserialize as a Thought first
                if let thought = try? Thought.deserialize(from: payload) {
                    DispatchQueue.main.async {
                        // Update the ThoughtStreamView
                        thoughtStreamViewModel.receiveThought(thought)
                    }
                } else if let city = try? City.deserialize(from: payload) {
                    // If it's not a Thought, try to deserialize as a City
                    DispatchQueue.main.async {
                        streamMapView?.addCityToCluster(city)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            streamMapView?.removeCityFromCluster(city)
                        }
                    }
                } else {
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                        // If it's neither a Thought nor a City, assume it's a video frame
                        DispatchQueue.main.async {
                            videoStreamViewModel.receiveVideoFrame(payload)
                        }
                    #endif
                }
            } catch {
                print("Unexpected error during nanoTDF decryption: \(error)")
            }
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
            thoughtStreamViewModel.profile = profile
            try persistenceController.saveChanges()

            authenticationManager.signUp(accountName: profile.name)
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
                    setupWebSocketManager()
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
