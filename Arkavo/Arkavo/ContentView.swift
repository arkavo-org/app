import SwiftUI
import SwiftData
import MapKit
import CryptoKit
import AuthenticationServices
import LocalAuthentication
import OpenTDFKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var items: [Item]
    @StateObject private var webSocketManager = WebSocketManager()
    let nanoTDFManager = NanoTDFManager()
    @State private var kasPublicKey: P256.KeyAgreement.PublicKey?
    @State private var cities: [City] = []
    @State private var mapUpdateTrigger = UUID()
    @State private var cityCount = 0
    @State private var nanoCities: [NanoTDF] = []
    @State private var nanoTime: TimeInterval = 0
    @State private var annotations: [CityAnnotation] = []
    @ObservedObject var amViewModel = AuthenticationManagerViewModel()
    @StateObject private var annotationManager = AnnotationManager()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var inProcessCount = 0
    
    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }
    
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            ZStack {
                mapContent
                
                VStack {
                    HStack {
                        controlsMenu
                        Spacer()
                        itemListButton
                    }
                    .padding()
                    
                    Spacer()
                    cityInfoOverlay
                }
            }
            .ignoresSafeArea(edges: .all)
        }
        .onAppear(perform: setupWebSocketManager)
    }
    #else
    private var macOSLayout: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            mapContent
        }
        .onAppear(perform: setupWebSocketManager)
    }
    
    private var sidebarContent: some View {
        List {
            Section("Controls") {
                Button("Prepare", action: loadGeoJSON)
                Button("Nano", action: createNanoCities)
                Button("Display", action: animateCities)
                Button("Add", action: loadRandomCities)
            }
            
            Section("Authentication") {
                Button("Sign Up", action: amViewModel.authenticationManager.signUp)
                Button("Sign In", action: amViewModel.authenticationManager.signIn)
            }
            
            Section("Items") {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 200)
    }
    #endif
    
    private var mapContent: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(annotationManager.annotations) { annotation in
                    Marker(annotation.city.name, coordinate: annotation.city.clCoordinate)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .gesture(mapDragGesture)
            
            VStack {
                Spacer()
                cityInfoOverlay
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
    
//    private var cityInfoOverlay: some View {
//        VStack {
//            if nanoTDFManager.processDuration > 0 {
//                Text("Decrypt (Rewrap) time: \(String(format: "%.2f", nanoTDFManager.processDuration)) seconds")
//            }
//            Text("Decrypt (Rewrap) count: \(nanoTDFManager.inProcessCount)")
//            if nanoTime > 0 {
//                Text("Encrypt time: \(String(format: "%.2f", nanoTime)) seconds")
//            }
//            if !nanoCities.isEmpty {
//                Text("Nano count: \(nanoCities.count)")
//            }
//            if cities.count > 0 {
//                Text("City count: \(cities.count)")
//            }
//        }
//        .padding()
//        .background(Color.black.opacity(0.7))
//        .cornerRadius(10)
//        .padding()
//    }
    
    #if os(iOS)
    private var controlsMenu: some View {
        Menu {
            Button("Prepare", action: loadGeoJSON)
            Button("Nano", action: createNanoCities)
            Button("Display", action: animateCities)
            Button("Add", action: loadRandomCities)
            Divider()
            Button("Sign Up", action: amViewModel.authenticationManager.signUp)
            Button("Sign In", action: amViewModel.authenticationManager.signIn)
        } label: {
            Image(systemName: "gear")
                .padding()
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
    
    private var itemListButton: some View {
        NavigationLink(destination: ItemListView(items: items, deleteItems: deleteItems)) {
            Image(systemName: "list.bullet")
                .padding()
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
    #endif

    private func setupWebSocketManager() {
        webSocketManager.setKASPublicKeyCallback { publicKey in
            kasPublicKey = publicKey
        }
        webSocketManager.setRewrapCallback(callback: handleRewrapCallback)
        webSocketManager.connect()
        webSocketManager.sendPublicKey()
        webSocketManager.sendKASKeyMessage()
    }

    private func handleRewrapCallback(id: Data?, symmetricKey: SymmetricKey?) {
        guard let id = id, let nanoCity = nanoTDFManager.getNanoTDF(withIdentifier: id) else { return }
        nanoTDFManager.removeNanoTDF(withIdentifier: id)

        guard let symmetricKey = symmetricKey else {
            print("DENY")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let payload = try nanoCity.getPayloadPlaintext(symmetricKey: symmetricKey)
                let city = try City.deserialize(from: payload)
                
                DispatchQueue.main.async {
                    self.addCityAnnotation(city)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.removeCityAnnotation(city)
                    }
                }
            } catch {
                print("getPayloadPlaintext failed: \(error)")
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
        print("Generating Cities...")
        cities = generateTwoThousandActualCities()
        print("Cities loaded: \(cities.count)")
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
                    let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")
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

    private func addItem() {
        let _ = "Keep this message secret".data(using: .utf8)!
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
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
        print("startProcessTimer")
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

#if os(iOS)
struct ItemListView: View {
    let items: [Item]
    let deleteItems: (IndexSet) -> Void

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                } label: {
                    Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("Items")
        .toolbar {
            EditButton()
        }
    }
}
#endif

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
