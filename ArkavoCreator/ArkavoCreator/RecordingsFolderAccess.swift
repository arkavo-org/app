import AppKit

enum RecordingsFolderAccess {
    private static let bookmarkKey = "recordingsFolderBookmark"

    /// Returns the bookmarked folder URL if available, nil if user needs to choose
    static func getBookmarkedFolder() -> URL? {
        return try? loadBookmarkedURL()
    }

    /// Check if a folder has been selected
    static var hasFolderSelected: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Shows folder picker and stores bookmark. Must be called on main thread.
    @MainActor
    static func chooseRecordingsFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Recordings Folder"
        panel.message = "Select the folder where Creator will read/write recordings (recommended: Documents/Recordings)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        // Start in user's Documents
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        let response = await panel.begin()
        guard response == .OK, let selected = panel.url else {
            return nil
        }

        do {
            try storeBookmark(for: selected)
            return selected
        } catch {
            print("⚠️ Failed to store bookmark: \(error)")
            return nil
        }
    }

    static func withScopedAccess<T>(_ folderURL: URL, _ body: () throws -> T) throws -> T {
        guard folderURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }
        return try body()
    }

    private static func storeBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private static func loadBookmarkedURL() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try storeBookmark(for: url)
        }
        return url
    }
}
