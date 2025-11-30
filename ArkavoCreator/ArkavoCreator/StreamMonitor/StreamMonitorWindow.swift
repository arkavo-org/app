import AppKit
import SwiftUI

/// A floating window for monitoring the stream output.
/// Shows the final composed frame exactly as viewers see it.
@MainActor
final class StreamMonitorWindow: NSObject {
    static let shared = StreamMonitorWindow()

    private var window: NSWindow?
    private let viewModel = StreamMonitorViewModel.shared

    @AppStorage("streamMonitor.alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("streamMonitor.windowFrame") private var savedFrameData: Data?

    // Notification to save frame before close
    private var willCloseObserver: Any?

    override private init() {
        super.init()
    }

    /// Shows the stream monitor window, creating it if needed.
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = StreamMonitorView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.contentView = hostingView
        newWindow.title = "Stream Monitor"
        newWindow.titlebarAppearsTransparent = false
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 400, height: 250)
        newWindow.contentMinSize = NSSize(width: 400, height: 250)

        // Restore saved frame or center on screen
        if let frameData = savedFrameData,
           let frameString = String(data: frameData, encoding: .utf8)
        {
            newWindow.setFrame(from: frameString)
        } else {
            // Default: center on main screen or secondary if available
            if let screens = NSScreen.screens.dropFirst().first {
                newWindow.center()
                newWindow.setFrameOrigin(NSPoint(
                    x: screens.frame.midX - newWindow.frame.width / 2,
                    y: screens.frame.midY - newWindow.frame.height / 2
                ))
            } else {
                newWindow.center()
            }
        }

        // Set window level based on preference
        newWindow.level = alwaysOnTop ? .floating : .normal

        // Observe window close to save frame
        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveWindowFrame()
            }
        }

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }

    /// Hides the stream monitor window.
    func hide() {
        saveWindowFrame()
        window?.close()
    }

    /// Toggles visibility of the stream monitor window.
    func toggle() {
        if let existing = window, existing.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Updates the window title based on stream state.
    func updateTitle(isLive: Bool) {
        window?.title = isLive ? "Stream Monitor - LIVE" : "Stream Monitor - Preview"
    }

    /// Sets the always-on-top preference.
    func setAlwaysOnTop(_ enabled: Bool) {
        alwaysOnTop = enabled
        window?.level = enabled ? .floating : .normal
    }

    /// Returns whether the window is currently visible.
    var isVisible: Bool {
        window?.isVisible ?? false
    }

    private func saveWindowFrame() {
        guard let window else { return }
        let frameString = window.frameDescriptor
        savedFrameData = frameString.data(using: .utf8)
    }
}
