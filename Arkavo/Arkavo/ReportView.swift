import SwiftUI

struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSeverities: [ReportReason: ContentRatingLevel] = [:]
    @State private var showingConfirmation = false
    @State private var additionalDetails = ""
    @State private var includeContentSnapshot = true
    @State private var showingBlockConfirmation = false
    @State private var blockUser = false

    let content: Any
    let contentId: String
    let contributor: Contributor?

    var body: some View {
        NavigationStack {
            List {
                ForEach(ReportReason.allCases, id: \.self) { reason in
                    Section {
                        DisclosureGroup {
                            ForEach(ContentRatingLevel.allCases, id: \.self) { severity in
                                Button {
                                    if selectedSeverities[reason] == severity {
                                        selectedSeverities.removeValue(forKey: reason)
                                    } else {
                                        selectedSeverities[reason] = severity
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Label {
                                                Text(severity.title)
                                                    .fontWeight(.medium)
                                            } icon: {
                                                Image(systemName: severity.icon)
                                                    .foregroundColor(colorForRating(severity))
                                            }
                                            Spacer()

                                            if selectedSeverities[reason] == severity {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.blue)
                                            }
                                        }

                                        Text(severity.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reason.rawValue)
                                        .font(.headline)
                                    Text(reason.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: reason.icon)
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundColor(colorForReason(reason))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Block user from interacting with you", isOn: $blockUser)
                        .onChange(of: blockUser) { _, newValue in
                            if newValue {
                                showingBlockConfirmation = true
                            }
                        }
                }

                Section {
                    Text("Reports are reviewed within 24 hours. Severe violations may be acted upon sooner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submitReport()
                    } label: {
                        Text("Submit")
                            .bold()
                    }
                    .disabled(selectedSeverities.isEmpty)
                }
            }
        }
        .alert("Block User?", isPresented: $showingBlockConfirmation) {
            Button("Cancel", role: .cancel) {
                blockUser = false
            }
            Button("Block User", role: .destructive) {
                blockUser = true
            }
        } message: {
            Text("Blocking this user will prevent them from interacting with your content or messaging you. You can unblock them later in settings.")
        }
        .alert("Report Submitted", isPresented: $showingConfirmation) {
            Button("Done", role: .cancel) {
                dismiss()
            }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Thank you for helping keep our community safe.")
                Text("• Your report will be reviewed within 24 hours")
                Text("• You will be notified of the outcome")
                if blockUser {
                    Text("• This user has been blocked")
                }
            }
        }
    }

    private func colorForRating(_ rating: ContentRatingLevel) -> Color {
        switch rating.colorName {
        case "gray": .gray
        case "orange": .orange
        case "red": .red
        default: .black
        }
    }

    private func colorForReason(_ reason: ReportReason) -> Color {
        switch reason.colorName {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "purple": .purple
        case "pink": .pink
        case "indigo": .indigo
        default: .black
        }
    }

    private func submitReport() {
        Task {
            do {
                // Retrieve the account profile
                guard let accountProfile = try await PersistenceController.shared.getOrCreateAccount().profile,
                      let creatorPublicID = contributor?.profilePublicID
                else {
                    // If the profile or public ID is nil, return early
                    return
                }
                let accountProfilePublicID = accountProfile.publicID
                // Create the report object
                let report = ContentReport(
                    reasons: selectedSeverities,
                    includeSnapshot: includeContentSnapshot,
                    blockUser: blockUser,
                    timestamp: Date(),
                    contentId: contentId,
                    reporterId: accountProfilePublicID.base58EncodedString
                )

                // Handle blocking the user if enabled
                if blockUser {
                    let blockedProfile = BlockedProfile(
                        blockedPublicID: creatorPublicID,
                        report: report
                    )
                    try await PersistenceController.shared.saveBlockedProfile(blockedProfile)
                }

                // Submit the report to the backend
                try await submitReportToBackend(report)

                // Show confirmation message
                showingConfirmation = true
            } catch {
                // Handle error (optional: show an error message to the user)
                print("Failed to submit the report: \(error.localizedDescription)")
            }
        }
    }

    private func submitReportToBackend(_: ContentReport) async throws {
        // Implementation for submitting report to backend
    }
}

struct ContentReportSelection: Identifiable, Hashable {
    let reason: ReportReason
    let severity: ContentRatingLevel

    var id: String { "\(reason)_\(severity.rawValue)" }

    static func == (lhs: ContentReportSelection, rhs: ContentReportSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
