import AppKit
import WebKit

@MainActor
final class DemoWorkspace: NSObject, WKNavigationDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let pageURL: URL

    init(resources: Bundle = AnalyzeResponse.resources) throws {
        guard let pageURL = resources.url(forResource: "index", withExtension: "html", subdirectory: "Demo") else {
            throw ClientError.message("The demo website is missing. Rebuild Miracle.")
        }
        self.pageURL = pageURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Shopfront"
        window.minSize = NSSize(width: 580, height: 560)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = webView
        window.center()
        webView.navigationDelegate = self
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url == pageURL ? .allow : .cancel
    }
}
