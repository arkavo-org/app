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
    @State private var cameraPosition = MapCameraPosition.camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            distance: 20000000,
            heading: 0,
            pitch: 0
        )
    )
    @State private var cities: [City] = []
    @State private var mapUpdateTrigger = UUID()
    @State private var cityCount = 0
    @State private var nanoCities: [NanoTDF] = []
    @State private var nanoTime: TimeInterval = 0
    @State private var annotations: [CityAnnotation] = []
    @ObservedObject var amViewModel = AuthenticationManagerViewModel()
    
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
                ForEach(annotations) { annotation in
                    Marker(annotation.city.name, coordinate: annotation.city.clCoordinate)
                }
            }
            .id(mapUpdateTrigger)
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
        VStack {
            if nanoTime > 0 {
                Text("Encrypt: \(String(format: "%.2f", nanoTime)) seconds")
            }
            if !nanoCities.isEmpty {
                Text("Nano count: \(nanoCities.count)")
            }
            if cities.count > 0 {
                Text("Data count: \(cities.count)")
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .padding()
    }
    
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

    private func addCityAnnotation(_ city: City) {
        let annotation = CityAnnotation(city: city)
        annotations.append(annotation)
        cityCount += 1
    }
    
    private func removeCityAnnotation(_ city: City) {
        annotations.removeAll { $0.city.id == city.id }
        cityCount -= 1
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
            print("Cities nanoed: \(self.nanoCities.count)")
            print("Time taken: \(self.nanoTime) seconds")
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
//            let kasRL = ResourceLocator(protocolEnum: .http, body: "localhost:8080")
//            let kasMetadata = KasMetadata(resourceLocator: kasRL!, publicKey: publicKey, curve: .secp256r1)
//            let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "localhost/123")
//            var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
//
//            do {
//                // create
//                let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: plaintext)
//                print("Encryption successful")
//            } catch {
//                print("Error creating nanoTDF: \(error)")
//            }
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

class NanoTDFManager {
    private var nanoTDFs: [Data: NanoTDF] = [:]
    private var count: Int = 0

    func addNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) {
        nanoTDFs[identifier] = nanoTDF
        count += 1
    }

    func getNanoTDF(withIdentifier identifier: Data) -> NanoTDF? {
        nanoTDFs[identifier]
    }

    func updateNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) {
        nanoTDFs[identifier] = nanoTDF
    }

    func removeNanoTDF(withIdentifier identifier: Data) {
        if nanoTDFs.removeValue(forKey: identifier) != nil {
            count -= 1
        }
    }

    func isEmpty() -> Bool {
        return nanoTDFs.isEmpty
    }

    func getCount() -> Int {
        return count
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
