import ArkavoStore
import StoreKit
import SwiftUI

struct CreatorSupportView: View {
    let creator: Creator
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeKitManager = StoreKitManager()
    @State private var selectedTier: CreatorTier = .basic
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Creator Header
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.blue)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(creator.name)
                                .font(.title2)
                                .bold()
                            Text(creator.bio)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)

                    // Encryption Tiers
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Encryption Tiers")
                            .font(.headline)

                        if storeKitManager.isLoadingProducts {
                            ProgressView("Loading plans...")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if storeKitManager.products.isEmpty {
                            // Fallback to static tiers if products not available
                            ForEach(CreatorTier.allCases, id: \.self) { tier in
                                TierCard(
                                    tier: tier,
                                    product: nil,
                                    isSelected: selectedTier == tier,
                                    onSelect: { selectedTier = tier }
                                )
                            }
                        } else {
                            // Show StoreKit products
                            ForEach(CreatorTier.allCases, id: \.self) { tier in
                                let product = productForTier(tier)
                                TierCard(
                                    tier: tier,
                                    product: product,
                                    isSelected: selectedTier == tier,
                                    onSelect: { selectedTier = tier }
                                )
                            }
                        }
                    }

                    // Support Button
                    if selectedTier != .basic {
                        Button {
                            Task {
                                await startSupport()
                            }
                        } label: {
                            Group {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Subscribe")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isProcessing)
                    }

                    // Restore Purchases Button
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
                }
                .padding()
            }
            .navigationTitle("Support \(creator.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { /* Dismisses alert */ }
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you! Your encryption has been upgraded.")
            }
            .task {
                await storeKitManager.loadProducts()
            }
        }
    }

    private func productForTier(_ tier: CreatorTier) -> Product? {
        let productID: String
        switch tier {
        case .basic:
            return nil // Free tier
        case .premium:
            productID = ProductIdentifier.encryptionMediumMonthly
        case .exclusive:
            productID = ProductIdentifier.encryptionHighMonthly
        }
        return storeKitManager.product(for: productID)
    }

    private func startSupport() async {
        isProcessing = true
        defer { isProcessing = false }

        guard let product = productForTier(selectedTier) else {
            errorMessage = "Product not available. Please try again later."
            showError = true
            return
        }

        do {
            if let _ = try await storeKitManager.purchase(product) {
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
            if !storeKitManager.purchasedProductIDs.isEmpty {
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct TierCard: View {
    let tier: CreatorTier
    let product: Product?
    let isSelected: Bool
    let onSelect: () -> Void

    private var encryptionLevel: ArkavoStore.EncryptionLevel {
        switch tier {
        case .basic: .low
        case .premium: .medium
        case .exclusive: .high
        }
    }

    private var price: String {
        if let product {
            return product.displayPrice
        }
        switch tier {
        case .basic: return "Free"
        case .premium: return "$4.99"
        case .exclusive: return "$9.99"
        }
    }

    private var priceLabel: String {
        if tier == .basic {
            return "Free"
        }
        return "\(price)/month"
    }

    private var icon: String {
        switch encryptionLevel {
        case .low: "lock"
        case .medium: "lock.fill"
        case .high: "lock.shield.fill"
        }
    }

    private var iconColor: Color {
        switch encryptionLevel {
        case .low: .gray
        case .medium: .blue
        case .high: .purple
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(iconColor)

                    VStack(alignment: .leading) {
                        Text(encryptionLevel.displayName)
                            .font(.title3)
                            .bold()
                        Text(priceLabel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.purple)
                    }
                }

                Text(encryptionLevel.description)
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Text(encryptionLevel.technicalDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.gray.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
