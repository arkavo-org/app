//
//  PatronManagementView.swift
//  Arkavo
//
//  Created by Paul Flynn on 11/29/24.
//

import ArkavoSocial
import SwiftUI

// MARK: - Main View

struct PatronManagementView: View {
    let patreonClient: PatreonClient
    @State private var selectedTier: PatronTier?
    @State private var selectedCampaign: Campaign?
    @State private var searchText = ""
    @State private var showNewTierSheet = false
    @State private var sortOrder = [KeyPathComparator(\Patron.name)]
    @State private var filterStatus: PatronStatus?
    @State private var selectedPatrons: Set<Patron> = []
    @State private var showingExportMenu = false
    @State private var isEditingMode = false
    // Environment values for system appearance
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Left side - Campaigns & Tiers
            VStack(spacing: 0) {
                // Campaigns Sidebar
                CampaignsSidebar(
                    patreonClient: patreonClient,
                    selectedCampaign: $selectedCampaign
                )
                .frame(height: 120)

                Divider()

                // Tiers Sidebar
                TiersSidebar(
                    selectedCampaign: $selectedCampaign,
                    selectedTier: $selectedTier,
                    showNewTierSheet: $showNewTierSheet,
                    isEditingMode: $isEditingMode
                )
            }
            .frame(minWidth: 250, maxWidth: 300)

            // Divider between sidebar and content
            Divider()

            // Right side - Patron list
            PatronListView(
                patreonClient: patreonClient,
                searchText: $searchText,
                filterStatus: $filterStatus,
                selectedPatrons: $selectedPatrons
            )
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button("CSV", action: {})
                        Button("Excel", action: {})
                        Button("PDF", action: {})
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    if !selectedPatrons.isEmpty {
                        Menu {
                            Button("Send Message", action: sendMessageToSelected)
                            Button("Export Selected", action: exportSelectedData)
                            Divider()
                            Button("Remove Selected", action: removeSelected)
                                .foregroundColor(.red)
                        } label: {
                            Label("Actions", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNewTierSheet) {
            NewTierSheet()
                .frame(minWidth: 500, minHeight: 600)
        }
    }

    private func sendMessageToSelected() {
        // Implement send message functionality
    }

    private func exportSelectedData() {
        // Implement export functionality
    }

    private func removeSelected() {
        // Implement remove functionality with confirmation
    }
}

// MARK: - Campaigns Sidebar

struct CampaignsSidebar: View {
    let patreonClient: PatreonClient
    @Binding var selectedCampaign: Campaign?
    @State private var campaigns: [Campaign] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showNewCampaignSheet = false

