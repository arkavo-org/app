import SwiftUI

struct ContentManagerView: View {
    @State private var searchText = ""
    @State private var selectedItems = Set<UUID>()
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedItems) {
                ForEach(sampleContent) { content in
                    ContentItemRow(content: content)
                        .tag(content.id)
                }
            }
            .navigationTitle("Content Manager")
            .searchable(text: $searchText, prompt: "Search content")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingImporter.toggle() }) {
                        Label("Import Content", systemImage: "plus")
                    }
                    .keyboardShortcut("i", modifiers: [.command])
                }

                if !selectedItems.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: {}) {
                            Label("Protect", systemImage: "lock.shield")
                        }
                        Button(action: {}) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}

struct ContentItemRow: View {
    let content: ContentItem
    @State private var showingMenu = false

    var body: some View {
        HStack(spacing: 12) {
            // Type Icon with proper SF Symbol
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.body)

                    HStack(spacing: 8) {
                        Text(content.type.rawValue)
                            .foregroundStyle(.secondary)

                        switch content.protectionStatus {
                        case let .protected(date):
                            Text("Protected \(date)")
                                .foregroundStyle(.secondary)
                        case .registering:
                            Label("Registering...", systemImage: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                        case .unprotected:
                            Label("Not Protected", systemImage: "lock.open")
                                .foregroundStyle(.secondary)
                        case .failed:
                            Label("Protection Failed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }

                        if !content.patronAccess.isEmpty {
                            Text("\(content.patronAccess.count) Tiers")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            } icon: {
                Image(systemName: content.type.icon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
            }

            Spacer()

            if content.views > 0 {
                VStack(alignment: .trailing) {
                    Text("\(content.views) views")
                    Text("\(content.engagement, specifier: "%.1f")% engagement")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Menu {
                Button("View Details") {}
                Button("Edit") {}

                if case .unprotected = content.protectionStatus {
                    Divider()
                    Button("Protect Content") {}
                }

                Divider()
                Button("Delete", role: .destructive) {}
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolVariant(.fill)
                    .contentTransition(.symbolEffect(.replace))
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

struct ProtectionConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var isRegistering = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Protect Content")
                .font(.title)

            if isRegistering {
                ProgressView("Registering with Arkavo Network...")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Registration will:")
                        .font(.headline)

                    Label("Create immutable record", systemImage: "checkmark.circle")
                    Label("Generate unique identifier", systemImage: "checkmark.circle")
                    Label("Enable patron distribution", systemImage: "checkmark.circle")
                }
            }

            HStack {
                Button("Cancel", action: { dismiss() })
                    .keyboardShortcut(.cancelAction)

                Button("Register Content") {
                    isRegistering = true
                    // Registration logic
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
    }
}

struct PatronAccessSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTiers: Set<UUID> = []

    var body: some View {
        VStack(spacing: 20) {
            Text("Set Patron Access")
                .font(.title)

//            List(sampleTiers, selection: $selectedTiers) { tier in
//                HStack {
//                    VStack(alignment: .leading) {
//                        Text(tier.name)
//                            .font(.headline)
//                        Text("\(tier.patronCount) patrons")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                    }
//
//                    Spacer()
//
//                    Text("$\(tier.price, specifier: "%.2f")/month")
//                        .foregroundStyle(.secondary)
//                }
//            }

            HStack {
                Button("Cancel", action: { dismiss() })
                    .keyboardShortcut(.cancelAction)

                Button("Confirm Access") {
                    // Distribution logic
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

// MARK: - Content Item Model

struct ContentItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let type: ContentType
    let createdDate: Date
    let lastModified: Date
    var protectionStatus: ProtectionStatus
    var patronAccess: [PatronTier]
    var views: Int
    var engagement: Double // percentage

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ContentItem, rhs: ContentItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supporting Types

enum ContentType: String {
    case blogPost = "Blog Post"
    case video = "Video"
    case audio = "Audio"
    case image = "Image"
    case document = "Document"

    var icon: String {
        switch self {
        case .blogPost: "doc.text"
        case .video: "video"
        case .audio: "waveform"
        case .image: "photo"
        case .document: "doc"
        }
    }
}

enum ProtectionStatus {
    case unprotected
    case registering
    case protected(Date)
    case failed(String)

    var icon: String {
        switch self {
        case .unprotected: "lock.open"
        case .registering: "arrow.clockwise"
        case .protected: "lock.shield"
        case .failed: "exclamationmark.triangle"
        }
    }

    var description: String {
        switch self {
        case .unprotected: "Not Protected"
        case .registering: "Registering..."
        case let .protected(date): "Protected on \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .failed(error): "Failed: \(error)"
        }
    }
}

// MARK: - Sample Content

let sampleContent: [ContentItem] = [
    ContentItem(
        id: UUID(),
        title: "Getting Started with SwiftUI",
        type: .blogPost,
        createdDate: Date().addingTimeInterval(-86400 * 2),
        lastModified: Date().addingTimeInterval(-3600 * 2),
        protectionStatus: .protected(Date().addingTimeInterval(-3600)),
        patronAccess: [],
        views: 156,
        engagement: 78.5
    ),
    ContentItem(
        id: UUID(),
        title: "Monthly Update Video",
        type: .video,
        createdDate: Date().addingTimeInterval(-86400),
        lastModified: Date().addingTimeInterval(-3600),
        protectionStatus: .unprotected,
        patronAccess: [],
        views: 0,
        engagement: 0
    ),
    ContentItem(
        id: UUID(),
        title: "Project Documentation",
        type: .document,
        createdDate: Date(),
        lastModified: Date(),
        protectionStatus: .registering,
        patronAccess: [],
        views: 0,
        engagement: 0
    ),
]

// MARK: - Content Row View

struct ContentRow: View {
    let content: ContentItem

    var body: some View {
        HStack(spacing: 16) {
            // Content Icon
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: content.type.icon)
                        .foregroundStyle(Color.accentColor)
                )

            // Content Info
            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label(content.type.rawValue, systemImage: content.type.icon)

                    Label(content.protectionStatus.description,
                          systemImage: content.protectionStatus.icon)

                    if !content.patronAccess.isEmpty {
                        Label("\(content.patronAccess.count) Tiers",
                              systemImage: "person.2.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats
            if content.views > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(content.views) views")
                        .font(.subheadline)

                    Text("\(content.engagement, specifier: "%.1f")% engagement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Actions Menu
            Menu {
                Button("View Details", action: {})
                Button("Edit", action: {})
                if case .unprotected = content.protectionStatus {
                    Button("Protect Content", action: {})
                }
                Button("Set Patron Access", action: {})
                Divider()
                Button("Delete", role: .destructive, action: {})
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolVariant(.fill)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}