import AppKit
import ApplicationServices
import Testing
@testable import Preflight

@MainActor @Test("Onboarding choice and pause survive relaunch")
func settingsPersist() throws {
    let name = "PreflightTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let first = AppSettings(defaults: defaults)
    #expect(!first.completedOnboarding)
    first.mode = .helpful
    first.automatic = false
    first.completedOnboarding = true
    let next = AppSettings(defaults: defaults)
    #expect(next.mode == .helpful)
    #expect(!next.automatic)
    #expect(next.completedOnboarding)
}

@Test("AI prompt monitoring accepts Cursor and Codex labels but excludes editors, search and secure fields")
func promptPolicy() {
    let cursor = "com.todesktop.230313mzl4w4u92"
    #expect(PromptPolicy.accepts(bundleID: cursor, role: kAXTextAreaRole, subrole: "", label: "Chat input"))
    #expect(PromptPolicy.accepts(bundleID: "com.openai.codex", role: kAXTextAreaRole, subrole: "", label: "Message Codex"))
    #expect(!PromptPolicy.accepts(bundleID: cursor, role: kAXTextAreaRole, subrole: "", label: "Editor content"))
    #expect(!PromptPolicy.accepts(bundleID: cursor, role: kAXTextAreaRole, subrole: "", label: "task.swift"))
    #expect(!PromptPolicy.accepts(bundleID: cursor, role: kAXTextAreaRole, subrole: "", label: "Code editor prompt.swift"))
    #expect(!PromptPolicy.accepts(bundleID: cursor, role: kAXTextFieldRole, subrole: "", label: "Search chat"))
    #expect(!PromptPolicy.accepts(bundleID: cursor, role: kAXTextFieldRole, subrole: kAXSecureTextFieldSubrole, label: "Prompt"))
    #expect(!PromptPolicy.accepts(bundleID: "com.apple.Notes", role: kAXTextAreaRole, subrole: "", label: "Chat"))
    #expect(PromptPolicy.accepts(bundleID: "com.openai.codex", role: kAXTextAreaRole, subrole: "", label: "Send a follow-up"))
    #expect(!PromptPolicy.accepts(bundleID: "com.openai.codex", role: kAXTextFieldRole, subrole: "", label: "Search chats"))
    #expect(!PromptPolicy.accepts(bundleID: "com.openai.codex", role: kAXTextAreaRole, subrole: kAXSecureTextFieldSubrole, label: "Prompt"))
}

@Test("Helpful placement respects edges and secondary displays")
func placement() {
    let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
    let above = PanelPlacement.frame(above: CGRect(x: -900, y: 200, width: 600, height: 100), size: CGSize(width: 420, height: 300), visibleFrame: screen)
    #expect(above.minY == 310)
    #expect(screen.contains(above))
    let below = PanelPlacement.frame(above: CGRect(x: -100, y: 880, width: 80, height: 100), size: CGSize(width: 420, height: 300), visibleFrame: screen)
    #expect(below.maxY == 870)
    #expect(screen.contains(below))
    let converted = PanelPlacement.appKitRect(CGRect(x: -800, y: -200, width: 400, height: 100), primaryScreenHeight: 900)
    #expect(converted.minY == 1000)
}

@MainActor @Test("Rapid edits send only the settled prompt, and unchanged polls do not repeat it")
func debounce() async throws {
    let recorder = AnalysisRecorder()
    let model = AppModel { text, _, _ in try await recorder.analyze(text) }
    let field = UUID()
    model.receive(snapshot("First prompt", field: field))
    let previous = model.task
    model.receive(snapshot("Final prompt", field: field))
    await previous?.value
    await model.task?.value
    #expect(await recorder.prompts == ["Final prompt"])
    #expect(model.result != nil)
    #expect(model.hasUnreadRecommendation)
    model.markRead()
    model.receive(snapshot("Final prompt", field: field, x: 40))
    #expect(!model.hasUnreadRecommendation)
    #expect(model.activeSnapshot?.bounds?.minX == 40)
    #expect(await recorder.prompts.count == 1)
}

@MainActor @Test("Leaving the prompt clears pending analysis and stale recommendations")
func focusLoss() async {
    let recorder = AnalysisRecorder()
    let model = AppModel { text, _, _ in try await recorder.analyze(text) }
    model.receive(snapshot("Pending prompt"))
    let pending = model.task
    model.receive(nil)
    await pending?.value
    #expect(await recorder.prompts.isEmpty)
    #expect(model.result == nil)
    #expect(!model.isLoading)
    #expect(!model.hasUnreadRecommendation)
    #expect(model.activeSnapshot == nil)
}

