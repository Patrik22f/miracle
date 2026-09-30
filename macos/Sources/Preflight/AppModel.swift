import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var prompt = ""
    private(set) var source: PromptSource?
    var sourceApp: String? { source?.name }
    var result: AnalyzeResponse?
    var selected: Set<String> = []
    var isLoading = false
    var message: String?
    private(set) var demoMode = false
    private(set) var liveCaptureEnabled: Bool
    private(set) var captureStatus: CaptureStatus = .waiting
    private(set) var automaticRecommendationsEnabled = true
    private(set) var activeSnapshot: PromptSnapshot?
    var hasUnreadRecommendation = false
    var helpfulDismissed = false
    var hasError = false
    var targetApp: HostApp? { demoMode ? .cursor : HostApp.detect(source) }
    @ObservationIgnored var presentationChanged: () -> Void = {}
    @ObservationIgnored var permissionChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored private let monitor: LivePromptMonitor
    @ObservationIgnored private let analyzePrompt: @Sendable (String, String?) async throws -> AnalyzeResponse
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    private var captureStarted = false
    private var captureSuspended = false
    private var lastFieldID: UUID?
    private var revision = UUID()

    init(monitor: LivePromptMonitor = LivePromptMonitor(), preferences: UserDefaults? = nil,
         analyzePrompt: @escaping @Sendable (String, String?) async throws -> AnalyzeResponse = {
             try await APIClient().analyze(prompt: $0, app: $1)
         }) {
        self.monitor = monitor
        self.analyzePrompt = analyzePrompt
        self.liveCaptureEnabled = true
        preferences?.removeObject(forKey: "liveCaptureEnabled")
        monitor.onReading = { [weak self] reading in self?.receiveCapture(reading) }
        monitor.onPermission = { [weak self] granted in self?.permissionChanged(granted) }
        monitor.isEnabled = { [weak self] in
            guard let self else { return false }
            return self.liveCaptureEnabled && !self.demoMode && !self.captureSuspended
        }
    }

    func startCapture() {
        captureStarted = true
        synchronizeCapture()
    }

    func stopCapture() {
        captureStarted = false
        monitor.stop()
    }

    func setLiveCaptureEnabled(_ enabled: Bool) {
        liveCaptureEnabled = enabled
        if !enabled { endAutomaticSession() }
        synchronizeCapture()
    }

    func setAutomaticRecommendationsEnabled(_ enabled: Bool) {
        guard automaticRecommendationsEnabled != enabled else { return }
        automaticRecommendationsEnabled = enabled
        if !enabled { endAutomaticSession() }
        synchronizeCapture()
    }

    func setCaptureSuspended(_ suspended: Bool) {
        guard captureSuspended != suspended else { return }
        captureSuspended = suspended
        if suspended { endAutomaticSession() }
        synchronizeCapture()
    }

    private func synchronizeCapture() {
        // Keep checking permission while paused or in setup, without reading text.
        monitor.stop()
        if !liveCaptureEnabled || demoMode { captureStatus = .paused }
        else if captureSuspended { captureStatus = .reviewing }
        else { captureStatus = AccessibilityPermission.isGranted ? .waiting : .permissionRequired }
        if captureStarted { monitor.start() }
        presentationChanged()
    }

    func receiveCapture(_ reading: CaptureReading) {
        guard liveCaptureEnabled, !demoMode, !captureSuspended else { return }
        captureStatus = reading.status
        switch reading {
        case .captured(let captured): applyCapture(captured)
        case .status(.reviewing): break // Keep the prompt while reviewing it in Preflight.
        case .status: receive(nil)
        }
        presentationChanged()
    }

    private func applyCapture(_ captured: CapturedPrompt) {
        if liveCaptureEnabled, automaticRecommendationsEnabled, let snapshot = captured.automaticSnapshot {
            receive(snapshot)
            return
        }
        guard prompt != captured.text || source != captured.source || lastFieldID != captured.fieldID || activeSnapshot != nil else { return }
        activeSnapshot = nil
        invalidate()
        prompt = captured.text
        source = captured.source
        lastFieldID = captured.fieldID
    }

    func editPrompt(_ text: String) {
        guard text != prompt else { return }
        // Internal draft updates must not be overwritten by an in-flight capture.
        liveCaptureEnabled = false
        endAutomaticSession()
        synchronizeCapture()
        invalidate()
        source = nil
        lastFieldID = nil
        prompt = text
    }

    func setDemoMode(_ enabled: Bool) {
        activeSnapshot = nil
        invalidate()
        demoMode = enabled
        synchronizeCapture()
    }

    func cancel() {
        task?.cancel()
        task = nil
        revision = UUID()
        isLoading = false
        presentationChanged()
    }

    func invalidate() {
        cancel()
        result = nil
        selected = []
        message = nil
        hasError = false
        hasUnreadRecommendation = false
        presentationChanged()
    }

    private func endAutomaticSession() {
        guard activeSnapshot != nil else { return }
        activeSnapshot = nil
        invalidate()
    }

    func receive(_ snapshot: PromptSnapshot?) {
        guard let snapshot else {
            if activeSnapshot != nil {
                endAutomaticSession()
                prompt = ""
                source = nil
                lastFieldID = nil
            }
            return
        }
        guard liveCaptureEnabled, automaticRecommendationsEnabled, !demoMode, !captureSuspended else { return }
        if let activeSnapshot, snapshot.matchesContent(of: activeSnapshot) {
            self.activeSnapshot = snapshot
            presentationChanged()
            return
        }
        invalidate()
        activeSnapshot = snapshot
        helpfulDismissed = false
        prompt = snapshot.text
        source = PromptSource(processID: snapshot.processID, bundleIdentifier: snapshot.bundleIdentifier, name: snapshot.appName)
        lastFieldID = snapshot.fieldID
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        analyze(after: .milliseconds(900))
    }

    func markRead() {
        hasUnreadRecommendation = false
        presentationChanged()
    }

    func dismissHelpful() {
        helpfulDismissed = true
        markRead()
    }

    func capture() async {
        // Freeze an explicitly selected excerpt until live capture is resumed.
        setLiveCaptureEnabled(false)
        invalidate()
        let current = revision
        let reading = await monitor.sample(mode: .selectionPreferred)
        guard !Task.isCancelled, revision == current else { return }
        if case .captured(let captured) = reading {
            applyCapture(captured)
            analyze()
        } else {
            message = reading.status.description
            hasError = true
            presentationChanged()
        }
    }

    @discardableResult
    func analyze() -> Task<Void, Never>? { analyze(after: .zero) }

    @discardableResult
    private func analyze(after delay: Duration) -> Task<Void, Never>? {
        invalidate()
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= PromptTextPolicy.maximumLength else {
            message = "Enter a prompt of 1–12,000 characters."
            hasError = true
            presentationChanged()
            return nil
        }
        let current = revision
        let useDemo = demoMode
        let app = sourceApp
        let analyzePrompt = analyzePrompt
        isLoading = true
        presentationChanged()
        task = Task { [weak self] in
            do {
                if delay != .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                let response: AnalyzeResponse
                if useDemo { response = try .demo() }
                else { response = try await analyzePrompt(text, app) }
                guard !Task.isCancelled, let self, self.revision == current else { return }
                self.result = response
                self.selected = Set(response.skills.map(\.id))
                self.isLoading = false
                self.hasUnreadRecommendation = true
                self.presentationChanged()
            } catch {
                guard !Task.isCancelled, let self, self.revision == current else { return }
                self.isLoading = false
                self.message = error.localizedDescription
                self.hasError = true
                self.hasUnreadRecommendation = true
                self.presentationChanged()
            }
        }
        return task
    }

    func loadDemo() {
        setDemoMode(true)
        source = nil
        lastFieldID = nil
        prompt = "Optimize this Next.js page. It is slow when rendering 500 products."
        analyze()
    }

    func copy(includeSkills: Bool) {
        let output = promptWithSkills(includeSkills: includeSkills)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        message = "Copied"
        hasError = false
        markRead()
    }

    func promptWithSkills(includeSkills: Bool) -> String {
        var output = prompt
        if includeSkills, let result {
            let chosen = result.skills.filter { selected.contains($0.id) }
            if !chosen.isEmpty {
                output += "\n\nSuggested Agent Skills (read their SKILL.md and use only if relevant):\n"
                output += chosen.map { skill in
                    let location = skill.url.isFileURL ? skill.url.path : skill.url.absoluteString
                    return "- \(skill.name): \(location)"
                }.joined(separator: "\n")
            }
        }
        return output
    }
}
