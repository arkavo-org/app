import AuthenticationServices
import Combine
import CryptoKit
import LocalAuthentication
import MapKit
import OpenTDFKit
import SwiftData
import SwiftUI

struct ArkavoView: View {
    @Environment(\.locale) var locale
    // service
    @State var service: ArkavoService
    // data
    @State private var persistenceController: PersistenceController?
    // map
    @State private var streamMapView: StreamMapView?
    // account
    @State private var showingProfileDetails = false
    // video
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        @StateObject private var videoStreamViewModel = VideoStreamViewModel()
    #endif
    // view control
    @State private var selectedView: SelectedView = .streamList
    @Query private var accounts: [Account]

    init(service: ArkavoService) {
        self.service = service
    }

    enum SelectedView {
        case streamMap
        case streamList
        case video
    }

    var body: some View {
        ZStack {
            ZStack {
                switch selectedView {
                case .streamMap:
                    StreamMapView(webSocketManager: service.webSocketManager,
                                  nanoTDFManager: service.nanoTDFManager)
                        .onAppear {
                            // Store reference to StreamMapView when it appears
                            streamMapView = StreamMapView(webSocketManager: service.webSocketManager,
                                                          nanoTDFManager: service.nanoTDFManager)
                        }
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
                }
                menuView()
            }
            .ignoresSafeArea(edges: .all)
        }
        .onAppear(perform: initialSetup)
    }

    private func menuView() -> some View {
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
                            Button("List") {
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

    private func initialSetup() {
        persistenceController = PersistenceController.shared
        service.setupCallbacks()
        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
            service.videoStreamViewModel = videoStreamViewModel
        #endif

        // TODO: replace with session token
        if let account = accounts.first, let profile = account.profile {
            let token = service.authenticationManager.createJWT(publicID: profile.publicID.base58EncodedString)
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

class NanoTDFManager: ObservableObject {
    private var nanoTDFs: [Data: NanoTDF] = [:]
    @Published private(set) var count: Int = 0
    @Published private(set) var inProcessCount: Int = 0
    @Published private(set) var processDuration: TimeInterval = 0

    private var processTimer: Timer?
    private var processStartTime: Date?

    func addNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) {
        DispatchQueue.main.async {
            self.nanoTDFs[identifier] = nanoTDF
            self.count += 1
            self.updateInProcessCount(self.inProcessCount + 1)
        }
    }

    func getNanoTDF(withIdentifier identifier: Data) -> NanoTDF? {
        nanoTDFs[identifier]
    }

    func removeNanoTDF(withIdentifier identifier: Data) {
        guard identifier.count > 32 else {
            print("Identifier must be greater than 32 bytes long")
            return
        }
        DispatchQueue.main.async {
            if self.nanoTDFs.removeValue(forKey: identifier) != nil {
                self.count -= 1
                self.updateInProcessCount(self.inProcessCount - 1)
            }
        }
    }

    private func updateInProcessCount(_ newCount: Int) {
        DispatchQueue.main.async {
            if newCount > 0, self.inProcessCount == 0 {
                self.startProcessTimer()
            } else if newCount == 0, self.inProcessCount > 0 {
                self.stopProcessTimer()
            }
            self.inProcessCount = newCount
//            print("inProcessCount \(self.inProcessCount)")
        }
    }

    private func startProcessTimer() {
        DispatchQueue.main.async {
            self.processStartTime = Date()
            self.processTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let startTime = processStartTime else { return }
                DispatchQueue.main.async {
                    self.processDuration = Date().timeIntervalSince(startTime)
                    print("rewrapDuration \(String(format: "%.4f", self.processDuration))")
                    if self.processDuration > 2.0 {
                        self.stopProcessTimer()
                    }
                }
            }
        }
    }

    private func stopProcessTimer() {
        DispatchQueue.main.async {
            guard let startTime = self.processStartTime else { return }
            self.processDuration = Date().timeIntervalSince(startTime)
            self.processTimer?.invalidate()
            self.processTimer = nil
            self.processStartTime = nil
        }
    }

    func isEmpty() -> Bool {
        nanoTDFs.isEmpty
    }
}
