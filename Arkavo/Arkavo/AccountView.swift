import ArkavoStore
import StoreKit
import SwiftData
import SwiftUI

struct AccountView: View {
    @Query private var accounts: [Account]
    @StateObject private var locationManager = LocationManager()
    @StateObject private var storeKitManager = StoreKitManager()
    #if !os(macOS)
        @StateObject private var ageVerificationManager = AgeVerificationManager()
    #endif
    @State private var isLocationEnabled = false
    @State private var isFaceEnabled = false
    @State private var isVoiceEnabled = false
    @State private var locationGranularity: LocationGranularity = .wide
    @State private var showingLocationPermissionAlert = false
    @State private var identityAssuranceLevel: IdentityAssuranceLevel = .ial0
    @State private var streamLevel: StreamLevel = .sl0
    @State private var dataModeLevel: DataModeLevel = .dml0
    @State private var showingAgeVerification = false
    @State private var showingDeleteProfileAlert = false
    @State private var isResettingProfile = false
    @State private var showingEncryptionUpgrade = false

    private var account: Account? {
        accounts.first
    }

    private var encryptionIcon: String {
        switch account?.entitlementTier ?? .low {
        case .low: "lock"
        case .medium: "lock.fill"
        case .high: "lock.shield.fill"
        }
    }

