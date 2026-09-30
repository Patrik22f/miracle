import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = AppModel(preferences: .standard)
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hotKey: GlobalHotKey?
    private var captureTask: Task<Void, Never>?
    private var liveCaptureItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Preflight")
        let menu = NSMenu()
        add("Open Preflight", action: #selector(openPanel), to: menu)
        add("Try demo", action: #selector(demo), to: menu)
        add("Enable Accessibility…", action: #selector(permission), to: menu)
        let liveItem = NSMenuItem(title: "Live capture", action: #selector(toggleLiveCapture), keyEquivalent: "")
        liveItem.target = self
        menu.addItem(liveItem)
        liveCaptureItem = liveItem
        menu.delegate = self
        menu.addItem(.separator())
        add("Quit Preflight", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
        hotKey = GlobalHotKey { [weak self] in
            guard let self else { return }
            self.captureTask?.cancel()
            self.captureTask = Task { [weak self] in
                guard let self else { return }
                await self.model.capture() // Read before our overlay takes focus.
                guard !Task.isCancelled else { return }
                self.openPanel()
            }
        }
        do { try hotKey?.start() } catch { model.message = error.localizedDescription }
        openPanel()
        if ProcessInfo.processInfo.arguments.contains("--demo") { demo() }
        model.startCapture()
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func configureMainMenu() {
        // AppKit-hosted SwiftUI needs a responder-chain Edit menu for standard
        // TextEditor shortcuts (paste, undo, select all), even in a menu-bar app.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Preflight")
        let quit = applicationMenu.addItem(withTitle: "Quit Preflight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
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
    @objc func permission() { AccessibilityPermission.request() }
    @objc func toggleLiveCapture() { model.setLiveCaptureEnabled(!model.liveCaptureEnabled) }
    func menuWillOpen(_ menu: NSMenu) {
        liveCaptureItem?.state = model.liveCaptureEnabled && !model.demoMode ? .on : .off
        liveCaptureItem?.isEnabled = !model.demoMode
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        captureTask?.cancel()
        hotKey?.stop()
        model.stopCapture()
        model.cancel()
    }
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
