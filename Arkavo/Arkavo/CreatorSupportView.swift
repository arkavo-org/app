import SwiftUI

struct CreatorSupportView: View {
    let creator: Creator
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTier: CreatorTier = .basic
    @State private var isProcessing = false

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

                    // Membership Tiers
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Support Tiers")
                            .font(.headline)

                        ForEach(CreatorTier.allCases, id: \.self) { tier in
                            TierCard(
                                tier: tier,
                                isSelected: selectedTier == tier,
                                onSelect: { selectedTier = tier },
                            )
                        }
                    }

                    // Support Button
                    Button {
                        startSupport()
                    } label: {
                        Group {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Become a Supporter")
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
        }
    }

    private func startSupport() {
        isProcessing = true
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isProcessing = false
            dismiss()
        }
    }
}

struct TierCard: View {
    let tier: CreatorTier
    let isSelected: Bool
    let onSelect: () -> Void

    private var price: String {
        switch tier {
        case .basic: "$5"
        case .premium: "$10"
        case .exclusive: "$25"
        }
    }

    private var perks: [String] {
        switch tier {
        case .basic:
            ["Access to public posts", "Join community discussions", "Monthly Q&A sessions"]
        case .premium:
            ["All Basic tier perks", "Exclusive content", "Priority support", "Behind-the-scenes content"]
        case .exclusive:
            ["All Premium tier perks", "1-on-1 mentoring", "Custom requests", "Early access to new content"]
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(tier.rawValue)
                            .font(.title3)
                            .bold()
                        Text("\(price)/month")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.purple)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(perks, id: \.self) { perk in
                        Label(perk, systemImage: "checkmark")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.gray.opacity(0.3), lineWidth: 2),
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
