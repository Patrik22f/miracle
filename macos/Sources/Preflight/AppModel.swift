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
    private var task: Task<Void, Never>?
    private var revision = UUID()

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

    func capture() {
        invalidate()
        prompt = ""
        sourceApp = nil
        do {
            let captured = try FocusedText.capture()
            prompt = captured.text
            sourceApp = captured.appName
            analyze()
        } catch { message = error.localizedDescription }
    }

    func analyze() {
        invalidate()
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 12000 else {
            message = "Enter a prompt of 1–12,000 characters."
            return
        }
        let current = revision
        let useDemo = demoMode
        let app = sourceApp
        isLoading = true
        task = Task { [weak self] in
            do {
                let response: AnalyzeResponse
                if useDemo { response = try .demo() }
                else { response = try await APIClient().analyze(prompt: text, app: app) }
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
    }

    func loadDemo() {
        invalidate()
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
    }
}
