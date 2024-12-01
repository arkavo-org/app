import SwiftUI
import WebKit

// MARK: - WebView Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    let parent: WebViewRepresentable

    init(_ parent: WebViewRepresentable) {
        self.parent = parent
    }

    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            if url.scheme == "arkavocreator" {
                parent.handleCallback(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        parent.isLoading = true
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        parent.isLoading = false
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        parent.isLoading = false
        parent.error = error
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        parent.isLoading = false
        parent.error = error
    }
}

// MARK: - WebView Configuration

enum WebViewConfiguration {
    @MainActor static func create() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Add any additional configuration here
        return config
    }
}

// MARK: - WebView Representable

struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let handleCallback: (URL) -> Void
    @Binding var isLoading: Bool
    @Binding var error: Error?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WebViewConfiguration.create())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // Handle any updates if needed
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }
}

// MARK: - WebView Container

struct WebView: View {
    let url: URL
    let handleCallback: (URL) -> Void
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        ZStack {
            WebViewRepresentable(
                url: url,
                handleCallback: handleCallback,
                isLoading: $isLoading,
                error: $error
            )

            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }

            if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red)

                    Text("Loading Error")
                        .font(.headline)

                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        self.error = nil
                        if let webView = NSApp.keyWindow?.contentView?.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
                            webView.load(URLRequest(url: url))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
            }
        }
    }
}

// MARK: - WebView Window

class WebViewWindow: NSWindow {
    init(url: URL, handleCallback: @escaping (URL) -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Authentication"
        isReleasedWhenClosed = false
        center()

        contentView = NSHostingView(
            rootView: WebView(url: url, handleCallback: handleCallback)
                .frame(width: 800, height: 600)
        )
    }
}

// MARK: - WebView Presenter

class WebViewPresenter: ObservableObject {
    private var window: WebViewWindow?

    @MainActor func present(url: URL, handleCallback: @escaping (URL) -> Void) {
        window = WebViewWindow(url: url, handleCallback: handleCallback)
        window?.makeKeyAndOrderFront(nil)
    }

    @MainActor func dismiss() {
        window?.close()
        window = nil
    }
}
