import AppKit
import Observation

enum DisplayMode: String, CaseIterable, Identifiable {
    case stealth, helpful
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .stealth ? "moon" : "sparkles" }
    var summary: String {
        self == .stealth
            ? "A quiet signal in your menu bar. Open it when you’re ready."
            : "Recommendations appear above your prompt, without interrupting your typing."
    }
}

@MainActor @Observable
final class AppSettings {
    private let defaults: UserDefaults
    var permissionGranted = false
    var monitoringStatus = "Waiting for Cursor"
    var mode: DisplayMode { didSet { defaults.set(mode.rawValue, forKey: "displayMode") } }
    var automatic: Bool { didSet { defaults.set(automatic, forKey: "automaticRecommendations") } }
    var completedOnboarding: Bool { didSet { defaults.set(completedOnboarding, forKey: "completedOnboarding") } }
    var cursorModelIDs: Set<String> { didSet { defaults.set(Array(cursorModelIDs), forKey: "cursorModelIDs") } }
    var cursorCustomEffort: Bool { didSet { defaults.set(cursorCustomEffort, forKey: "cursorCustomEffort") } }
    var detectCursorModels: Bool { didSet { defaults.set(detectCursorModels, forKey: "detectCursorModels") } }
    var installInProject: Bool { didSet { defaults.set(installInProject, forKey: "installInProject") } }
    var projectPath: String { didSet { defaults.set(projectPath, forKey: "skillProjectPath") } }

    func availableModels(for host: HostApp, catalog: ModelCatalog) -> [RecommendedModel] {
        catalog.models(for: host).filter {
            host != .cursor || (detectCursorModels && catalog.cursorDetected ? $0.enabled : cursorModelIDs.contains($0.id))
        }
    }

    func installRoot(for host: HostApp) -> URL? {
        if installInProject {
            guard !projectPath.isEmpty else { return nil }
            return URL(fileURLWithPath: projectPath).appendingPathComponent(host.skillsDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(host.skillsDirectory)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .helpful
        automatic = defaults.object(forKey: "automaticRecommendations") as? Bool ?? true
        completedOnboarding = defaults.bool(forKey: "completedOnboarding")
        cursorModelIDs = Set(defaults.stringArray(forKey: "cursorModelIDs") ?? ["grok-4.6"])
        cursorCustomEffort = defaults.bool(forKey: "cursorCustomEffort")
        detectCursorModels = defaults.object(forKey: "detectCursorModels") as? Bool ?? true
        installInProject = defaults.bool(forKey: "installInProject")
        projectPath = defaults.string(forKey: "skillProjectPath") ?? ""
    }
}

enum PanelPlacement {
    static func frame(above anchor: CGRect, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width)
        let above = anchor.maxY + 10
        let y = above + height <= visibleFrame.maxY ? above : anchor.minY - height - 10
        return CGRect(x: x, y: min(max(y, visibleFrame.minY), visibleFrame.maxY - height), width: width, height: height)
    }

    static func appKitRect(_ accessibilityRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: accessibilityRect.minX, y: primaryScreenHeight - accessibilityRect.maxY,
               width: accessibilityRect.width, height: accessibilityRect.height)
    }
}

final class RecommendationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
