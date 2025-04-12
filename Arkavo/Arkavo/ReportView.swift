import ArkavoSocial
import FlatBuffers
import SwiftUI

struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReportViewModel
    @State private var selectedSeverities: [ReportReason: ContentRatingLevel] = [:]
    @State private var showingConfirmation = false
    @State private var additionalDetails = ""
    @State private var includeContentSnapshot = true
    @State private var showingBlockConfirmation = false
    @State private var blockUser = false
    @State private var submissionError: String? = nil // For showing errors

    let content: Any
    let contentId: String
    let contributor: Contributor?

    init(content: Any, contentId: String, contributor: Contributor?) {
        self.content = content
        self.contentId = contentId
        self.contributor = contributor
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeViewModel())
    }

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

                // Display submission error if any
                if let error = submissionError {
                    Section {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
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
                submissionError = nil // Clear previous errors
                let accountProfilePublicID = viewModel.profile.publicID

                // Create the report object
                var report = ContentReport(
                    reasons: selectedSeverities,
                    includeSnapshot: includeContentSnapshot,
                    blockUser: blockUser,
                    timestamp: Date(),
                    contentId: contentId,
                    reporterId: accountProfilePublicID.base58EncodedString
                )

                // Handle blocking the user if enabled
                if blockUser,
                   let creatorPublicID = contributor?.profilePublicID
                {
                    // Set optional blockedPublicID for the report serialization
                    report.blockedPublicID = creatorPublicID.base58EncodedString

                    // Fetch the Profile to block
                    guard let profileToBlock = try await PersistenceController.shared.fetchProfile(withPublicID: creatorPublicID) else {
                        print("ReportView Error: Could not find profile with publicID \(creatorPublicID.base58EncodedString) to block.")
                        // Optionally set an error state for the UI
                        submissionError = "Could not find the user profile to block."
                        // Decide if you want to proceed with submitting the report without blocking
                        // For now, we'll stop the submission process if blocking fails
                        return
                    }

                    // Create BlockedProfile with the fetched Profile object
                    let blockedProfileEntry = BlockedProfile(
                        blockedProfile: profileToBlock,
                        report: report
                    )
                    try await PersistenceController.shared.saveBlockedProfile(blockedProfileEntry)
                    print("ReportView: Successfully saved blocked profile entry for \(creatorPublicID.base58EncodedString)")
                }

                // Submit report using ViewModel
                try await viewModel.submitReport(report)

                // Show confirmation message
                showingConfirmation = true
            } catch {
                print("Failed to submit the report or block user: \(error.localizedDescription)")
                submissionError = "Failed to submit report: \(error.localizedDescription)"
            }
        }
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

@MainActor
class ReportViewModel: ViewModel {
    let client: ArkavoClient
    let account: Account
    let profile: Profile

    required init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
    }

    func submitReport(_ report: ContentReport) async throws {
        // Create FlatBuffer builder
        var builder = FlatBufferBuilder()

        // Serialize report to JSON data
        let encoder = JSONEncoder()
        let reportData = try encoder.encode(report)

        // Create target ID from report ID and optional blocked ID
        let targetId = "\(report.contentId)\(report.blockedPublicID ?? "")"

        // Create vectors for target ID and payload
        let targetIdVector = builder.createVector(bytes: Data(targetId.utf8))
        let payloadVector = builder.createVector(bytes: reportData)

        // Create CacheEvent
        let cacheEvent = Arkavo_CacheEvent.createCacheEvent(
            &builder,
            targetIdVectorOffset: targetIdVector,
            targetPayloadVectorOffset: payloadVector,
            ttl: 0, // No TTL for reports
            oneTimeAccess: false
        )

        // Create Event
        let event = Arkavo_Event.createEvent(
            &builder,
            action: .store,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            status: .preparing,
            dataType: .cacheevent,
            dataOffset: cacheEvent
        )

        builder.finish(offset: event)
        let eventData = builder.data

        // Send event through client
        try await client.sendNATSEvent(eventData)
    }
}