@MainActor @Test("Dismissal lasts for one prompt and new text clears results immediately")
func dismissal() async throws {
    let model = AppModel { _, _, _ in try .demo() }
    let field = UUID()
    model.receive(snapshot("Original", field: field))
    await model.task?.value
    model.dismissHelpful()
    model.receive(snapshot("Original", field: field))
    #expect(model.helpfulDismissed)
    model.receive(snapshot("Edited", field: field))
    #expect(!model.helpfulDismissed)
    #expect(model.result == nil)
    #expect(model.selected.isEmpty)
    #expect(!model.hasUnreadRecommendation)
    model.cancel()
}

@MainActor @Test("A late network response cannot restore a result after a prompt edit")
func staleResponse() async throws {
    let gate = AnalysisGate()
    let model = AppModel { _, _, _ in await gate.response() }
    model.editPrompt("Before edit")
    model.analyze()
    let pending = model.task
    await gate.waitUntilStarted()
    model.editPrompt("After edit")
    await gate.finish(try .demo())
    await pending?.value
    #expect(model.prompt == "After edit")
    #expect(model.result == nil)
    #expect(!model.hasUnreadRecommendation)
    #expect(model.isLoading) // The edited prompt is now scheduled automatically.
    model.cancel()
}

private func snapshot(_ text: String, field: UUID = UUID(), x: CGFloat = 0) -> PromptSnapshot {
    PromptSnapshot(text: text, appName: "Cursor", processID: 123, fieldID: field, bounds: CGRect(x: x, y: 100, width: 500, height: 100))
}

@MainActor @Test("Backend errors signal attention once and can be retried")
func analysisError() async {
    let model = AppModel { _, _, _ in throw ClientError.message("Offline") }
    let field = UUID()
    model.receive(snapshot("A prompt", field: field))
    await model.task?.value
    #expect(model.hasError)
    #expect(model.hasUnreadRecommendation)
    #expect(!model.isLoading)
    model.markRead()
    model.receive(snapshot("A prompt", field: field))
    #expect(!model.hasUnreadRecommendation)
    model.analyze()
    await model.task?.value
    #expect(model.hasUnreadRecommendation)
}

@MainActor @Test("An empty result still carries model and effort advice")
func emptyRecommendation() async throws {
    let fixture = try AnalyzeResponse.demo()
    let empty = AnalyzeResponse(schemaVersion: fixture.schemaVersion, requestId: "empty", analysis: fixture.analysis,
                                effort: fixture.effort, model: fixture.model, skills: [], meta: fixture.meta)
    let model = AppModel { _, _, _ in empty }
    model.editPrompt("Hello")
    model.analyze()
    await model.task?.value
    #expect(model.result?.skills.isEmpty == true)
    #expect(model.result?.effort.level == fixture.effort.level)
    #expect(model.hasUnreadRecommendation)
    #expect(!model.hasError)
}

@MainActor @Test("The same text in a different field starts a new prompt session")
func differentField() async {
    let recorder = AnalysisRecorder()
    let model = AppModel { text, _, _ in try await recorder.analyze(text) }
    model.receive(snapshot("Same text"))
    await model.task?.value
    model.dismissHelpful()
    model.receive(snapshot("Same text"))
    #expect(!model.helpfulDismissed)
    #expect(model.result == nil)
    await model.task?.value
    #expect(await recorder.prompts.count == 2)
}

private actor AnalysisRecorder {
    var prompts: [String] = []
    func analyze(_ text: String) throws -> AnalyzeResponse {
        prompts.append(text)
        return try .demo()
    }
}

private actor AnalysisGate {
    private var pending: CheckedContinuation<AnalyzeResponse, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func response() async -> AnalyzeResponse {
        await withCheckedContinuation {
            pending = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ response: AnalyzeResponse) { pending?.resume(returning: response); pending = nil }
}

@Test("Composer labels can vary without requiring a specific English placeholder")
func composerLabels() {
    for label in ["Ask", "Message", "Describe your task", "Build anything", "What would you like to do?"] {
        #expect(PromptPolicy.accepts(bundleID: "com.todesktop.230313mzl4w4u92", role: kAXTextAreaRole, subrole: "", label: label))
    }
    #expect(PromptPolicy.accepts(bundleID: "com.openai.codex", role: kAXTextAreaRole, subrole: "", label: ""))
    #expect(!PromptPolicy.accepts(bundleID: "com.todesktop.230313mzl4w4u92", role: kAXTextAreaRole, subrole: "", label: ""))
}
