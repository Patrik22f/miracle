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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .stealth
        automatic = defaults.object(forKey: "automaticRecommendations") as? Bool ?? true
        completedOnboarding = defaults.bool(forKey: "completedOnboarding")
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
