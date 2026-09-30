import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    var prompt = ""
    var sourceApp: String?
    var result: AnalyzeResponse?
    var selected: Set<String> = []
    var isLoading = false
    var message: String?
    var demoMode = false
    var activeSnapshot: PromptSnapshot?
    var hasUnreadRecommendation = false
    var helpfulDismissed = false
    var hasError = false
    @ObservationIgnored var presentationChanged: () -> Void = {}
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    private var revision = UUID()
    private let analyzePrompt: @Sendable (String, String?) async throws -> AnalyzeResponse

    init(analyzePrompt: @escaping @Sendable (String, String?) async throws -> AnalyzeResponse = {
        try await APIClient().analyze(prompt: $0, app: $1)
    }) { self.analyzePrompt = analyzePrompt }

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

    func editPrompt(_ text: String) {
        activeSnapshot = nil
        sourceApp = nil
        invalidate()
        prompt = text
    }

    func receive(_ snapshot: PromptSnapshot?) {
        guard let snapshot else {
            if activeSnapshot != nil {
                activeSnapshot = nil
                invalidate()
                prompt = ""
                sourceApp = nil
            }
            return
        }
        if let activeSnapshot, snapshot.matchesContent(of: activeSnapshot) {
            self.activeSnapshot = snapshot
            presentationChanged()
            return
        }
        invalidate()
        activeSnapshot = snapshot
        helpfulDismissed = false
        prompt = snapshot.text
        sourceApp = snapshot.appName
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

    func capture() {
        activeSnapshot = nil
        invalidate()
        prompt = ""
        sourceApp = nil
        do {
            let captured = try FocusedText.capture()
            prompt = captured.text
            sourceApp = captured.appName
            analyze()
        } catch { message = error.localizedDescription; hasError = true; presentationChanged() }
    }

    func analyze() { analyze(after: .zero) }

    private func analyze(after delay: Duration) {
        invalidate()
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 12000 else {
            message = "Enter a prompt of 1–12,000 characters."
            hasError = true
            presentationChanged()
            return
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
                self.message = "\(error.localizedDescription) Start the API with npm start, or turn on Demo mode."
                self.hasError = true
                self.hasUnreadRecommendation = true
                self.presentationChanged()
            }
        }
    }

    func loadDemo() {
        invalidate()
        activeSnapshot = nil
        demoMode = true
        sourceApp = nil
        prompt = "Optimize this Next.js page. It is slow when rendering 500 products."
        analyze()
    }

    func copy(includeSkills: Bool) {
        var output = prompt
        if includeSkills, let result {
            let chosen = result.skills.filter { selected.contains($0.id) }
            if !chosen.isEmpty {
                output += "\n\nSuggested public Agent Skills (review their SKILL.md and use only if relevant):\n"
                output += chosen.map { "- \($0.name): \($0.url.absoluteString)" }.joined(separator: "\n")
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        message = "Copied. Paste into your AI app, review, and send."
        hasError = false
        markRead()
    }
}
