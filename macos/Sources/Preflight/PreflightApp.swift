import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Preflight")
        let menu = NSMenu()
        add("Open Preflight", action: #selector(openPanel), to: menu)
        add("Try demo", action: #selector(demo), to: menu)
        add("Enable Accessibility…", action: #selector(permission), to: menu)
        menu.addItem(.separator())
        add("Quit Preflight", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        hotKey = GlobalHotKey { [weak self] in
            self?.model.capture() // Capture before our overlay takes focus.
            self?.openPanel()
        }
        do { try hotKey?.start() } catch { model.message = error.localizedDescription }
        openPanel()
        if ProcessInfo.processInfo.arguments.contains("--demo") { demo() }
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc func openPanel() {
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 730), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Preflight"
            window.level = .floating
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: OverlayView(model: model) { [weak self] in self?.closePanel() })
            window.delegate = self
            window.center()
            panel = window
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func closePanel() { model.cancel(); panel?.orderOut(nil) }
    func windowWillClose(_ notification: Notification) { model.cancel() }
    @objc func demo() { model.loadDemo(); openPanel() }
    @objc func permission() { FocusedText.requestPermission() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { hotKey?.stop(); model.cancel() }
}

@main
enum PreflightApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
