import SwiftUI
import SwiftData
import MapKit
import CryptoKit
import AuthenticationServices
import LocalAuthentication
import Combine
import OpenTDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    // OpenTDFKit
    @StateObject private var webSocketManager = WebSocketManager()
    let nanoTDFManager = NanoTDFManager()
    @State private var kasPublicKey: P256.KeyAgreement.PublicKey?
    // map
    @State private var cameraPosition: MapCameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), distance: 35000000, heading: 0, pitch: 0))
    @State private var showMap = true
    @State private var mapUpdateTrigger = UUID()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly
    // authentication
    @ObservedObject var amViewModel = AuthenticationManagerViewModel(baseURL: URL(string: "https://webauthn.arkavo.net")!)
    // connection
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isReconnecting = false
    @State private var hasInitialConnection = false
    // account
    @State private var selectedAccount: String = "main"
    @State private var selectedAccountIndex = 0
    private let accountOptions = ["Main", "Alt", "Private"]
    // SecureStream
    @Query private var secureStreams: [SecureStreamModel]
    @StateObject private var secureStreamModel = SecureStreamModel(
        stream: SecureStream(name: "Public", streamDescription: "Earth", ownerID: UUID())
    )
    // ThoughtStream
    @StateObject private var thoughtStreamViewModel = ThoughtStreamViewModel()
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
    
    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }
    
    #if os(iOS)
    private var iOSLayout: some View {
        ZStack {
            ZStack {
                if showMap {
                    mapContent
                } else  {
                    ThoughtStreamView(viewModel: thoughtStreamViewModel)
                }
                
                VStack() {
                    HStack {
                        Spacer()
                        Menu {
                            Section("Account") {
                                Picker("", selection: $selectedAccountIndex) {
                                    ForEach(0..<accountOptions.count, id: \.self) { index in
                                        Text(accountOptions[index]).tag(index)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .onChange(of: selectedAccountIndex) { oldValue, newValue in
                                    print("Account changed from \(accountOptions[oldValue]) to \(accountOptions[newValue])")
                                    amViewModel.authenticationManager.updateAccount(accountOptions[newValue])
                                    resetWebSocketManager()
                                }
                            }
                            Section("Authentication") {
                                Button("Sign Up") {
                                    amViewModel.authenticationManager.signUp(accountName: selectedAccount)
                                }
                                Button("Sign In") {
                                    amViewModel.authenticationManager.signUp(accountName: selectedAccount)
                                }
                            }
                            Spacer()
                            Section("Demo") {
                                if !showMap {
                                    Button("Map", action: {
                                        self.showMap = true
                                        cameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), distance: 40000000, heading: 0, pitch: 0))
                                    })
                                }
                                Button("Prepare", action: loadGeoJSON)
                                Button("Nano", action: createNanoCities)
                                Button("Display", action: animateCities)
                                Button("Add", action: loadRandomCities)
                            }
                        } label: {
                            Image(systemName: "gear")
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    //                    ++++++++++++++ Connection debug
                    //                    Spacer()
                    //                    Section(header: Text("Status")) {
                    //                        Text("WebSocket Status: \(webSocketManager.connectionState.description)")
                    //                        if let error = webSocketManager.lastError {
                    //                            Text("Error: \(error)")
                    //                                .foregroundColor(.red)
                    //                        }
                    //                        if isReconnecting {
                    //                            ProgressView()
                    //                        } else {
                    //                            Button("Reconnect") {
                    //                                resetWebSocketManager()
                    //                            }
                    //                            .buttonStyle(.bordered)
                    //                        }
                    //                        if let kasPublicKey = kasPublicKey {
                    //                            Text("KAS Public Key: \(kasPublicKey.compressedRepresentation.base64EncodedString().prefix(20))...")
                    //                                .font(.caption)
                    //                                .lineLimit(1)
                    //                                .truncationMode(.tail)
                    //                        }
                    //                    }
                    if showMap {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 1.0)) {
                                        cameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 0), distance: 400000, heading: 0, pitch: 0))
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                        withAnimation(.smooth(duration: 0.5)) {
                                            showMap = false
                                        }
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
            .ignoresSafeArea(edges: .all)
        }
        .onAppear(perform: initialSetup)
    }
    #else
    private var macOSLayout: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebarContent
        } detail: {
            ZStack {
                if showMap {
                    mapContent
                } else {
                    ThoughtStreamView(viewModel: thoughtStreamViewModel)
                }
            }
        }
        .onAppear(perform: initialSetup)
    }
    
    private var sidebarContent: some View {
        List {
            Section("Account") {
                Picker("", selection: $selectedAccountIndex) {
                    ForEach(0..<accountOptions.count, id: \.self) { index in
                        Text(accountOptions[index]).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedAccountIndex) { oldValue, newValue in
                    print("Account changed from \(accountOptions[oldValue]) to \(accountOptions[newValue])")
                    amViewModel.authenticationManager.updateAccount(accountOptions[newValue])
                    resetWebSocketManager()
                }
            }
            Section("Authentication") {
                Button("Sign Up") {
                    amViewModel.authenticationManager.signUp(accountName: selectedAccount)
                }
                Button("Sign In") { amViewModel.authenticationManager.signIn(accountName: selectedAccount)
                }
            }
            Spacer()
            Spacer()
            Section("Demo") {
                if !showMap {
                    Button("Map", action: {
                        self.showMap = true
                        cameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), distance: 40000000, heading: 0, pitch: 0))
                    })
                }
                Button("Prepare", action: loadGeoJSON)
                Button("Nano", action: createNanoCities)
                Button("Display", action: animateCities)
                Button("Add", action: loadRandomCities)
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 200)
    }
    #endif
    
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
            .gesture(mapDragGesture)
            
            VStack {
                Spacer()
                if showCityInfoOverlay {
                    cityInfoOverlay
                }
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: engageAction) {
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
    
    private func engageAction() {
        withAnimation(.easeInOut(duration: 1.0)) {
            cameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 0), distance: 400000, heading: 0, pitch: 0))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.smooth(duration: 0.5)) {
                showMap = false
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
                            distance: 2000000000,
                            heading: delta.width,
                            pitch: delta.height
                        )
                    )
                }
            }
    }
    
    private var cityInfoOverlay: some View {
        CityInfoOverlay(
            nanoTime: nanoTime,
            nanoCitiesCount: nanoCities.count,
            citiesCount: cities.count,
            decryptTime: nanoTDFManager.processDuration,
            decryptCount: nanoTDFManager.inProcessCount
        )
        .padding()
    }

    private func initialSetup() {
        amViewModel.authenticationManager.updateAccount(accountOptions[0])
        setupCallbacks()
        setupWebSocketManager()
        // Initialize ThoughtStreamViewModel
        thoughtStreamViewModel.initialize(
            webSocketManager: webSocketManager,
            nanoTDFManager: nanoTDFManager,
            kasPublicKey: $kasPublicKey
        )
    }

    private func setupCallbacks() {
        webSocketManager.setKASPublicKeyCallback { publicKey in
            DispatchQueue.main.async {
                print("Received KAS Public Key")
                self.kasPublicKey = publicKey
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
                if state == .connected && !hasInitialConnection {
                    DispatchQueue.main.async {
                        print("Initial connection established. Sending public key and KAS key message.")
                        self.webSocketManager.sendPublicKey()
                        self.webSocketManager.sendKASKeyMessage()
                        self.hasInitialConnection = true
                    }
                } else if state == .disconnected {
                    self.hasInitialConnection = false
                }
            }
            .store(in: &cancellables)
        let token = amViewModel.authenticationManager.createJWT()
        if token != nil {
            webSocketManager.setupWebSocket(token: token!)
        }
        else {
            print("createJWT token nil")
        }
        webSocketManager.connect()
    }

    private func resetWebSocketManager() {
        isReconnecting = true
        hasInitialConnection = false
        webSocketManager.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Increased delay to 1 second
            self.setupWebSocketManager()
            self.isReconnecting = false
        }
    }
    
    private func handleRewrapCallback(id: Data?, symmetricKey: SymmetricKey?) {
        guard let id = id, let symmetricKey = symmetricKey else {
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
                        self.thoughtStreamViewModel.receiveThought(thought)
                    }
                } else if let city = try? City.deserialize(from: payload) {
                    // If it's not a Thought, try to deserialize as a City
                    DispatchQueue.main.async {
                        self.addCityToCluster(city)
                        self.updateAnnotations()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.removeCityFromCluster(city)
                            self.updateAnnotations()
                        }
                    }
                } else {
                    print("Unable to deserialize payload as Thought or City")
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
    }

    private func loadRandomCities() {
        nanoTime = 0
        nanoCities = []
        print("Generating new random cities...")
        let newCities = generateRandomCities(count: 200)
        cities.append(contentsOf: newCities)
        print("New cities added: \(newCities.count)")
        print("Total cities: \(cities.count)")
    }

    private func createNanoCities() {
        print("Nanoing Cities...")
        guard kasPublicKey != nil else {
            print("KAS public key")
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
                        self.nanoCities.append(nanoTDF)
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
            self.nanoTime = endTime.timeIntervalSince(startTime)
        }
    }

    private func animateCities() {
        print("Rewrapping...")
        for nanoCity in nanoCities {
            let id = nanoCity.header.ephemeralPublicKey
            nanoTDFManager.addNanoTDF(nanoCity, withIdentifier: id)
            webSocketManager.sendRewrapMessage(header: nanoCity.header)
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
        annotations = continentClusters.flatMap { (continent, cities) -> [AnnotationItem] in
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

#Preview {
    ContentView()
        .modelContainer(for: SecureStreamModel.self, inMemory: true)
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
        if newCount > 0 && inProcessCount == 0 {
            startProcessTimer()
        } else if newCount == 0 && inProcessCount > 0 {
            stopProcessTimer()
        }
        inProcessCount = newCount
    }

    private func startProcessTimer() {
        processStartTime = Date()
        processTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.processStartTime else { return }
            print("processDuration \(Date().timeIntervalSince(startTime))")
        }
    }

    private func stopProcessTimer() {
        print("stopProcessTimer")
        guard let startTime = self.processStartTime else { return }
        self.processDuration = Date().timeIntervalSince(startTime)
        print("processDuration \(processDuration)")
        processTimer?.invalidate()
        processTimer = nil
        processStartTime = nil
    }

    func isEmpty() -> Bool {
        return nanoTDFs.isEmpty
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

    init<Content: View>(coordinate: CLLocationCoordinate2D, @ViewBuilder content: () -> Content) {
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

extension WebSocketConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        }
    }
}
