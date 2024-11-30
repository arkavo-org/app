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
    @State private var searchText = ""
    @State private var showNewTierSheet = false
    @State private var sortOrder = [KeyPathComparator(\Patron.name)]
    @State private var filterStatus: PatronStatus?
    @State private var selectedPatrons: Set<String> = []
    @State private var showingExportMenu = false
    @State private var isEditingMode = false
    // Environment values for system appearance
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Left side - Tiers
            TiersSidebar(
                selectedTier: $selectedTier,
                showNewTierSheet: $showNewTierSheet,
                isEditingMode: $isEditingMode
            )
            .frame(minWidth: 250, maxWidth: 300)

            // Divider between sidebar and content
            Divider()

            // Right side - Patron list
            PatronListView(
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

// MARK: - Tiers Sidebar

struct TiersSidebar: View {
    @Binding var selectedTier: PatronTier?
    @Binding var showNewTierSheet: Bool
    @Binding var isEditingMode: Bool

    var body: some View {
        List(selection: $selectedTier) {
            Section {
                ForEach(sampleTiers) { tier in
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
                    Button(action: { isEditingMode.toggle() }) {
                        Text(isEditingMode ? "Done" : "Edit")
                    }
                }
            }
        }
//        .toolbar {
//            ToolbarItem(placement: .primaryAction) {
//                Button(action: { showNewTierSheet.toggle() }) {
//                    Label("Add Tier", systemImage: "plus")
//                }
//            }
//        }
    }
}

// MARK: - Patron List View

struct PatronListView: View {
    @Binding var searchText: String
    @State private var sortOrder: [KeyPathComparator<Patron>] = [
        KeyPathComparator(\Patron.name),
        KeyPathComparator(\Patron.joinDate),
    ]
    @Binding var filterStatus: PatronStatus?
    @Binding var selectedPatrons: Set<String>
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

            Table(selection: $selectedPatrons, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { patron in
                    PatronNameCell(patron: patron)
                }
//                TableColumn("Status", value: \.status.rawValue) { patron in
//                    StatusBadgeView(status: patron.status)
//                }
//                TableColumn("Tier", value: \.tier.name)
//                TableColumn("Join Date", value: \.joinDate) { patron in
//                    Text(patron.joinDate.formatted(date: .abbreviated, time: .omitted))
//                }
//                TableColumn("Last Payment", value: \.lastPayment) { patron in
//                    Text(patron.lastPayment.formatted(date: .abbreviated, time: .omitted))
//                }
//                TableColumn("Total", value: \.totalContribution) { patron in
//                    Text(patron.totalContribution.formatted(.currency(code: "USD")))
//                }
            } rows: {
                ForEach(patrons) { patron in
                    TableRow(patron)
                }
            }
        }
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

                    if tier.isOneTime {
                        Text("One-time")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
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
    let id: UUID
    var name: String
    var price: Double
    var benefits: [String]
    var patronCount: Int
    var color: Color
    var description: String
    var isOneTime: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PatronTier, rhs: PatronTier) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sample Data

let sampleTiers = [
    PatronTier(id: UUID(), name: "Bronze", price: 5.0, benefits: ["Basic Access"], patronCount: 125, color: .brown, description: "Basic tier with essential features", isOneTime: false),
    PatronTier(id: UUID(), name: "Silver", price: 10.0, benefits: ["Basic Access", "Early Access"], patronCount: 75, color: .gray, description: "Enhanced access with early content", isOneTime: false),
    PatronTier(id: UUID(), name: "Gold", price: 25.0, benefits: ["Basic Access", "Early Access", "Exclusive Content"], patronCount: 30, color: .yellow, description: "Premium tier with all features", isOneTime: false),
]