    var body: some View {
        List(selection: $selectedCampaign) {
            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if let error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Error loading campaigns")
                                .font(.caption)
                            Text(error.localizedDescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Retry") {
                            Task {
                                await loadCampaigns()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(campaigns) { campaign in
                        CampaignRow(campaign: campaign)
                            .tag(campaign)
                            .contextMenu {
                                Button("Edit") {}
                                Button("Duplicate") {}
                                Divider()
                                Button("Archive", role: .destructive) {}
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Campaigns")
                    Spacer()
                    Button(action: { showNewCampaignSheet = true }) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .task {
            await loadCampaigns()
        }
        .sheet(isPresented: $showNewCampaignSheet) {
            Text("New Campaign")
                .frame(width: 400, height: 300)
        }
    }

    private func loadCampaigns() async {
        isLoading = true
        error = nil
        do {
            let response = try await patreonClient.getCampaigns()
            let dateFormatter = ISO8601DateFormatter()
            campaigns = response.data.map { campaignData in
                // Create a dictionary of tier data from included array
                let tierDataDict = Dictionary(
                    uniqueKeysWithValues: response.included
                        .filter { $0.type == "tier" }
                        .map { ($0.id, $0) }
                )
                // Map tier IDs to PatronTier objects
                let tiers = campaignData.relationships.tiers.data.compactMap { tierRelation -> PatronTier? in
                    guard let tierData = tierDataDict[tierRelation.id] else { return nil }
                    // Extract tier attributes
                    let attributes = tierData.attributes
                    guard let title = attributes["title"]?.value as? String,
                          let amountCents = attributes["amount_cents"]?.value as? Int,
                          let description = attributes["description"]?.value as? String,
                          let patronCount = attributes["patron_count"]?.value as? Int
                    else {
                        return nil
                    }

                    // Convert amount from cents to dollars
                    let priceInDollars = Double(amountCents) / 100.0

                    // Extract benefits from description
                    let benefits = description
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    return PatronTier(
                        id: tierRelation.id,
                        name: title,
                        price: priceInDollars,
                        benefits: benefits,
                        patronCount: patronCount,
                        color: .blue,
                        description: description
                    )
                }
                return Campaign(
                    id: campaignData.id,
                    createdAt: dateFormatter.date(from: campaignData.attributes.created_at) ?? Date(),
                    creationName: campaignData.attributes.creation_name ?? "",
                    isMonthly: campaignData.attributes.is_monthly,
                    isNSFW: campaignData.attributes.is_nsfw,
                    patronCount: campaignData.attributes.patron_count,
                    publishedAt: campaignData.attributes.published_at.flatMap { dateFormatter.date(from: $0) },
                    summary: campaignData.attributes.summary,
                    tiers: tiers
                )
            }

            // Auto-select first campaign if none selected
            if selectedCampaign == nil, !campaigns.isEmpty {
                selectedCampaign = campaigns.first
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

struct CampaignRow: View {
    let campaign: Campaign

    var body: some View {
        HStack {
            Circle()
                .fill(campaign.isMonthly ? Color.blue : Color.green)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(campaign.creationName.isEmpty ? "Your Campaign" : campaign.creationName)
                    .fontWeight(.medium)

                HStack {
                    Text("\(campaign.patronCount) patrons")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if campaign.tiers.count > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(campaign.tiers.count) tiers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if campaign.isNSFW {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text(campaign.isMonthly ? "Monthly" : "Per Creation")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Tiers Sidebar

struct TiersSidebar: View {
    @Binding var selectedCampaign: Campaign?
    @Binding var selectedTier: PatronTier?
    @Binding var showNewTierSheet: Bool
    @Binding var isEditingMode: Bool

    var body: some View {
        List(selection: $selectedTier) {
            Section {
                ForEach(selectedCampaign?.tiers ?? []) { tier in
                    TierRowView(tier: tier, isEditing: isEditingMode)
                        .contextMenu {
                            Button("Edit Tier") { /* Implementation */ }
                            Button("Duplicate") { /* Implementation */ }
                            Divider()
                            Button("Delete", role: .destructive) { /* Implementation */ }
                        }
                }
                .onMove { _, _ in
                    // Handle reordering
                }
            } header: {
                HStack {
                    Text("Tiers")
                    Spacer()
                    HStack(spacing: 2) {
                        Button(action: { showNewTierSheet = true }) {
                            Image(systemName: "plus")
                                .font(.caption)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

// MARK: - Patron List View

struct PatronListView: View {
    let patreonClient: PatreonClient
    @Binding var searchText: String
    @Binding var filterStatus: PatronStatus?
    @Binding var selectedPatrons: Set<Patron>
    @State private var isLoading = false
    @State private var error: Error?
    @State private var patrons: [Patron] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search patrons...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)

                Picker("Status", selection: $filterStatus) {
                    Text("All").tag(nil as PatronStatus?)
                    ForEach(PatronStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status as PatronStatus?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding()

            Divider()

            Table(patrons) {
                TableColumn("Name") { patron in
                    Text(patron.name)
                }
                TableColumn("Email") { patron in
                    Text(patron.email ?? "N/A")
                }
                TableColumn("Status") { patron in
                    Text(patron.status.rawValue)
                }
                TableColumn("Amount") { patron in
                    Text("$\(patron.tierAmount, specifier: "%.2f")")
                }
            }
        }
        .task {
            await loadPatrons()
        }
    }

    private func loadPatrons() async {
        if isLoading { return }
        isLoading = true
        error = nil
        do {
            patrons = try await patreonClient.getPatrons()
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

// MARK: - Supporting Views

struct PatronNameCell: View {
    let patron: Patron

    var body: some View {
        HStack {
            Circle()
                .frame(width: 28, height: 28)
                .overlay(
                    Text(patron.name)
                        .foregroundColor(.white)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                )

            VStack(alignment: .leading) {
                Text(patron.name)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadgeView: View {
    let status: PatronStatus

    var statusColor: Color {
        switch status {
        case .active: .green
        case .inactive: .gray
        case .pending: .orange
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }
}

// MARK: - New Tier Sheet

struct NewTierSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var tierName = ""
    @State private var tierPrice = ""
    @State private var tierDescription = ""
    @State private var benefits: [String] = [""]
    @State private var selectedColor: Color = .blue
    @State private var isOneTime = false
    @State private var currentStep = 0
    @State private var showingImagePicker = false
    @State private var tierImage: NSImage?

    private let predefinedColors: [Color] = [
        .blue, .purple, .pink, .red, .orange,
        .yellow, .green, .mint, .teal, .cyan,
    ]

    var isValidTier: Bool {
        !tierName.isEmpty &&
            !tierPrice.isEmpty &&
            Double(tierPrice) != nil &&
            !benefits.filter { !$0.isEmpty }.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(currentStep == 0 ? "Create New Tier" : "Configure Benefits")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            // Content
            TabView(selection: $currentStep) {
                // Basic Info View
                basicInfoView
                    .tag(0)

                // Benefits View
                benefitsView
                    .tag(1)
            }
            .tabViewStyle(.automatic)

            // Footer
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }

                Spacer()

                Button(currentStep == 0 ? "Next" : "Create") {
                    if currentStep == 0 {
                        withAnimation {
                            currentStep += 1
                        }
                    } else {
                        createTier()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidTier)
            }
            .padding()
        }
        .frame(width: 600)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var basicInfoView: some View {
        Form {
            Section {
                TextField("Tier Name", text: $tierName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("$")
                    TextField("Price", text: $tierPrice)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("One-time payment", isOn: $isOneTime)

                TextEditor(text: $tierDescription)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } header: {
                Text("Basic Information")
            }

            Section {
                HStack {
                    if let image = tierImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            )
                    }

                    VStack(alignment: .leading) {
                        Button("Choose Image") {
                            showingImagePicker = true
                        }

                        Text("Recommended size: 300x300")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5)) {
                    ForEach(predefinedColors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
            } header: {
                Text("Appearance")
            }
        }
        .padding()
        .sheet(isPresented: $showingImagePicker) {
            // Image picker view would go here
        }
    }

    private var benefitsView: some View {
        Form {
            Section {
                ForEach(benefits.indices, id: \.self) { index in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(selectedColor)

                        TextField("Describe this benefit", text: $benefits[index])
                            .textFieldStyle(.roundedBorder)

                        if benefits.count > 1 {
                            Button(action: { removeBenefit(at: index) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: addBenefit) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Benefit")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            } header: {
                Text("Tier Benefits")
            } footer: {
                Text("Describe what patrons will receive at this tier")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func addBenefit() {
        benefits.append("")
    }

    private func removeBenefit(at index: Int) {
        benefits.remove(at: index)
    }

    private func createTier() {
        // Create new tier logic
        dismiss()
    }
}

// MARK: - Tier Row View

struct TierRowView: View {
    let tier: PatronTier
    let isEditing: Bool

    var body: some View {
        HStack {
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
            }

            Circle()
                .fill(tier.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tier.name)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("\(tier.patronCount) patrons")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !tier.benefits.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(tier.benefits.count) benefits")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text(tier.price.formatted(.currency(code: "USD")))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") {}
            Button("Duplicate") {}
            Divider()
            Button("Archive", role: .destructive) {}
        }
    }
}

enum PatronStatus: String, CaseIterable {
    case active = "Active"
    case inactive = "Inactive"
    case pending = "Pending"
}

struct PatronTier: Identifiable, Hashable {
    let id: String
    var name: String
    var price: Double
    var benefits: [String]
    var patronCount: Int
    var color: Color
    var description: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PatronTier, rhs: PatronTier) -> Bool {
        lhs.id == rhs.id
    }
}
