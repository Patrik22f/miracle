import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let settings = AppSettings()
    private let monitor = PromptMonitor()
    private var statusItem: NSStatusItem?
    private let badge = StatusBadgeView(frame: NSRect(x: 23, y: 14, width: 6, height: 6))
    private let popover = NSPopover()
    private var panel: NSPanel?
    private var helpfulPanel: RecommendationPanel?
    private var setupWindow: NSWindow?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: 34)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Preflight")
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        badge.isHidden = true
        item.button?.addSubview(badge)
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
        model.presentationChanged = { [weak self] in self?.refreshPresentation() }
        settings.permissionGranted = AXIsProcessTrusted()
        monitor.isEnabled = { [weak self] in
            guard let self else { return false }
            return self.settings.completedOnboarding && self.settings.automatic && !self.model.demoMode
                && self.setupWindow?.isVisible != true && !self.popover.isShown && self.panel?.isVisible != true
        }
        monitor.onPermission = { [weak self] granted in
            guard let self else { return }
            self.settings.permissionGranted = granted
            if !granted { self.model.receive(nil) }
        }
        monitor.onSnapshot = { [weak self] in self?.model.receive($0) }
        monitor.onStatus = { [weak self] in self?.settings.monitoringStatus = $0 }
        monitor.start()
        hotKey = GlobalHotKey { [weak self] in
            self?.model.capture()
            self?.openPanel()
        }
        do { try hotKey?.start() } catch { model.message = error.localizedDescription }
        refreshPresentation()
        if ProcessInfo.processInfo.arguments.contains("--demo") { demo() }
        else if !settings.completedOnboarding { showSetup() }
    }

    private func reviewView(close: @escaping () -> Void) -> OverlayView {
        OverlayView(model: model, close: close, settings: settings, openSettings: { [weak self] in self?.showSetup() })
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "Preflight")
        application.submenu = applicationMenu
        let settingsItem = add("Settings…", action: #selector(showSetup), to: applicationMenu)
        settingsItem.keyEquivalent = ","
        applicationMenu.addItem(.separator())
        let quitItem = add("Quit Preflight", action: #selector(quit), to: applicationMenu)
        quitItem.keyEquivalent = "q"
        mainMenu.addItem(application)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if !settings.completedOnboarding { showSetup(); return }
        if popover.isShown { popover.performClose(nil); return }
        helpfulPanel?.orderOut(nil)
        guard let button = statusItem?.button else { return }
        let controller = NSHostingController(rootView: reviewView { [weak self] in self?.popover.performClose(nil) })
        let height = min(700, (button.window?.screen?.visibleFrame.height ?? 800) - 40)
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 560, height: height)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.markRead()
    }

    private func showMenu() {
        let menu = NSMenu()
        add("Open Preflight", action: #selector(openPanel), to: menu)
        menu.addItem(.separator())
        let stealth = add("Stealth", action: #selector(chooseStealth), to: menu)
        stealth.state = settings.mode == .stealth ? .on : .off
        let helpful = add("Helpful", action: #selector(chooseHelpful), to: menu)
        helpful.state = settings.mode == .helpful ? .on : .off
        add(settings.automatic ? "Pause automatic recommendations" : "Resume automatic recommendations", action: #selector(toggleAutomatic), to: menu)
        add("Settings…", action: #selector(showSetup), to: menu)
        add("Try demo", action: #selector(demo), to: menu)
        menu.addItem(.separator())
        add("Quit Preflight", action: #selector(quit), to: menu)
        guard let button = statusItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc func openPanel() {
        popover.performClose(nil)
        helpfulPanel?.orderOut(nil)
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 730), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Preflight"
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentMinSize = NSSize(width: 510, height: 560)
            window.delegate = self
            window.center()
            panel = window
        }
        panel?.contentView = NSHostingView(rootView: reviewView { [weak self] in self?.closePanel() })
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        model.markRead()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openPanel() }
        return true
    }

    @objc private func showSetup() {
        popover.performClose(nil)
        helpfulPanel?.orderOut(nil)
        model.receive(nil)
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 590), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = settings.completedOnboarding ? "Preflight Settings" : "Welcome to Preflight"
            window.delegate = self
            setupWindow = window
        }
        setupWindow?.contentView = NSHostingView(rootView: SetupView(settings: settings, onboarding: !settings.completedOnboarding, complete: { [weak self] in
            guard let self else { return }
            self.settings.completedOnboarding = true
            self.setupWindow?.orderOut(nil)
            self.setupWindow = nil
            self.refreshPresentation()
        }, changed: { [weak self] in self?.settingsChanged() }))
        setupWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    private func settingsChanged() {
        if !settings.automatic { model.receive(nil) }
        refreshPresentation()
    }

    private func refreshPresentation() {
        if model.hasUnreadRecommendation && (popover.isShown || panel?.isVisible == true) {
            model.markRead()
            return
        }
        badge.isHidden = !model.hasUnreadRecommendation
        badge.color = model.hasError ? .systemOrange : .controlAccentColor
        let state = model.isLoading ? "Analyzing prompt" : model.hasUnreadRecommendation ? (model.hasError ? "Analysis needs attention" : "New recommendations") : "Ready"
        statusItem?.button?.toolTip = "Preflight · \(settings.mode.title) · \(state)"
        statusItem?.button?.setAccessibilityLabel("Preflight, \(settings.mode.title), \(state)")
        guard settings.mode == .helpful, !model.helpfulDismissed, !popover.isShown,
              panel?.isVisible != true, setupWindow?.isVisible != true,
              model.result != nil || model.hasError,
              let snapshot = model.activeSnapshot,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.processID,
              let bounds = snapshot.bounds, let primary = NSScreen.screens.first else {
            helpfulPanel?.orderOut(nil)
            return
        }
        let anchor = PanelPlacement.appKitRect(bounds, primaryScreenHeight: primary.frame.height)
        guard let screen = NSScreen.screens.max(by: { $0.frame.intersection(anchor).area < $1.frame.intersection(anchor).area }),
              screen.frame.intersects(anchor) else { helpfulPanel?.orderOut(nil); return }
        if helpfulPanel == nil {
            let window = RecommendationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Preflight Recommendations"
            window.isFloatingPanel = true
            window.level = .floating
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: HelpfulView(model: model, review: { [weak self] in self?.openPanel() }, dismiss: { [weak self] in self?.model.dismissHelpful() }))
            helpfulPanel = window
        }
        let height = model.hasError ? 220.0 : min(430, 225 + Double(model.result?.skills.count ?? 0) * 78)
        helpfulPanel?.setFrame(PanelPlacement.frame(above: anchor, size: CGSize(width: 420, height: height), visibleFrame: screen.visibleFrame.insetBy(dx: 8, dy: 8)), display: true)
        // orderFront leaves the host's prompt as the key input. Never activate here.
        helpfulPanel?.orderFrontRegardless()
    }

    func closePanel() { model.cancel(); panel?.orderOut(nil); model.dismissHelpful() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { model.cancel(); model.dismissHelpful() }
    }
    func popoverDidClose(_ notification: Notification) { model.dismissHelpful() }
    @objc private func chooseStealth() { settings.mode = .stealth; settingsChanged() }
    @objc private func chooseHelpful() { settings.mode = .helpful; settingsChanged() }
    @objc private func toggleAutomatic() { settings.automatic.toggle(); settingsChanged() }
    @objc func demo() { model.loadDemo(); openPanel() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop(); hotKey?.stop(); model.cancel() }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

private final class StatusBadgeView: NSView {
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
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
