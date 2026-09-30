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
    @ObservationIgnored private let monitor: LivePromptMonitor
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let analyzePrompt: @Sendable (String, String?) async throws -> AnalyzeResponse
    private var captureStarted = false
    private var task: Task<Void, Never>?
    private var revision = UUID()

    init(monitor: LivePromptMonitor = LivePromptMonitor(), preferences: UserDefaults? = nil,
         analyzePrompt: @escaping @Sendable (String, String?) async throws -> AnalyzeResponse = {
             try await APIClient().analyze(prompt: $0, app: $1)
         }) {
        self.monitor = monitor
        self.preferences = preferences
        self.analyzePrompt = analyzePrompt
        self.liveCaptureEnabled = preferences?.object(forKey: "liveCaptureEnabled") as? Bool ?? true
        if !liveCaptureEnabled { captureStatus = .paused }
        monitor.onReading = { [weak self] reading in self?.receiveCapture(reading) }
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
        preferences?.set(enabled, forKey: "liveCaptureEnabled")
        synchronizeCapture()
    }

    private func synchronizeCapture() {
        guard liveCaptureEnabled, !demoMode else {
            monitor.stop()
            captureStatus = .paused
            return
        }
        captureStatus = AccessibilityPermission.isGranted ? .waiting : .permissionRequired
        if captureStarted { monitor.start() }
    }

    func receiveCapture(_ reading: CaptureReading) {
        guard liveCaptureEnabled, !demoMode else { return }
        captureStatus = reading.status
        if case .captured(let captured) = reading { applyCapture(captured) }
    }

    private func applyCapture(_ captured: CapturedPrompt) {
        guard prompt != captured.text || source != captured.source else { return }
        invalidate()
        prompt = captured.text
        source = captured.source
    }

    func editPrompt(_ text: String) {
        guard text != prompt else { return }
        setLiveCaptureEnabled(false)
        invalidate()
        source = nil
        prompt = text
    }

    func setDemoMode(_ enabled: Bool) {
        invalidate()
        demoMode = enabled
        synchronizeCapture()
    }

    func cancel() {
        task?.cancel()
        task = nil
        revision = UUID()
        isLoading = false
    }

    func invalidate() {
        cancel()
        result = nil
        selected = []
        message = nil
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
        }
    }

    @discardableResult
    func analyze() -> Task<Void, Never>? {
        invalidate()
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= PromptTextPolicy.maximumLength else {
            message = "Enter a prompt of 1–12,000 characters."
            return nil
        }
        let current = revision
        let useDemo = demoMode
        let app = sourceApp
        let analyzePrompt = analyzePrompt
        isLoading = true
        task = Task { [weak self] in
            do {
                let response: AnalyzeResponse
                if useDemo { response = try .demo() }
                else { response = try await analyzePrompt(text, app) }
                guard !Task.isCancelled, let self, self.revision == current else { return }
                self.result = response
                self.selected = Set(response.skills.map(\.id))
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.revision == current else { return }
                self.isLoading = false
                self.message = "\(error.localizedDescription) Start the API with npm start, or turn on Demo mode."
            }
        }
        return task
    }

    func loadDemo() {
        setDemoMode(true)
        source = nil
        prompt = "Optimize this Next.js page. It is slow when rendering 500 products."
        analyze()
    }

    func copy(includeSkills: Bool) {
        let output = promptWithSkills(includeSkills: includeSkills)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        message = "Copied. Paste into your AI app, review, and send."
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
