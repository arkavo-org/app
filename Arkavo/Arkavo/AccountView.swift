import SwiftUI

struct AccountView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var ageVerificationManager = AgeVerificationManager()
    @State private var isLocationEnabled = false
    @State private var isFaceEnabled = false
    @State private var isVoiceEnabled = false
    @State private var locationGranularity: LocationGranularity = .wide
    @State private var showingLocationPermissionAlert = false
    @State private var identityAssuranceLevel: IdentityAssuranceLevel = .ial0
    @State private var encryptionLevel: EncryptionLevel = .el0
    @State private var streamLevel: StreamLevel = .sl0
    @State private var dataModeLevel: DataModeLevel = .dml0
    @State private var showingAgeVerification = false

    var body: some View {
        List {
            Section(header: Text("Identity")) {
                Picker("Assurance", selection: $identityAssuranceLevel) {
                    ForEach(IdentityAssuranceLevel.allCases, id: \.self) { level in
                        Text(level.rawValue)
                    }
                }

                HStack {
                    Text("Age Verification")
                    Spacer()
                    Text(ageVerificationManager.verificationStatus.rawValue)
                        .foregroundColor(verificationStatusColor)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if ageVerificationManager.verificationStatus != .verified {
                        showingAgeVerification = true
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
                Toggle("Voice", isOn: $isVoiceEnabled)
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
        .sheet(isPresented: $showingAgeVerification) {
            AgeVerificationView(ageVerificationManager: ageVerificationManager)
        }
        .onChange(of: locationManager.locationStatus) { _, newValue in
            if newValue == .denied || newValue == .restricted {
                isLocationEnabled = false
                showingLocationPermissionAlert = true
            }
        }
    }

    private var verificationStatusColor: Color {
        switch ageVerificationManager.verificationStatus {
        case .unverified:
            .gray
        case .pending:
            .orange
        case .verified:
            .green
        case .failed:
            .red
        }
    }

    private func requestLocationPermission() {
        locationManager.requestLocation()
    }
}

struct AgeVerificationView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var ageVerificationManager: AgeVerificationManager

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Age Verification")
                    .font(.title)
                    .padding()

                Text("Please provide a valid government-issued ID and a selfie to verify your age.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if ageVerificationManager.isVerifying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Button(action: {
                        ageVerificationManager.startVerification()
                    }) {
                        Text("Start Verification")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
            }
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .fullScreenCover(isPresented: $ageVerificationManager.showingScanner) {
                IDCardScannerView(
                    onCapture: { image in
                        ageVerificationManager.showingScanner = false
                        Task {
                            await ageVerificationManager.processCapturedImage(image)
                        }
                    },
                    onCancel: {
                        ageVerificationManager.showingScanner = false
                        ageVerificationManager.isVerifying = false
                        ageVerificationManager.verificationStatus = .unverified
                    }
                )
            }
        }
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

enum AgeVerificationStatus: String, CaseIterable {
    case unverified = "Not Verified"
    case pending = "Verification Pending"
    case verified = "Verified 18+"
    case failed = "Verification Failed"
}
