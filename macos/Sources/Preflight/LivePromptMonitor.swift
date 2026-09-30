import AppKit

@MainActor
struct CaptureEnvironment {
    var isTrusted: () -> Bool
    var frontmostSource: () -> PromptSource?
    var ownProcessID: Int32

    static var system: Self {
        Self(isTrusted: { AccessibilityPermission.isGranted }, frontmostSource: {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return PromptSource(processID: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                                name: app.localizedName ?? "Unknown app")
        }, ownProcessID: ProcessInfo.processInfo.processIdentifier)
    }
}

/// Serial, cancellable sampling works with editors that don't emit AX change
/// notifications. At most one read is in flight; only changed values reach UI.
@MainActor
final class LivePromptMonitor: NSObject {
    var onReading: ((CaptureReading) -> Void)?
    private let reader: any FocusedTextReading
    private let environment: CaptureEnvironment
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var previousReading: CaptureReading?
    private var sessionActive = true
    private var displayAwake = true

    init(reader: any FocusedTextReading = FocusedTextReader(), environment: CaptureEnvironment = .system) {
        self.reader = reader
        self.environment = environment
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sessionInactive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(displaySleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displayWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    deinit { task?.cancel() }

    func start() {
        guard task == nil else { return }
        generation = UUID()
        previousReading = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.poll() else { return }
                do { try await Task.sleep(for: delay) } catch { return }
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        previousReading = nil
    }

    func sample(mode: CaptureMode = .live) async -> CaptureReading {
        let current = generation
        guard sessionActive, displayAwake else { return .status(.suspended) }
        guard environment.isTrusted() else { return .status(.permissionRequired) }
        guard let source = environment.frontmostSource() else { return .status(.waiting) }
        guard source.processID != environment.ownProcessID else { return .status(.reviewing) }
        let reading = await reader.read(from: source, mode: mode)
        guard !Task.isCancelled, current == generation, sessionActive, displayAwake else { return .status(.waiting) }
        guard environment.isTrusted() else { return .status(.permissionRequired) }
        guard environment.frontmostSource() == source else { return .status(.waiting) }
        return reading
    }

    private func poll() async -> Duration {
        let current = generation
        let reading = await sample()
        guard !Task.isCancelled, current == generation else { return .seconds(1) }
        if previousReading != reading {
            previousReading = reading
            onReading?(reading)
        }
        switch reading {
        case .captured: return .milliseconds(350)
        case .status(.permissionRequired), .status(.suspended): return .seconds(2)
        default: return .seconds(1)
        }
    }

    @objc private func sessionInactive() { sessionActive = false; generation = UUID() }
    @objc private func sessionActivated() { sessionActive = true; generation = UUID() }
    @objc private func displaySleeping() { displayAwake = false; generation = UUID() }
    @objc private func displayWoke() { displayAwake = true; generation = UUID() }
}
