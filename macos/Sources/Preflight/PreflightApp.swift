import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let model = AppModel(preferences: .standard)
    private let settings = AppSettings()
    private var statusItem: NSStatusItem?
    private let badge = StatusBadgeView(frame: NSRect(x: 23, y: 14, width: 6, height: 6))
    private let popover = NSPopover()
    private let catalog = ModelCatalog()
    private let installer = SkillInstallModel()
    private var settingsWindow: NSWindow?
    private var helpfulPanel: RecommendationPanel?
    private var setupWindow: NSWindow?

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
        model.permissionChanged = { [weak self] granted in self?.settings.permissionGranted = granted }
        synchronizeMonitoring()
        model.startCapture()
        Task { await catalog.refresh() }
        refreshPresentation()
        if !settings.completedOnboarding { showOnboarding() }
    }

    private func reviewView(close: @escaping () -> Void) -> OverlayView {
        OverlayView(model: model, close: close, settings: settings, catalog: catalog, installer: installer,
                    openSettings: { [weak self] in self?.showSettings() }, modeChanged: { [weak self] in self?.settingsChanged() })
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "Preflight")
        application.submenu = applicationMenu
        let settingsItem = add("Settings…", action: #selector(showSettings), to: applicationMenu)
        settingsItem.keyEquivalent = ","
        applicationMenu.addItem(.separator())
        let quitItem = add("Quit Preflight", action: #selector(quit), to: applicationMenu)
        quitItem.keyEquivalent = "q"
        mainMenu.addItem(application)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
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
        if !settings.completedOnboarding { showOnboarding(); return }
        if popover.isShown { popover.performClose(nil); return }
        showReview()
    }

    @objc private func showReview() {
        guard settings.completedOnboarding else { showOnboarding(); return }
        helpfulPanel?.orderOut(nil)
        guard let button = statusItem?.button else { return }
        let controller = NSHostingController(rootView: reviewView { [weak self] in self?.popover.performClose(nil) })
        let height = min(740, (button.window?.screen?.visibleFrame.height ?? 800) - 40)
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 560, height: height)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        model.markRead()
    }

    private func showMenu() {
        let menu = NSMenu()
        add("Open Preflight", action: #selector(showReview), to: menu)
        menu.addItem(.separator())
        let modeItem = NSMenuItem(title: "Display mode", action: nil, keyEquivalent: "")
        let modes = NSMenu(title: "Display mode")
        modeItem.submenu = modes
        menu.addItem(modeItem)
        let stealth = add("Stealth", action: #selector(chooseStealth), to: modes)
        stealth.state = settings.mode == .stealth ? .on : .off
        let helpful = add("Helpful", action: #selector(chooseHelpful), to: modes)
        helpful.state = settings.mode == .helpful ? .on : .off
        add(settings.automatic ? "Pause automatic recommendations" : "Resume automatic recommendations", action: #selector(toggleAutomatic), to: menu)
        let capture = add("Live capture", action: #selector(toggleLiveCapture), to: menu)
        capture.state = model.liveCaptureEnabled && !model.demoMode ? .on : .off
        capture.isEnabled = !model.demoMode
        add("Enable Accessibility…", action: #selector(permission), to: menu)
        add("Settings…", action: #selector(showSettings), to: menu)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    private func showOnboarding() {
        guard !settings.completedOnboarding else { return }
        if let setupWindow { setupWindow.makeKeyAndOrderFront(nil); return }
        model.setCaptureSuspended(true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Preflight"
        window.delegate = self
        setupWindow = window
        window.contentView = NSHostingView(rootView: SetupView(settings: settings, complete: { [weak self] in
            guard let self else { return }
            self.settings.completedOnboarding = true
            self.setupWindow?.orderOut(nil)
            self.setupWindow = nil
            self.synchronizeMonitoring()
            self.refreshPresentation()
        }, changed: { [weak self] in self?.settingsChanged() }))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings() {
        guard settings.completedOnboarding else { showOnboarding(); return }
        popover.performClose(nil)
        helpfulPanel?.orderOut(nil)
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); return }
        model.setCaptureSuspended(true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 550), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preflight Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, model: model, catalog: catalog,
            changed: { [weak self] in self?.settingsChanged() }, demo: { [weak self] in self?.model.loadDemo() }))
        settingsWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func synchronizeMonitoring() {
        model.setAutomaticRecommendationsEnabled(settings.completedOnboarding && settings.automatic)
        model.setCaptureSuspended(!settings.completedOnboarding || setupWindow?.isVisible == true || settingsWindow?.isVisible == true)
    }

    private func settingsChanged() {
        synchronizeMonitoring()
        refreshPresentation()
    }

    private func refreshPresentation() {
        settings.monitoringStatus = model.captureStatus.description
        if model.hasUnreadRecommendation && popover.isShown {
            model.markRead()
            return
        }
        badge.isHidden = !model.hasUnreadRecommendation
        badge.color = model.hasError ? .systemOrange : .controlAccentColor
        let state = model.isLoading ? "Analyzing prompt" : model.hasUnreadRecommendation ? (model.hasError ? "Analysis needs attention" : "New recommendations") : "Ready"
        statusItem?.button?.toolTip = "Preflight · \(settings.mode.title) · \(state)"
        statusItem?.button?.setAccessibilityLabel("Preflight, \(settings.mode.title), \(state)")
        guard settings.mode == .helpful, !model.helpfulDismissed, !popover.isShown,
              settingsWindow?.isVisible != true, setupWindow?.isVisible != true,
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
            window.contentView = NSHostingView(rootView: HelpfulView(model: model, settings: settings, catalog: catalog, installer: installer, dismiss: { [weak self] in self?.model.dismissHelpful() }, review: { [weak self] in self?.showReview() }))
            helpfulPanel = window
        }
        let height = model.hasError ? 180.0 : min(480, 300 + Double(model.result?.skills.count ?? 0) * 64)
        helpfulPanel?.setFrame(PanelPlacement.frame(above: anchor, size: CGSize(width: 420, height: height), visibleFrame: screen.visibleFrame.insetBy(dx: 8, dy: 8)), display: true)
        // orderFront leaves the host's prompt as the key input. Never activate here.
        helpfulPanel?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
            synchronizeMonitoring()
        }
        if window === setupWindow {
            setupWindow = nil
            synchronizeMonitoring()
        }
    }
    func popoverDidClose(_ notification: Notification) { model.dismissHelpful() }
    @objc private func chooseStealth() { settings.mode = .stealth; settingsChanged() }
    @objc private func chooseHelpful() { settings.mode = .helpful; settingsChanged() }
    @objc private func toggleAutomatic() { settings.automatic.toggle(); settingsChanged() }
    @objc func demo() { model.loadDemo(); showReview() }
    @objc private func toggleLiveCapture() { model.setLiveCaptureEnabled(!model.liveCaptureEnabled) }
    @objc private func permission() { AccessibilityPermission.request() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        model.stopCapture()
        model.cancel()
    }
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
