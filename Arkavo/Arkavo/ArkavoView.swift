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
    @Environment(\.modelContext) private var modelContext
    // OpenTDFKit
    @StateObject private var webSocketManager = WebSocketManager()
    let nanoTDFManager = NanoTDFManager()
    @State private var kasPublicKey: P256.KeyAgreement.PublicKey?
    // map
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapUpdateTrigger = UUID()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly
    // connection
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isReconnecting = false
    @State private var hasInitialConnection = false
    // account
    @State private var showingProfileCreation = false
    @State private var showingProfileDetails = false
    // ThoughtStream
    @StateObject private var thoughtStreamViewModel = ThoughtStreamViewModel()
    // video
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        @StateObject private var videoStreamViewModel = VideoStreamViewModel()
    #endif
    // demo
    @State private var showCityInfoOverlay = false
    @State private var cities: [City] = []
    @State private var cityCount = 0
    @State private var nanoCities: [NanoTDF] = []
    @State private var nanoTime: TimeInterval = 0
    @StateObject private var annotationManager = AnnotationManager()
    @State private var inProcessCount = 0
    @State private var continentClusters: [String: [City]] = [:]
    @State private var annotations: [AnnotationItem] = []
    // view control
    @State private var selectedView: SelectedView = .map
    private var authenticationManager = AuthenticationManager()
    @Query private var accounts: [Account]
    @Query private var profiles: [Profile]

    init() {}

    enum SelectedView {
        case map
        case wordCloud
        case streams
        case video
    }

    var body: some View {
        ZStack {
            ZStack {
                switch selectedView {
                case .map:
                    mapContent
                        .sheet(isPresented: $showingProfileCreation) {
                            if let account = accounts.first {
                                AccountProfileCreateView { newProfile in
                                    account.profile = newProfile
                                    thoughtStreamViewModel.profile = newProfile
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Failed to save profile: \(error)")
                                    }
                                }
                            }
                        }
                        .sheet(isPresented: $showingProfileDetails) {
                            if let account = accounts.first {
                                if let profile = account.profile {
                                    AccountProfileDetailedView(viewModel: AccountProfileViewModel(profile: profile))
                                }
                            }
                        }
                case .wordCloud:
                    if let account = accounts.first {
                        if !account.streams.isEmpty {
                            let words: [(String, CGFloat)] = account.streams.map { ($0.name, 40) }
                            WordCloudView(
                                viewModel: WordCloudViewModel(
                                    thoughtStreamViewModel: thoughtStreamViewModel,
                                    words: words,
                                    animationType: .falling
                                )
                            )
                        } else {
                            let words: [(String, CGFloat)] = [
                                ("SwiftUI", 60), ("iOS", 50), ("Xcode", 45), ("Swift", 55),
                                ("Apple", 40), ("Developer", 35), ("Code", 30), ("App", 25),
                                ("UI", 20), ("UX", 15), ("Design", 30), ("Mobile", 25),
                            ]
                            WordCloudView(
                                viewModel: WordCloudViewModel(
                                    thoughtStreamViewModel: thoughtStreamViewModel,
                                    words: words,
                                    animationType: .explosion
                                )
                            )
                        }
                    }
                case .video:
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                        VideoStreamView(viewModel: videoStreamViewModel)
                    #endif
                case .streams:
                    StreamManagementView()
                }
                VStack {
                    GeometryReader { geometry in
                        HStack {
                            Spacer()
                                .frame(width: geometry.size.width * 0.8)
                            Menu {
                                Section("Navigation") {
                                    Button("Map") {
                                        selectedView = .map
                                        withAnimation(.easeInOut(duration: 2.5)) {
                                            cameraPosition = .camera(MapCamera(
                                                centerCoordinate: CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129), // Center of USA
                                                distance: 40_000_000,
                                                heading: 0,
                                                pitch: 0
                                            ))
                                        }
                                    }
                                    Button("My Streams") {
                                        selectedView = .streams
                                    }
                                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                                        Button("Video") {
                                            selectedView = .video
                                        }
                                    #endif
                                    Button("Engage!") {
                                        selectedView = .wordCloud
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
                                        if let attestationEnvelope = account.attestationEnvelope {
                                            VStack(alignment: .leading) {
                                                Text("ID: \(attestationEnvelope.base64EncodedString())")
                                            }
                                            Button("Sign In") {
                                                authenticationManager.signIn(accountName: account.id.uuidString)
                                            }
                                        } else {
                                            Button("Sign Up") {
                                                authenticationManager.signUp(accountName: account.id.uuidString)
                                            }
                                            // FIXME: remove
                                            Button("Sign In") {
                                                authenticationManager.signIn(accountName: account.id.uuidString)
                                            }
                                        }
                                    }
                                }
                                Section("Demo") {
                                    Button("Cities", action: loadGeoJSON)
                                    Button("Clusters", action: loadRandomCities)
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
            .ignoresSafeArea(edges: .all)
        }
        .onAppear(perform: initialSetup)
    }

    private var mapContent: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(annotations) { item in
                    if item.isCluster {
                        Annotation(item.name, coordinate: item.coordinate) {
                            ClusterAnnotationView(count: item.count, continent: item.name)
                        }
                    } else {
                        Marker(item.name, coordinate: item.coordinate)
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .task {
                await showGlobeCenteredOnUserCountry()
            }

            VStack {
                Spacer()
                if showCityInfoOverlay {
                    cityInfoOverlay
                }
            }
            if thoughtStreamViewModel.profile != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                await engageAction()
                            }
                        }) {
                            Text("Engage!")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding()
                    }
                }
            }
        }
    }

    private func showGlobeCenteredOnUserCountry() async {
        let centerCoordinate = await getCountryCenterCoordinate()
        cameraPosition = .camera(MapCamera(
            centerCoordinate: centerCoordinate,
            distance: 40_000_000,
            heading: 0,
            pitch: 0
        ))
    }

    private func getCountryCenterCoordinate() async -> CLLocationCoordinate2D {
        let countryCode = locale.region?.identifier ?? "US"
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(countryCode)
            return (placemarks.first?.location!.coordinate)!
        } catch {
            print("Geocoding failed: \(error.localizedDescription)")
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
    }

    private func engageAction() async {
        let centerCoordinate = await getCountryCenterCoordinate()
        var currentCenter = centerCoordinate
        if cameraPosition.camera != nil {
            currentCenter = cameraPosition.camera!.centerCoordinate
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: currentCenter,
                distance: 400_000,
                heading: 0,
                pitch: 0
            ))
        }
        // Switch to word cloud view
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.smooth(duration: 0.5)) {
                selectedView = .wordCloud
            }
        }
    }

    private var mapDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let delta = value.translation
                withAnimation {
                    cameraPosition = MapCameraPosition.camera(
                        MapCamera(
                            centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                            distance: 40_000_000,
                            heading: delta.width,
                            pitch: delta.height
                        )
                    )
                }
            }
    }

    private var cityInfoOverlay: some View {
        PerformanceInfoOverlay(
            nanoTime: nanoTime,
            nanoCitiesCount: nanoCities.count,
            citiesCount: cities.count,
            decryptTime: nanoTDFManager.processDuration,
            decryptCount: nanoTDFManager.inProcessCount
        )
        .padding()
    }

    private func initialSetup() {
        setupCallbacks()
        setupWebSocketManager()
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
            if !profiles.isEmpty {
                if account.profile == nil {
                    account.profile = profiles.first
                    thoughtStreamViewModel.profile = profiles.first
                }
            }
        }
    }

    private func setupCallbacks() {
        webSocketManager.setKASPublicKeyCallback { publicKey in
            if kasPublicKey != nil {
                // go ahead and show something on the map
                loadGeoJSON()
                showCityInfoOverlay = false
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
        // FIXME: replace using account
        let token = authenticationManager.createJWT(profileName: "Main")
        if token != nil {
            webSocketManager.setupWebSocket(token: token!)
        } else {
            print("createJWT token nil")
        }
        webSocketManager.connect()
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
                        addCityToCluster(city)
                        updateAnnotations()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            removeCityFromCluster(city)
                            updateAnnotations()
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

    private func addCityAnnotation(_ city: City) {
        annotationManager.addAnnotation(city)
    }

    private func removeCityAnnotation(_ city: City) {
        annotationManager.removeAnnotation(city)
    }

    private func loadGeoJSON() {
        showCityInfoOverlay = true
        cities = generateTwoThousandActualCities()
        createNanoCities()
    }

    private func loadRandomCities() {
        showCityInfoOverlay = true
        nanoTime = 0
        nanoCities = []
        print("Generating new random cities...")
        let newCities = generateRandomCities(count: 1000)
        cities.append(contentsOf: newCities)
        print("New cities added: \(newCities.count)")
        print("Total cities: \(cities.count)")
        createNanoCities()
    }

    private func createNanoCities() {
        print("Nanoing Cities...")
        guard kasPublicKey != nil else {
            print("Missing KAS public key")
            return
        }
        let startTime = Date()
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue(label: "com.arkavo.nanoTDFCreation", attributes: .concurrent)

        for city in cities {
            dispatchGroup.enter()
            queue.async {
                do {
                    let serializedCity = try city.serialize()
                    let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")
                    let kasMetadata = KasMetadata(resourceLocator: kasRL!, publicKey: kasPublicKey!, curve: .secp256r1)
//                    let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")
                    let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: city.continent)
                    var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

                    let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: serializedCity)

                    DispatchQueue.main.async {
                        nanoCities.append(nanoTDF)
                        dispatchGroup.leave()
                    }
                } catch {
                    print("Error creating nanoTDF for \(city.name): \(error)")
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            let endTime = Date()
            nanoTime = endTime.timeIntervalSince(startTime)
            sendCities()
        }
    }

    private func sendCities() {
        print("Sending...")
        // Limit the number of cities to 3000
        let maxCitiesToSend = 3000
        let citiesToSend = nanoCities.prefix(maxCitiesToSend)
        for nanoCity in citiesToSend {
            // Create and send the NATSMessage
            let natsMessage = NATSMessage(payload: nanoCity.toData())
            let messageData = natsMessage.toData()
//            print("City NATS message payload sent: \(natsMessage.payload.base64EncodedString())")

            webSocketManager.sendCustomMessage(messageData) { error in
                if let error {
                    print("Error sending thought: \(error)")
                }
            }
        }
    }

    private func addCityToCluster(_ city: City) {
        if continentClusters[city.continent] == nil {
            continentClusters[city.continent] = []
        }
        continentClusters[city.continent]?.append(city)
        cityCount += 1
    }

    private func removeCityFromCluster(_ city: City) {
        continentClusters[city.continent]?.removeAll { $0.id == city.id }
        cityCount -= 1
    }

    private func updateAnnotations() {
        annotations = continentClusters.flatMap { continent, cities -> [AnnotationItem] in
            if cities.count > 50 {
                let centerCoordinate = calculateCenterCoordinate(for: cities)
                return [AnnotationItem(coordinate: centerCoordinate, name: continent, count: cities.count, isCluster: true)]
            } else {
                return cities.map { city in
                    AnnotationItem(coordinate: city.clCoordinate, name: city.name, count: 1, isCluster: false)
                }
            }
        }
        mapUpdateTrigger = UUID()
    }

    private func calculateCenterCoordinate(for cities: [City]) -> CLLocationCoordinate2D {
        let totalLat = cities.reduce(0.0) { $0 + $1.coordinate.latitude }
        let totalLon = cities.reduce(0.0) { $0 + $1.coordinate.longitude }
        let count = Double(cities.count)
        return CLLocationCoordinate2D(latitude: totalLat / count, longitude: totalLon / count)
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

class AnnotationManager: ObservableObject {
    @Published var annotations: [CityAnnotation] = []

    func addAnnotation(_ city: City) {
        DispatchQueue.main.async {
            if !self.annotations.contains(where: { $0.id == city.id }) {
                self.annotations.append(CityAnnotation(city: city))
            }
        }
    }

    func removeAnnotation(_ city: City) {
        DispatchQueue.main.async {
            self.annotations.removeAll { $0.id == city.id }
        }
    }
}

struct ClusterAnnotationView: View {
    let count: Int
    let continent: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 50, height: 50)
            VStack {
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                Text(continent)
                    .font(.system(size: 10))
            }
            .foregroundColor(.white)
        }
    }
}

struct CityAnnotationView: View {
    let city: City

    var body: some View {
        VStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.red)
                .font(.title)
            Text(city.name)
                .font(.caption)
                .fixedSize()
        }
    }
}

struct IdentifiableMapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let content: AnyView

    init(coordinate: CLLocationCoordinate2D, @ViewBuilder content: () -> some View) {
        self.coordinate = coordinate
        self.content = AnyView(content())
    }
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let name: String
    let count: Int
    let isCluster: Bool
}
