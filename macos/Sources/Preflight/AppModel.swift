import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    let suggestions: PromptSuggestionsModel
    private(set) var prompt = ""
    private(set) var source: PromptSource?
    private(set) var context: ConversationContext?
    var contextText: String { context?.text ?? "" }
    var contextLabel: String {
        guard let context else { return "Chat context unavailable · Add context" }
        return context.source == "manual" ? "Added chat context" : "Visible chat context · Review"
    }
    var sourceApp: String? { source?.name }
    var result: AnalyzeResponse?
    var selected: Set<String> = []
    var isLoading = false
    var message: String?
    private(set) var demoMode = false
    private(set) var demoInstalledSkills: Set<String> = []
    private(set) var liveCaptureEnabled: Bool
    private(set) var captureStatus: CaptureStatus = .waiting
    private(set) var automaticRecommendationsEnabled = true
    private(set) var activeSnapshot: PromptSnapshot?
    var hasUnreadRecommendation = false
    var helpfulDismissed = false
    var hasError = false
    var targetApp: HostApp? { HostApp.detect(source) ?? (manuallyEdited ? draftHost : nil) }
    @ObservationIgnored var presentationChanged: () -> Void = {}
    @ObservationIgnored var permissionChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored private let monitor: LivePromptMonitor
    @ObservationIgnored private let analyzePrompt: @Sendable (String, String?, ConversationContext?) async throws -> AnalyzeResponse
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    private var captureStarted = false
    private var captureSuspended = false
    private var lastFieldID: UUID?
    private var revision = UUID()
    private var automaticTask = false
    private var manuallyEdited = false
    private var draftHost: HostApp?
    private var lastSuggestionIDs: [String] = []

    init(monitor: LivePromptMonitor = LivePromptMonitor(), preferences: UserDefaults? = nil,
         analyzePrompt: @escaping @Sendable (String, String?, ConversationContext?) async throws -> AnalyzeResponse = {
             try await APIClient().analyze(prompt: $0, app: $1, context: $2)
         }) {
        self.monitor = monitor
        self.suggestions = PromptSuggestionsModel(preferences: preferences)
        self.analyzePrompt = analyzePrompt
        self.liveCaptureEnabled = true
        preferences?.removeObject(forKey: "liveCaptureEnabled")
        monitor.onReading = { [weak self] reading in self?.receiveCapture(reading) }
        monitor.onPermission = { [weak self] granted in self?.permissionChanged(granted) }
        monitor.isEnabled = { [weak self] in
            guard let self else { return false }
            return self.liveCaptureEnabled && !self.captureSuspended
        }
        suggestions.changed = { [weak self] in
            guard let self else { return }
            let ids = self.suggestions.response?.suggestions.map(\.id) ?? []
            if !ids.isEmpty, ids != self.lastSuggestionIDs {
                self.lastSuggestionIDs = ids
                self.hasUnreadRecommendation = true
            }
            self.presentationChanged()
        }
    }

    func startCapture() {
        captureStarted = true
        synchronizeCapture()
    }

    func stopCapture() {
        captureStarted = false
        monitor.stop()
        suggestions.setRunning(false)
    }

    func setLiveCaptureEnabled(_ enabled: Bool) {
        liveCaptureEnabled = enabled
        if enabled { manuallyEdited = false; draftHost = nil }
        if !enabled { endAutomaticSession(); if automaticTask { invalidate() } }
        synchronizeCapture()
        if enabled { scheduleAutomaticAnalysis() }
    }

    func setAutomaticRecommendationsEnabled(_ enabled: Bool) {
        guard automaticRecommendationsEnabled != enabled else { return }
        automaticRecommendationsEnabled = enabled
        if !enabled { endAutomaticSession(); if automaticTask { invalidate() } }
        synchronizeCapture()
        if enabled { scheduleAutomaticAnalysis() }
    }

    func setCaptureSuspended(_ suspended: Bool) {
        guard captureSuspended != suspended else { return }
        captureSuspended = suspended
        if suspended { endAutomaticSession(); if automaticTask { invalidate() } }
        synchronizeCapture()
        if !suspended { scheduleAutomaticAnalysis() }
    }

    private func synchronizeCapture() {
        // Keep checking permission while paused or in setup, without reading text.
        monitor.stop()
        if !liveCaptureEnabled { captureStatus = .paused }
        else if captureSuspended { captureStatus = .reviewing }
        else { captureStatus = AccessibilityPermission.isGranted ? .waiting : .permissionRequired }
        if captureStarted { monitor.start() }
        suggestions.setRunning(captureStarted && automaticRecommendationsEnabled && !demoMode && !captureSuspended)
        presentationChanged()
    }

    func receiveCapture(_ reading: CaptureReading) {
        guard liveCaptureEnabled, !captureSuspended else { return }
        captureStatus = reading.status
        switch reading {
        case .captured(let captured): applyCapture(captured)
        case .status(.reviewing): break // Keep the prompt while reviewing it in Miracle.
        case .status: receive(nil)
        }
        presentationChanged()
    }

    private func applyCapture(_ captured: CapturedPrompt) {
        defer { updateSuggestions(detectedProjectPath: captured.projectPath) }
        manuallyEdited = false
        if liveCaptureEnabled, automaticRecommendationsEnabled, let snapshot = captured.automaticSnapshot {
            receive(snapshot)
            return
        }
        guard prompt != captured.text || source != captured.source || lastFieldID != captured.fieldID || context != captured.context || activeSnapshot != nil else { return }
        activeSnapshot = nil
        invalidate()
        prompt = captured.text
        source = captured.source
        context = captured.context
        lastFieldID = captured.fieldID
    }

    func editPrompt(_ text: String) {
        guard text != prompt else { return }
        pauseCaptureForEditing()
        invalidate()
        source = nil
        lastFieldID = nil
        prompt = text
        scheduleAutomaticAnalysis()
        updateSuggestions(detectedProjectPath: suggestions.detectedProjectPath)
    }

    private func pauseCaptureForEditing() {
        // Manual prompt and context edits pause this session, not the saved launch preference.
        draftHost = targetApp
        liveCaptureEnabled = false
        manuallyEdited = true
        endAutomaticSession()
        synchronizeCapture()
    }

    func editContext(_ text: String) {
        guard text != contextText else { return }
        pauseCaptureForEditing()
        invalidate()
        context = ConversationContext.snapshot(text, id: context?.conversationId ?? UUID().uuidString, source: "manual")
        scheduleAutomaticAnalysis()
        updateSuggestions(detectedProjectPath: suggestions.detectedProjectPath)
    }

    func setDemoMode(_ enabled: Bool) {
        activeSnapshot = nil
        invalidate()
        demoMode = enabled
        context = nil
        manuallyEdited = false
        liveCaptureEnabled = true
        demoInstalledSkills = []
        if !enabled {
            prompt = ""
            source = nil
            lastFieldID = nil
            updateSuggestions(detectedProjectPath: nil)
        }
        suggestions.setDemoMode(enabled)
        synchronizeCapture()
    }

    func installDemoSkills(_ ids: Set<String>) {
        guard demoMode else { return }
        demoInstalledSkills.formUnion(ids.intersection(Set(DemoCatalog.skills.map(\.id))))
        presentationChanged()
    }

    func cancel() {
        task?.cancel()
        task = nil
        automaticTask = false
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
        defer { updateSuggestions(detectedProjectPath: snapshot?.projectPath) }
        guard let snapshot else {
            if context != nil { context = nil; invalidate() }
            if activeSnapshot != nil {
                endAutomaticSession()
                prompt = ""
                source = nil
                lastFieldID = nil
            }
            return
        }
        guard liveCaptureEnabled, automaticRecommendationsEnabled, !captureSuspended else { return }
        if let activeSnapshot, snapshot.matchesContent(of: activeSnapshot) {
            self.activeSnapshot = snapshot
            presentationChanged()
            return
        }
        invalidate()
        activeSnapshot = snapshot
        manuallyEdited = false
        helpfulDismissed = false
        prompt = snapshot.text
        source = PromptSource(processID: snapshot.processID, bundleIdentifier: snapshot.bundleIdentifier, name: snapshot.appName)
        lastFieldID = snapshot.fieldID
        context = snapshot.context
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scheduleAutomaticAnalysis()
    }

    private func updateSuggestions(detectedProjectPath: String?) {
        let recognized = source == nil || HostApp.detect(source) != nil
        suggestions.update(prompt: recognized ? prompt : "", context: recognized ? context : nil,
                           detectedProjectPath: detectedProjectPath)
    }

    func useSuggestion(_ suggestion: PromptSuggestion) {
        editPrompt(suggestion.prompt)
    }

    private func scheduleAutomaticAnalysis() {
        guard automaticRecommendationsEnabled, !captureSuspended,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source == nil || activeSnapshot != nil || manuallyEdited else { return }
        analyze(after: .milliseconds(300))
        automaticTask = task != nil
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
        let app = targetApp?.title
        let context = context
        let analyzePrompt = analyzePrompt
        isLoading = true
        presentationChanged()
        task = Task { [weak self] in
            do {
                if delay != .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                let response: AnalyzeResponse
                if useDemo { response = DemoCatalog.analyze(text) }
                else { response = try await analyzePrompt(text, app, context) }
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
        prompt = ""
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
                    let rank = skill.id == result.bestSkill?.id ? " (best match from the skill library)" : ""
                    return "- \(skill.name): \(location)\(rank)"
                }.joined(separator: "\n")
                if chosen.contains(where: { $0.id == result.bestSkill?.id }) {
                    output += "\nMention the best match by name and source when responding."
                }
            }
        }
        return output
    }
}