    var body: some View {
        List {
            Section(header: Text("Identity")) {
                HStack {
                    Text("Assurance")
                    Spacer()
                    Text(account?.identityAssuranceLevel.rawValue ?? IdentityAssuranceLevel.ial0.rawValue)
                }

                #if !os(macOS)
                    AgeVerificationRow(
                        account: account,
                        showingAgeVerification: $showingAgeVerification,
                    )
                #else
                    HStack {
                        Text("Age Verification")
                        Spacer()
                        Text("Not available on macOS")
                            .foregroundColor(.gray)
                    }
                #endif
            }

            Section(header: Text("Profile Management")) {
                Button(action: {
                    showingDeleteProfileAlert = true
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .foregroundColor(.red)
                        Text("Reset Profile")
                            .foregroundColor(.red)
                    }
                }
                .disabled(isResettingProfile)
                .alert("Reset Profile", isPresented: $showingDeleteProfileAlert) {
                    Button("Cancel", role: .cancel) {
                        // Empty closure: Default behavior is to dismiss the alert.
                    }
                    Button("Reset", role: .destructive) {
                        resetProfile()
                    }
                } message: {
                    Text("This will delete your profile and all associated encryption keys. A new empty profile will be created. This action cannot be undone.")
                }
            }

            // Rest of the sections remain unchanged
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
                Button {
                    showingEncryptionUpgrade = true
                } label: {
                    HStack {
                        Label("Encryption", systemImage: encryptionIcon)
                        Spacer()
                        Text(account?.entitlementTier.displayName ?? "Basic")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)

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
        .sheet(isPresented: $showingEncryptionUpgrade) {
            EncryptionUpgradeView(storeKitManager: storeKitManager, account: account)
        }
        .alert("Location Permission", isPresented: $showingLocationPermissionAlert) {
            Button("OK") {
                // Empty closure: Default behavior is to dismiss the alert.
            }
        } message: {
            Text("Please grant location permission in Settings to use this feature.")
        }
        #if !os(macOS)
        .sheet(isPresented: $showingAgeVerification) {
            AgeVerificationView(ageVerificationManager: ageVerificationManager)
        }
        .onChange(of: ageVerificationManager.verificationStatus) { _, newValue in
            if newValue == .verified {
                Task {
                    await updateAccountVerification(status: .verified)
                }
                showingAgeVerification = false
            }
        }
        #endif
        .onChange(of: locationManager.locationStatus) { _, newValue in
            if newValue == .denied || newValue == .restricted {
                isLocationEnabled = false
                showingLocationPermissionAlert = true
            }
        }
        .task {
            if let account {
                identityAssuranceLevel = account.identityAssuranceLevel
                #if !os(macOS)
                    ageVerificationManager.verificationStatus = account.ageVerificationStatus
                #endif
            }
        }
    }

    private func requestLocationPermission() {
        locationManager.requestLocation()
    }

    private func updateAccountVerification(status: AgeVerificationStatus) async {
        guard let account else { return }
        account.updateVerificationStatus(status)
        do {
            try await PersistenceController.shared.saveChanges()
        } catch {
            print("Error saving verification status: \(error)")
        }
    }

    private func resetProfile() {
        Task {
            isResettingProfile = true
            defer { isResettingProfile = false }

            do {
                guard let account, let profile = account.profile else {
                    print("No account or profile found to reset")
                    return
                }

                // Delete the profile, which will clear KeyStore data and create a new empty profile
                try await PersistenceController.shared.deleteProfile(profile)

                // Reset local state variables
                identityAssuranceLevel = .ial0
                #if !os(macOS)
                    ageVerificationManager.verificationStatus = .unverified
                #endif

                print("Profile successfully reset")
            } catch {
                print("Error resetting profile: \(error)")
            }
        }
    }
}

#if !os(macOS)
    // Helper view to keep the age verification row logic contained
    struct AgeVerificationRow: View {
        let account: Account?
        @Binding var showingAgeVerification: Bool

        var body: some View {
            HStack {
                Text("Age Verification")
                Spacer()
                Text(account?.ageVerificationStatus.rawValue ?? AgeVerificationStatus.unverified.rawValue)
                    .foregroundColor(verificationStatusColor)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if account?.ageVerificationStatus != .verified {
                    showingAgeVerification = true
                }
            }
        }

        private var verificationStatusColor: Color {
            switch account?.ageVerificationStatus ?? .unverified {
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
                #if !os(visionOS)
                .fullScreenCover(isPresented: $ageVerificationManager.showingScanner) {
                    IDCardScannerView(
                        onCapture: { _ in
                            // TODO: Process captured ID card data
                            ageVerificationManager.showingScanner = false
                            ageVerificationManager.isVerifying = false
                            ageVerificationManager.verificationStatus = .verified // Placeholder: Assume success for now
                        },
                        onCancel: {
                            ageVerificationManager.showingScanner = false
                            ageVerificationManager.isVerifying = false
                            ageVerificationManager.verificationStatus = .unverified
                        },
                    )
                }
                #endif
            }
        }
    }
#endif

struct ClassificationView: View {
    var body: some View {
        // TODO: Implement classification settings UI
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
    case ial2 = "Verified on Device" // IAL2
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

// MARK: - Encryption Upgrade View

struct EncryptionUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var storeKitManager: StoreKitManager
    let account: Account?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false

    private var currentTier: EntitlementTier {
        account?.entitlementTier ?? .low
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.linearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))

                        Text("Encryption Level")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Upgrade your encryption for enhanced security")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)

                    // Current tier badge
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Current: \(currentTier.displayName)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)

                    // Encryption tiers
                    if storeKitManager.isLoadingProducts {
                        ProgressView("Loading plans...")
                            .padding()
                    } else {
                        VStack(spacing: 16) {
                            EncryptionTierCard(
                                tier: .low,
                                product: nil,
                                isCurrent: currentTier == .low,
                                onUpgrade: nil
                            )

                            if let mediumProduct = storeKitManager.products.first(where: { $0.id.contains("medium.monthly") }) {
                                EncryptionTierCard(
                                    tier: .medium,
                                    product: mediumProduct,
                                    isCurrent: currentTier == .medium,
                                    onUpgrade: { await purchase(mediumProduct) }
                                )
                            } else {
                                EncryptionTierCard(
                                    tier: .medium,
                                    product: nil,
                                    isCurrent: currentTier == .medium,
                                    onUpgrade: nil
                                )
                            }

                            if let highProduct = storeKitManager.products.first(where: { $0.id.contains("high.monthly") }) {
                                EncryptionTierCard(
                                    tier: .high,
                                    product: highProduct,
                                    isCurrent: currentTier == .high,
                                    onUpgrade: { await purchase(highProduct) }
                                )
                            } else {
                                EncryptionTierCard(
                                    tier: .high,
                                    product: nil,
                                    isCurrent: currentTier == .high,
                                    onUpgrade: nil
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Restore purchases
                    Button {
                        Task {
                            await restorePurchases()
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .disabled(isProcessing)
                    .padding(.bottom)
                }
                .padding()
            }
            .navigationTitle("Encryption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your encryption has been upgraded!")
            }
            .task {
                await storeKitManager.loadProducts()
            }
        }
    }

    private func purchase(_ product: StoreKit.Product) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            if let _ = try await storeKitManager.purchase(product) {
                let tier = ProductTierMapping.tier(for: product.id)
                account?.updateEntitlementTier(tier)
                try? await PersistenceController.shared.saveChanges()
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func restorePurchases() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await storeKitManager.restorePurchases()
            let tier = await storeKitManager.currentEncryptionTier()
            if tier != .low {
                account?.updateEntitlementTier(tier)
                try? await PersistenceController.shared.saveChanges()
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct EncryptionTierCard: View {
    let tier: EntitlementTier
    let product: StoreKit.Product?
    let isCurrent: Bool
    let onUpgrade: (() async -> Void)?

    private var icon: String {
        switch tier {
        case .low: "lock"
        case .medium: "lock.fill"
        case .high: "lock.shield.fill"
        }
    }

    private var color: Color {
        switch tier {
        case .low: .gray
        case .medium: .blue
        case .high: .purple
        }
    }

    private var price: String {
        if let product {
            return "\(product.displayPrice)/month"
        }
        return tier == .low ? "Free" : "N/A"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.headline)
                    Text(price)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isCurrent {
                    Text("CURRENT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                } else if onUpgrade != nil {
                    Button {
                        Task {
                            await onUpgrade?()
                        }
                    } label: {
                        Text("Upgrade")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(color)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }

            Text(tier.encryptionLevel.description)
                .font(.footnote)
                .foregroundColor(.secondary)

            Text(tier.encryptionLevel.technicalDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? color : Color.gray.opacity(0.3), lineWidth: isCurrent ? 2 : 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? color.opacity(0.05) : Color.clear)
        )
    }
}
