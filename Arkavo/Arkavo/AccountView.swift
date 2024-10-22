import SwiftUI

enum LocationGranularity: String, CaseIterable {
    case wide = "Wide"
    case approximate = "Approximate"
    case precise = "Precise"
}

enum IdentityAssuranceLevel: String, CaseIterable {
    case ial0 = "Anonymous" // IAL0
    case ial1 = "No identity proof" // IAL1
    case ial2 = "Remote verified" // IAL2
    case ial25 = "Enhanced remote verified" // IAL2.5
    case ial3 = "In-person proof" // IAL3
}

enum EncryptionLevel: String, CaseIterable {
    case el0 = "Standard"
    case el1 = "Military-grade"
    case el2 = "Advanced"
}

enum StreamLevel: String, CaseIterable {
    case sl0 = "Standard"
    case sl1 = "Expanded"
    case sl2 = "Hyper"
}

enum DataModeLevel: String, CaseIterable {
    case dml0 = "Standard"
    case dml1 = "Low"
}

struct AccountView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var isLocationEnabled = false
    @State private var isFaceEnabled = false
    @State private var isVoiceEnabled = false
    @State private var locationGranularity: LocationGranularity = .wide
    @State private var showingLocationPermissionAlert = false
    @State private var identityAssuranceLevel: IdentityAssuranceLevel = .ial0
    @State private var encryptionLevel: EncryptionLevel = .el0
    @State private var streamLevel: StreamLevel = .sl0
    @State private var dataModeLevel: DataModeLevel = .dml0

    var body: some View {
        List {
            Section(header: Text("Identity")) {
                Picker("Assurance", selection: $identityAssuranceLevel) {
                    ForEach(IdentityAssuranceLevel.allCases, id: \.self) { level in
                        Text(level.rawValue)
                    }
                }
            }
            Section(header: Text("Privacy")) {
                Toggle("Location", isOn: $isLocationEnabled)
                    .onChange(of: isLocationEnabled) { _, newValue in
                        if newValue {
                            requestLocationPermission()
                        }
                    }

                if isLocationEnabled {
                    Picker("Granularity", selection: $locationGranularity) {
                        ForEach(LocationGranularity.allCases, id: \.self) { granularity in
                            Text(granularity.rawValue)
                        }
                    }
                    .padding(.leading, 10)
                    if let location = locationManager.lastLocation {
                        Text("Last known location: \(location.latitude), \(location.longitude)")
                    }
                }
                Toggle("Face", isOn: $isFaceEnabled)
                    .onChange(of: isFaceEnabled) { _, newValue in
                        if newValue {}
                    }
                Toggle("Voice", isOn: $isVoiceEnabled)
                    .onChange(of: isVoiceEnabled) { _, newValue in
                        if newValue {}
                    }
                NavigationLink(destination: ClassificationView()) {
                    Text("Classification")
                }
            }
            Section(header: Text("Features")) {
                Picker("Encryption", selection: $encryptionLevel) {
                    ForEach(EncryptionLevel.allCases, id: \.self) { level in
                        Text(level.rawValue)
                    }
                }
                Picker("Stream", selection: $streamLevel) {
                    ForEach(StreamLevel.allCases, id: \.self) { level in
                        Text(level.rawValue)
                    }
                }
            }
            Section(header: Text("Settings")) {
                Picker("Data mode", selection: $dataModeLevel) {
                    ForEach(DataModeLevel.allCases, id: \.self) { level in
                        Text(level.rawValue)
                    }
                }
            }
        }
        .navigationTitle("Account")
        .alert("Location Permission", isPresented: $showingLocationPermissionAlert) {
            Button("OK") {}
        } message: {
            Text("Please grant location permission in Settings to use this feature.")
        }
        .onChange(of: locationManager.locationStatus) { _, newValue in
            if newValue == .denied || newValue == .restricted {
                isLocationEnabled = false
                showingLocationPermissionAlert = true
            }
        }
    }

    private func requestLocationPermission() {
        locationManager.requestLocation()
    }
}

struct ClassificationView: View {
    var body: some View {
        Text("Classification settings go here")
            .navigationTitle("Classification")
    }
}

struct AccountView_Previews: PreviewProvider {
    static var previews: some View {
        AccountView()
    }
}
